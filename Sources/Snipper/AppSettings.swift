import Combine
import Foundation

enum TargetLanguage: String, CaseIterable, Identifiable {
    case traditionalChinese = "Traditional Chinese"
    case japanese = "Japanese"
    case english = "English"

    var id: String { rawValue }
}

enum ShortcutModifiers: String, CaseIterable, Identifiable {
    case commandShift = "Command + Shift"
    case controlOption = "Control + Option"
    case commandOption = "Command + Option"

    var id: String { rawValue }
}

struct ShortcutConfiguration: Codable, Equatable {
    var modifiers: String
    var key: String

    var displayName: String { "\(modifiers) + \(key.uppercased())" }

    var isValid: Bool {
        ShortcutModifiers(rawValue: modifiers) != nil
            && key.count == 1
            && key.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0)
            }
    }
}

/// Preferences contain no captured text or API secrets.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var cloudTranslationConsent: Bool { didSet { defaults.set(cloudTranslationConsent, forKey: "cloudTranslationConsent") } }
    @Published private(set) var credentialsVersion = UUID()
    @Published var automaticTranslation: Bool { didSet { defaults.set(automaticTranslation, forKey: "automaticTranslation") } }
    @Published var targetLanguage: TargetLanguage { didSet { defaults.set(targetLanguage.rawValue, forKey: "targetLanguage") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var recognitionLanguages: String { didSet { defaults.set(recognitionLanguages, forKey: "recognitionLanguages") } }
    @Published var captureShortcut: ShortcutConfiguration { didSet { save(captureShortcut, key: "captureShortcut") } }
    @Published var recaptureShortcut: ShortcutConfiguration { didSet { save(recaptureShortcut, key: "recaptureShortcut") } }

    nonisolated static let openRouterBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cloudTranslationConsent = defaults.bool(forKey: "cloudTranslationConsent")
        automaticTranslation = defaults.object(forKey: "automaticTranslation") as? Bool ?? true
        targetLanguage = defaults.string(forKey: "targetLanguage").flatMap(TargetLanguage.init(rawValue:)) ?? .traditionalChinese
        model = defaults.string(forKey: "model") ?? ""
        recognitionLanguages = defaults.string(forKey: "recognitionLanguages") ?? "en-US, ja-JP"
        captureShortcut = Self.loadShortcut(defaults, key: "captureShortcut", fallbackKey: "2", fallbackModifiers: .commandShift)
        recaptureShortcut = Self.loadShortcut(defaults, key: "recaptureShortcut", fallbackKey: "1", fallbackModifiers: .commandShift)
    }

    func credentialsDidChange() { credentialsVersion = UUID() }

    var shortcutWarning: String? {
        guard captureShortcut.isValid, recaptureShortcut.isValid else {
            return "Use one letter (A–Z) or digit (0–9) for each shortcut."
        }
        guard captureShortcut != recaptureShortcut else {
            return "Capture and recapture must use different shortcuts."
        }
        return nil
    }

    private func save(_ shortcut: ShortcutConfiguration, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadShortcut(_ defaults: UserDefaults, key: String, fallbackKey: String, fallbackModifiers: ShortcutModifiers) -> ShortcutConfiguration {
        if let data = defaults.data(forKey: key),
           let shortcut = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data) {
            return shortcut
        }
        return ShortcutConfiguration(modifiers: fallbackModifiers.rawValue, key: fallbackKey)
    }
}
