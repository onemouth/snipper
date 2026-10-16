import Combine
import Foundation

@MainActor
final class ConnectionTestModel: ObservableObject {
    enum State: Equatable {
        case idle, testing, succeeded, cancelled
        case failed(ChatCompletionError)
    }

    @Published private(set) var state: State = .idle
    private let client: ChatCompletionClient
    private let loadKey: () throws -> String?
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    // Intentionally has no capture/clipboard dependency.
    static let sample = "Hello."
    static let maxCompletionTokens = 256

    init(client: ChatCompletionClient = ChatCompletionClient(), loadKey: @escaping () throws -> String? = { try KeychainStore().read() }) {
        self.client = client
        self.loadKey = loadKey
    }

    var isTesting: Bool { state == .testing }

    var status: String {
        switch state {
        case .idle: "Not tested. Uses the saved Keychain key, not unsaved text."
        case .testing: "Testing the selected model…"
        case .succeeded: "Connection succeeded. The selected model returned text."
        case .cancelled: "Test cancelled. A request already processed by the provider may still incur a charge."
        case .failed(let error): error.localizedDescription
        }
    }

    @discardableResult
    func start(model: String) -> Task<Void, Never>? {
        guard !isTesting else { return nil }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failed(.missingModel)
            return nil
        }
        let key: String
        do {
            guard let saved = try loadKey(), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .failed(.missingKey)
                return nil
            }
            key = saved
        } catch {
            state = .failed(.keychainUnavailable)
            return nil
        }
        let id = UUID()
        requestID = id
        state = .testing
        let client = self.client
        task = Task { [weak self] in
            let result: State
            do {
                _ = try await client.complete(
                    model: model, apiKey: key,
                    messages: [
                        .init(role: "system", content: "Translate the user's text into Traditional Chinese. Return only the translation."),
                        .init(role: "user", content: Self.sample),
                    ],
                    maxCompletionTokens: Self.maxCompletionTokens
                )
                result = .succeeded
            } catch is CancellationError {
                result = .cancelled
            } catch let error as ChatCompletionError {
                result = .failed(error)
            } catch {
                result = .failed(.network)
            }
            guard let self, self.requestID == id else { return }
            self.state = result
            self.task = nil
            self.requestID = nil
        }
        return task
    }

    func cancelIfRunning() {
        guard isTesting else { return }
        invalidate()
        state = .cancelled
    }

    func reset() {
        invalidate()
        state = .idle
    }

    private func invalidate() {
        requestID = nil
        task?.cancel()
        task = nil
    }
}
