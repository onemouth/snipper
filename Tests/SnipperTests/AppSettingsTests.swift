import Foundation
import Testing
@testable import Snipper

@Suite @MainActor
struct AppSettingsTests {
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "SnipperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults)
    }

    @Test func initialDefaults() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.automaticTranslation)
            #expect(settings.targetLanguage == .traditionalChinese)
            #expect(settings.recognitionLanguages == "en-US, ja-JP")
            #expect(settings.model.isEmpty)
            #expect(settings.captureShortcut == ShortcutConfiguration(modifiers: ShortcutModifiers.commandShift.rawValue, key: "2"))
            #expect(settings.recaptureShortcut == ShortcutConfiguration(modifiers: ShortcutModifiers.commandShift.rawValue, key: "1"))
            #expect(settings.shortcutWarning == nil)
        }
    }

    @Test func preferencesPersist() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.automaticTranslation = false
            settings.targetLanguage = .japanese
            settings.model = "example/model"
            settings.recognitionLanguages = "ja-JP"
            settings.captureShortcut.key = "a"
            settings.captureShortcut.modifiers = ShortcutModifiers.commandOption.rawValue
            let restored = AppSettings(defaults: defaults)
            #expect(!restored.automaticTranslation)
            #expect(restored.targetLanguage == .japanese)
            #expect(restored.model == "example/model")
            #expect(restored.recognitionLanguages == "ja-JP")
            #expect(restored.captureShortcut.key == "a")
            #expect(restored.captureShortcut.modifiers == ShortcutModifiers.commandOption.rawValue)
        }
    }

    @Test func shortcutsValidate() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.recaptureShortcut = settings.captureShortcut
            #expect(settings.shortcutWarning != nil)
            settings.recaptureShortcut.key = "!"
            #expect(settings.shortcutWarning != nil)
            settings.recaptureShortcut.key = "3"
            #expect(settings.shortcutWarning == nil)
        }
    }

    @Test func unknownLanguageFallsBack() {
        withDefaults { defaults in
            defaults.set("unknown", forKey: "targetLanguage")
            #expect(AppSettings(defaults: defaults).targetLanguage == .traditionalChinese)
        }
    }
}
