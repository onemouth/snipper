import Foundation
import Testing
@testable import Snipper

private func response(_ request: URLRequest, status: Int = 200, body: String = #"{"choices":[{"message":{"content":"你好。"},"finish_reason":"stop"}]}"#) -> (Data, HTTPURLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private let testMessages = [ChatCompletionClient.Message(role: "user", content: "Hello.")]

struct ChatCompletionClientTests {
    @Test func buildsSecureNonStreamingRequest() throws {
        let request = try ChatCompletionClient.makeRequest(model: " example/model \n", apiKey: " fake-test-key ", messages: testMessages, maxCompletionTokens: 256)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 30)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "example/model")
        #expect(payload["stream"] as? Bool == false)
        #expect(payload["max_completion_tokens"] as? Int == 256)
        #expect(payload["tools"] == nil)
    }

    @Test func rejectsMissingConfigurationBeforeTransport() async throws {
        let client = ChatCompletionClient { _ in
            Issue.record("Transport must not run for invalid configuration")
            throw URLError(.badURL)
        }
        await #expect(throws: ChatCompletionError.missingModel) {
            try await client.complete(model: " ", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
        await #expect(throws: ChatCompletionError.missingKey) {
            try await client.complete(model: "example/model", apiKey: "", messages: testMessages, maxCompletionTokens: 256)
        }
        await #expect(throws: ChatCompletionError.invalidKey) {
            try await client.complete(model: "example/model", apiKey: "fake\ninjected", messages: testMessages, maxCompletionTokens: 256)
        }
    }

    @Test func acceptsVisibleCompletion() async throws {
        let client = ChatCompletionClient { request in response(request) }
        let text = try await client.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        #expect(text == "你好。")
    }

    @Test(arguments: [302, 400, 401, 402, 403, 404, 408, 422, 429, 500, 502, 503, 524])
    func sanitizesHTTPFailures(status: Int) async throws {
        let client = ChatCompletionClient { request in
            response(request, status: status, body: #"{"error":{"message":"secret-that-must-not-be-displayed"}}"#)
        }
        do {
            _ = try await client.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
            Issue.record("Expected HTTP error")
        } catch let error as ChatCompletionError {
            #expect(error == .httpStatus(status))
            #expect(!error.localizedDescription.contains("secret-that-must-not-be-displayed"))
        }
    }

    @Test func recognizesEmbeddedErrorEvenWithHTTP200() async throws {
        let client = ChatCompletionClient { request in
            response(request, body: #"{"error":{"code":"402","message":"private provider payload"},"choices":[]}"#)
        }
        await #expect(throws: ChatCompletionError.httpStatus(402)) {
            try await client.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
    }

    @Test(arguments: [
        (#"{"choices":[{"message":{"content":" "}}]}"#, ChatCompletionError.emptyResponse),
        (#"{"choices":[{"message":{"content":null}}]}"#, ChatCompletionError.emptyResponse),
        (#"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#, ChatCompletionError.outputLimit),
        (#"{"choices":[]}"#, ChatCompletionError.invalidResponse),
        ("not JSON", ChatCompletionError.invalidResponse),
    ])
    func rejectsUnusableResponses(body: String, expected: ChatCompletionError) async throws {
        let client = ChatCompletionClient { request in response(request, body: body) }
        await #expect(throws: expected) {
            try await client.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
    }

    @Test func mapsTimeoutAndNetworkErrorsWithoutLeakingDetails() async throws {
        let timedOut = ChatCompletionClient { _ in throw URLError(.timedOut) }
        await #expect(throws: ChatCompletionError.timeout) {
            try await timedOut.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
        let offline = ChatCompletionClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: ChatCompletionError.network) {
            try await offline.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
    }

    @Test func neverAutomaticallyRetries() async throws {
        let counter = RequestCounter()
        let client = ChatCompletionClient { request in
            await counter.increment()
            return response(request, status: 503)
        }
        await #expect(throws: ChatCompletionError.httpStatus(503)) {
            try await client.complete(model: "example/model", apiKey: "fake", messages: testMessages, maxCompletionTokens: 256)
        }
        #expect(await counter.count == 1)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
struct ConnectionTestModelTests {
    @Test func sendsOnlyFixedSampleAndUsesSavedKey() async throws {
        let client = ChatCompletionClient { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-saved-key")
            let body = try #require(request.httpBody)
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(payload["messages"] as? [[String: String]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] == "system")
            #expect(messages[0]["content"]?.contains("Traditional Chinese") == true)
            #expect(messages[1] == ["role": "user", "content": "Hello."])
            #expect(payload["max_completion_tokens"] as? Int == 256)
            return response(request)
        }
        let model = ConnectionTestModel(client: client, loadKey: { "fake-saved-key" })
        let task = try #require(model.start(model: "example/model"))
        await task.value
        #expect(model.state == .succeeded)
        #expect(!model.status.contains("fake-saved-key"))
        #expect(!model.status.contains("你好"))
    }

    @Test func missingModelDoesNotReadKeychain() {
        let model = ConnectionTestModel(loadKey: {
            Issue.record("Do not read Keychain without a model")
            return nil
        })
        model.start(model: " ")
        #expect(model.state == .failed(.missingModel))
    }

    @Test func handlesMissingKeyAndKeychainFailureLocally() {
        let missing = ConnectionTestModel(loadKey: { nil })
        missing.start(model: "example/model")
        #expect(missing.state == .failed(.missingKey))
        let denied = ConnectionTestModel(loadKey: { throw KeychainStore.StoreError.invalidData })
        denied.start(model: "example/model")
        #expect(denied.state == .failed(.keychainUnavailable))
    }

    @Test func cancelAndResetRejectLateResults() async throws {
        let gate = ResponseGate()
        let client = ChatCompletionClient { request in await gate.wait(request) }
        let model = ConnectionTestModel(client: client, loadKey: { "fake-key" })
        let task = try #require(model.start(model: "example/model"))
        await gate.waitUntilStarted()
        #expect(model.isTesting)
        #expect(model.start(model: "example/model") == nil)
        model.cancelIfRunning()
        #expect(model.state == .cancelled)
        model.reset()
        await gate.finish()
        await task.value
        #expect(model.state == .idle)
    }
}

private actor ResponseGate {
    private var request: URLRequest?
    private var pending: CheckedContinuation<(Data, HTTPURLResponse), Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait(_ request: URLRequest) async -> (Data, HTTPURLResponse) {
        self.request = request
        return await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        guard let request, let pending else { return }
        self.pending = nil
        pending.resume(returning: response(request))
    }
}
