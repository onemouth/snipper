import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcutTester: ShortcutTester
    @State private var apiKey = ""
    @State private var keyStatus = "Key has not been checked."
    private let keychain = KeychainStore()

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            translation
                .tabItem { Label("Translation", systemImage: "character.bubble") }
        }
        .padding(20)
        .frame(width: 560, height: 490)
    }

    private var general: some View {
        Form {
            Section("Keyboard shortcuts") {
                shortcutRow("Select region", shortcut: $settings.captureShortcut)
                shortcutRow("Recapture region", shortcut: $settings.recaptureShortcut)
                if let warning = settings.shortcutWarning {
                    Text(warning).foregroundStyle(.red)
                }
                Text(shortcutTester.registrationStatus)
                    .font(.caption)
                    .foregroundStyle(shortcutTester.isRegistered ? Color.secondary : Color.red)
                Text(shortcutTester.lastReceived)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry Shortcut Registration") { shortcutTester.register(settings) }
                Text("Press either shortcut for a confirmation toast. No screenshot is taken. Keys use physical ANSI keyboard positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local OCR") {
                TextField("Recognition language codes", text: $settings.recognitionLanguages)
                Text("Priority languages: en-US, ja-JP. Other Vision-supported languages can be configured. Recognition is not limited to English or Japanese.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("MVP behavior") {
                Text("Original text is always copied and shown in a read-only panel. Translation never replaces your clipboard automatically.")
                Text("Capture, OCR, and the result panel are not implemented yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var translation: some View {
        Form {
            Section("OpenRouter") {
                Toggle("Translate automatically after capture", isOn: $settings.automaticTranslation)
                Picker("Target language", selection: $settings.targetLanguage) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                TextField("Model ID", text: $settings.model, prompt: Text("provider/model-name"))
                    .autocorrectionDisabled()
                Text("Endpoint: \(AppSettings.openRouterBaseURL.absoluteString)")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("New API key", text: $apiKey)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save Key") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Check Key") { checkKey() }
                    Button("Delete Key", role: .destructive) { deleteKey() }
                }
                Text(keyStatus).font(.caption).textSelection(.enabled)
            }
            Section("Privacy") {
                Text("OCR runs locally. When you request translation, only recognized text will be sent to OpenRouter and its selected model provider—not screenshots. Provider data policies apply.")
                Text("API keys stay in macOS Keychain. No persistent capture history or text logging; translation cache will be memory-only.")
                Text("This foundation build makes no translation requests.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, shortcut: Binding<ShortcutConfiguration>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("Modifiers", selection: shortcut.modifiers) {
                ForEach(ShortcutModifiers.allCases) { modifiers in
                    Text(modifiers.rawValue).tag(modifiers.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 175)
            TextField("Key", text: shortcut.key)
                .labelsHidden()
                .accessibilityLabel("\(title) key")
                .multilineTextAlignment(.center)
                .frame(width: 40)
                .onChange(of: shortcut.wrappedValue.key) { _, newValue in
                    shortcut.wrappedValue.key = newValue.lowercased()
                }
        }
    }

    private func saveKey() {
        do {
            try keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            keyStatus = "API key saved in Keychain."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func checkKey() {
        do {
            keyStatus = try keychain.read() == nil ? "No API key stored." : "API key is stored in Keychain."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try keychain.delete()
            apiKey = ""
            keyStatus = "API key removed."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
