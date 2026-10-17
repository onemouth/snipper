import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: GlobalShortcuts
    @ObservedObject var capture: CaptureCoordinator
    @ObservedObject var translator: TranslationCoordinator
    @ObservedObject var lookup: DictionaryCaptureCoordinator
    let dictionaryStore: DictionaryStore
    @State private var apiKey = ""
    @State private var keyStatus = "Key has not been checked."
    @State private var confirmConnectionTest = false
    @StateObject private var connectionTest = ConnectionTestModel()
    private let keychain = KeychainStore()

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            translation
                .tabItem { Label("Translation", systemImage: "character.bubble") }
            DictionariesView(store: dictionaryStore)
                .tabItem { Label("Dictionaries", systemImage: "books.vertical") }
        }
        .padding(20)
        .frame(width: 560, height: 490)
        .alert("Test OpenRouter connection?", isPresented: $confirmConnectionTest) {
            Button("Test Connection") { connectionTest.start(model: settings.model) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the fixed sample “Hello.” for translation into Traditional Chinese using your saved API key and selected model. A small API charge may apply. No captured text or screenshots are sent; your clipboard is unchanged.")
        }
        .onChange(of: settings.model) { _, _ in connectionTest.reset() }
        .onDisappear { connectionTest.cancelIfRunning() }
    }

    private var general: some View {
        Form {
            Section("Keyboard shortcuts") {
                shortcutRow("Select region", shortcut: $settings.captureShortcut)
                shortcutRow("Recapture region", shortcut: $settings.recaptureShortcut)
                shortcutRow("Dictionary region", shortcut: $settings.lookupShortcut)
                if let warning = settings.shortcutWarning {
                    Text(warning).foregroundStyle(.red)
                }
                Text(shortcuts.registrationStatus)
                    .font(.caption)
                    .foregroundStyle(shortcuts.isRegistered ? Color.secondary : Color.red)
                Text(shortcuts.lastReceived)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry Shortcut Registration") { shortcuts.register(settings) }
                Text("Capture selects a rectangle; recapture reuses it. Dictionary lookup uses its own region selection without copying or translating. Keys use physical ANSI keyboard positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local OCR") {
                TextField("Recognition language codes", text: $settings.recognitionLanguages)
                Text("Priority: en-US, ja-JP. Enter comma-separated Vision language codes, or leave blank for defaults. Automatic language detection is enabled; unsupported codes produce an OCR error.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("On-screen dictionary") {
                Text(lookup.status).font(.caption).textSelection(.enabled)
                Text("Press Control–Option–Z, release the keys, then drag a region with the left mouse button. OCR progress appears in the dictionary panel. A single word is looked up automatically; click words in longer OCR text to look them up. Escape/right-click cancels selection. Import a dictionary first. No deinflection yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture behavior") {
                Text(capture.status)
                    .textSelection(.enabled)
                Text("Successful OCR copies original text and opens a read-only result panel without activating Snipper. Pin keeps its position. Cloud translation is optional. Original text remains useful if translation fails and translation is copied only on explicit request.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var translation: some View {
        Form {
            Section("OpenRouter") {
                Toggle("Allow cloud translation", isOn: $settings.cloudTranslationConsent)
                Text("When allowed, automatic captures or the panel’s Translate button send OCR text to OpenRouter and its model provider. Screenshots are never sent. API charges and provider data policies apply.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Translate automatically after capture", isOn: $settings.automaticTranslation)
                Picker("Target language", selection: $settings.targetLanguage) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                TextField("Model ID", text: $settings.model, prompt: Text("provider/model-name"))
                    .autocorrectionDisabled()
                    .disabled(connectionTest.isTesting)
                Text("Endpoint: \(AppSettings.openRouterBaseURL.absoluteString)")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("New API key", text: $apiKey)
                    .autocorrectionDisabled()
                    .disabled(connectionTest.isTesting)
                HStack {
                    Button("Save Key") { saveKey() }
                        .disabled(connectionTest.isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Check Key") { checkKey() }
                    Button("Delete Key", role: .destructive) { deleteKey() }
                }
                .disabled(connectionTest.isTesting)
                Text(keyStatus).font(.caption).textSelection(.enabled)
            }
            Section("Connection test") {
                HStack {
                    Button("Test Connection…") { confirmConnectionTest = true }
                        .disabled(connectionTest.isTesting || !apiKey.isEmpty || settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if connectionTest.isTesting {
                        ProgressView().controlSize(.small)
                        Button("Cancel Test") { connectionTest.cancelIfRunning() }
                    }
                }
                Text(connectionTest.status)
                    .font(.caption).textSelection(.enabled)
                if !apiKey.isEmpty {
                    Text("Save or clear the new key before testing. The test uses the saved Keychain key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Fixed sample only · May incur a small API charge · 30-second timeout · No automatic retry")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("OCR runs locally. When you request translation, only recognized text will be sent to OpenRouter and its selected model provider—not screenshots. Provider data policies apply.")
                Text("API keys stay in macOS Keychain. No persistent capture history or text logging; translation cache is memory-only and clears on quit.")
                Button("Clear Translation Cache") { translator.clearCache() }
                Text("The built-in translation prompt preserves meaning and treats captured content as text, never as instructions. Target changes clear stale translations; click Translate to translate an existing result.")
                    .foregroundStyle(.secondary)
                Text("30-second timeout. Translation retries HTTP 429/502/503/529 once; timeouts are not retried. Cancellation or errors may still incur provider charges.")
                    .font(.caption).foregroundStyle(.secondary)
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
        connectionTest.reset()
        do {
            try keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            keyStatus = "API key saved in Keychain."
            settings.credentialsDidChange()
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
        connectionTest.reset()
        do {
            try keychain.delete()
            apiKey = ""
            keyStatus = "API key removed."
            settings.credentialsDidChange()
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
