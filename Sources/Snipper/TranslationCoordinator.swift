import Combine
import Foundation

enum TranslationFailure: Error, LocalizedError, Equatable {
    case cloudNotAllowed, textTooLong
    case backend(ChatCompletionError)

    var errorDescription: String? {
        switch self {
        case .cloudNotAllowed: "Cloud translation is off. Enable “Allow cloud translation” in Settings → Translation before sending OCR text."
        case .textTooLong: "This capture exceeds 12,000 characters. Select a smaller region. Original text is still available."
        case .backend(let error): error.localizedDescription
        }
    }
}

@MainActor
final class TranslationCoordinator: ObservableObject {
    enum Phase: Equatable {
        case ready, translating, retrying, completed(cached: Bool), cancelled
        case failed(TranslationFailure)
    }

    struct State: Equatable {
        var original = ""
        var translation: String?
        var phase: Phase = .ready
    }

    private struct Configuration: Equatable {
        var model: String
        var target: TargetLanguage
        var allowed: Bool
        var automatic: Bool
        var credentialsVersion: UUID
    }

    @Published private(set) var state = State()
    private let client: ChatCompletionClient
    private let loadKey: () throws -> String?
    private let retryDelay: @Sendable () async throws -> Void
    private var configuration: Configuration
    private var subscription: AnyCancellable?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var cache = TranslationCache()

    init(settings: AppSettings, client: ChatCompletionClient = ChatCompletionClient(),
         loadKey: @escaping () throws -> String? = { try KeychainStore().read() },
         retryDelay: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) {
        self.client = client
        self.loadKey = loadKey
        self.retryDelay = retryDelay
        configuration = Configuration(model: settings.model, target: settings.targetLanguage,
                                      allowed: settings.cloudTranslationConsent, automatic: settings.automaticTranslation,
                                      credentialsVersion: settings.credentialsVersion)
        subscription = settings.$model.combineLatest(settings.$targetLanguage, settings.$cloudTranslationConsent, settings.$automaticTranslation)
            .combineLatest(settings.$credentialsVersion)
            .dropFirst()
            .sink { [weak self] values in
                MainActor.assumeIsolated {
                    let (fields, credentials) = values
                    self?.configurationChanged(Configuration(model: fields.0, target: fields.1, allowed: fields.2,
                                                             automatic: fields.3, credentialsVersion: credentials))
                }
            }
    }

    var isTranslating: Bool { state.phase == .translating || state.phase == .retrying }
    var targetLanguage: TargetLanguage { configuration.target }
    var cachedEntryCount: Int { cache.count }

    var statusText: String { statusText(for: state) }

    func statusText(for state: State) -> String {
        switch state.phase {
        case .ready:
            configuration.allowed ? "Click Translate to send this text to OpenRouter." : TranslationFailure.cloudNotAllowed.localizedDescription
        case .translating: "Translating into \(configuration.target.rawValue)… Original text remains available."
        case .retrying: "Temporary provider error. Retrying once…"
        case .completed(let cached): cached ? "Translation ready · reused from memory cache." : "Translation ready · copy it explicitly when needed."
        case .cancelled: "Translation cancelled. Click Translate to try again."
        case .failed(let error): "Translation failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func receiveOriginal(_ text: String) -> Task<Void, Never>? {
        invalidate()
        state = State(original: text)
        if configuration.automatic && configuration.allowed { return translateCurrent() }
        return nil
    }

    @discardableResult
    func translateCurrent() -> Task<Void, Never>? {
        invalidate()
        guard !state.original.isEmpty else { return nil }
        state.translation = nil
        guard configuration.allowed else {
            state.phase = .failed(.cloudNotAllowed)
            return nil
        }
        guard state.original.count <= 12_000 else {
            state.phase = .failed(.textTooLong)
            return nil
        }
        let snapshot = configuration
        let model = snapshot.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            state.phase = .failed(.backend(.missingModel))
            return nil
        }
        let text = state.original
        let cacheKey = TranslationCache.Key(text: text, model: model, target: snapshot.target.rawValue,
                                           endpoint: client.baseURL.absoluteString, promptVersion: TranslationPrompt.version)
        if let cached = cache.value(for: cacheKey) {
            state.translation = cached
            state.phase = .completed(cached: true)
            return nil
        }
        let id = UUID()
        requestID = id
        state.phase = .translating
        let client = self.client
        let retryDelay = self.retryDelay
        let loadKey = self.loadKey
        task = Task { [weak self] in
            do {
                // Present the original panel before Keychain access or networking.
                await Task.yield()
                try Task.checkCancellation()
                guard self?.requestID == id else { return }
                let saved: String?
                do { saved = try loadKey() }
                catch { throw ChatCompletionError.keychainUnavailable }
                guard let apiKey = saved, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatCompletionError.missingKey
                }
                var translated: String?
                for attempt in 0...1 {
                    try Task.checkCancellation()
                    do {
                        translated = try await client.complete(model: model, apiKey: apiKey,
                                                               messages: TranslationPrompt.messages(text: text, target: snapshot.target),
                                                               maxCompletionTokens: 8192)
                        break
                    } catch let error as ChatCompletionError {
                        guard attempt == 0, Self.isRetryable(error) else { throw error }
                        guard let self, self.requestID == id else { return }
                        self.state.phase = .retrying
                        try await retryDelay()
                        try Task.checkCancellation()
                        guard self.requestID == id else { return }
                        self.state.phase = .translating
                    }
                }
                try Task.checkCancellation()
                guard let self, self.requestID == id, self.configuration == snapshot, let translated else { return }
                self.cache.insert(translated, for: cacheKey)
                self.state.translation = translated
                self.state.phase = .completed(cached: false)
            } catch {
                guard let self, self.requestID == id else { return }
                if error is CancellationError {
                    self.state.phase = .cancelled
                } else {
                    self.state.phase = .failed(.backend((error as? ChatCompletionError) ?? .network))
                }
            }
            guard let self, self.requestID == id else { return }
            self.task = nil
            self.requestID = nil
        }
        return task
    }

    func cancelCurrent() {
        guard isTranslating else { return }
        invalidate()
        state.phase = .cancelled
    }

    func clearCache() { cache.clear() }

    func stop() {
        invalidate()
        cache.clear()
        subscription?.cancel()
        subscription = nil
        state = State()
    }

    private func configurationChanged(_ newValue: Configuration) {
        let old = configuration
        guard old != newValue else { return }
        configuration = newValue
        let requestContextChanged = old.model != newValue.model || old.target != newValue.target
            || old.allowed != newValue.allowed || old.credentialsVersion != newValue.credentialsVersion
        if old.credentialsVersion != newValue.credentialsVersion || !newValue.allowed { cache.clear() }
        if requestContextChanged {
            invalidate()
            state.translation = nil
            state.phase = .ready
        } else if old.automatic != newValue.automatic {
            cancelCurrent()
        }
        // Enabling automatic translation or changing target never silently sends an old capture.
    }

    private func invalidate() {
        requestID = nil
        task?.cancel()
        task = nil
    }

    nonisolated static func isRetryable(_ error: ChatCompletionError) -> Bool {
        if case .httpStatus(let code) = error { return [429, 502, 503, 529].contains(code) }
        return false // Do not duplicate potentially billable work after network errors/timeouts.
    }
}
