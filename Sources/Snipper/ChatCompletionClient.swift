import Foundation

enum ChatCompletionError: Error, LocalizedError, Equatable {
    case missingModel, missingKey, invalidKey, keychainUnavailable
    case httpStatus(Int), invalidResponse, emptyResponse, outputLimit, timeout, network

    var errorDescription: String? {
        switch self {
        case .missingModel: "Enter an OpenRouter model ID first."
        case .missingKey: "No saved API key. Save your key in Keychain first."
        case .invalidKey: "The saved API key contains invalid characters. Save a valid key."
        case .keychainUnavailable: "Could not read the API key from Keychain. Check Keychain access and try again."
        case .httpStatus(let code):
            switch code {
            case 400, 404, 422: "OpenRouter rejected the model or request (HTTP \(code)). Check the model ID and its supported parameters."
            case 401: "Authentication failed (HTTP 401). Check the saved API key."
            case 402: "Insufficient credits or quota (HTTP 402). Check your OpenRouter balance and key limits."
            case 403: "Access denied (HTTP 403). Check key permissions, model access, or provider policy."
            case 408, 504, 524: "The provider timed out (HTTP \(code)). No automatic retry was made."
            case 429: "Rate limited (HTTP 429). Wait before testing again."
            case 500...599: "OpenRouter or its provider is unavailable (HTTP \(code)). Try again later."
            case 300...399: "The endpoint attempted a redirect. It was blocked to protect the API key."
            default: "OpenRouter request failed (HTTP \(code)). No automatic retry was made."
            }
        case .invalidResponse: "The server did not return a valid chat-completion response."
        case .emptyResponse: "The model returned no visible text. A reasoning model may have exhausted this small test's output budget."
        case .outputLimit: "The model reached the test's output limit. Choose a model that can answer this small sample without lengthy reasoning."
        case .timeout: "The connection test timed out after 30 seconds. No automatic retry was made."
        case .network: "Could not reach OpenRouter securely. Check your network connection and try again."
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward an API key to a redirect destination.
        completionHandler(nil)
    }
}

/// OpenAI-compatible chat transport. No logging, caching, cookies, or retries.
struct ChatCompletionClient: Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = ChatCompletionClient.liveTransport) {
        self.transport = transport
    }

    func complete(model: String, apiKey: String, messages: [Message], maxCompletionTokens: Int) async throws -> String {
        let request = try Self.makeRequest(model: model, apiKey: apiKey, messages: messages, maxCompletionTokens: maxCompletionTokens)
        try Task.checkCancellation()
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut { throw ChatCompletionError.timeout }
            if let safeError = error as? ChatCompletionError { throw safeError }
            // Never expose raw networking errors, URLs, request headers, or bodies.
            throw ChatCompletionError.network
        }
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw ChatCompletionError.httpStatus(response.statusCode) }
        guard data.count <= 1_048_576,
              let result = try? JSONDecoder().decode(Completion.self, from: data) else {
            throw ChatCompletionError.invalidResponse
        }
        // Some providers return a structured error with HTTP 200. Ignore its raw message.
        if let error = result.error {
            if let code = error.code, (400...599).contains(code) { throw ChatCompletionError.httpStatus(code) }
            throw ChatCompletionError.invalidResponse
        }
        guard let choice = result.choices?.first else { throw ChatCompletionError.invalidResponse }
        if choice.finishReason == "length" { throw ChatCompletionError.outputLimit }
        guard let text = choice.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ChatCompletionError.emptyResponse
        }
        return text
    }

    static func makeRequest(model: String, apiKey: String, messages: [Message], maxCompletionTokens: Int) throws -> URLRequest {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ChatCompletionError.missingModel }
        guard !key.isEmpty else { throw ChatCompletionError.missingKey }
        guard key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { throw ChatCompletionError.invalidKey }
        var request = URLRequest(url: AppSettings.openRouterBaseURL.appendingPathComponent("chat/completions"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.httpBody = try JSONEncoder().encode(Payload(model: model, messages: messages, maxCompletionTokens: maxCompletionTokens))
        return request
    }

    private struct Payload: Encodable {
        let model: String
        let messages: [Message]
        let maxCompletionTokens: Int
        let stream = false

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case maxCompletionTokens = "max_completion_tokens"
        }
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct ResponseMessage: Decodable { let content: String? }
            let message: ResponseMessage?
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        struct ServiceError: Decodable {
            let code: Int?
            enum CodingKeys: String, CodingKey { case code }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let value = try? container.decode(Int.self, forKey: .code) {
                    code = value
                } else {
                    code = (try? container.decode(String.self, forKey: .code)).flatMap(Int.init)
                }
            }
        }
        let choices: [Choice]?
        let error: ServiceError?
    }

    private static let liveSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    private static let liveTransport: Transport = { request in
        let (data, response) = try await liveSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatCompletionError.invalidResponse }
        return (data, response)
    }
}
