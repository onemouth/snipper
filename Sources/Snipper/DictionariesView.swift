import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DictionariesModel: ObservableObject {
    @Published private(set) var dictionaries: [ImportedDictionary] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isImporting = false
    @Published private(set) var status = "Import a Yomitan format 3 term dictionary ZIP to store it locally."
    @Published private(set) var searchResults: [DictionarySearchEntry] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchStatus = ""
    @Published var showSearchResults = false
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private let store: DictionaryStore
    private var operation: Task<Void, Never>?
    private var operationID = UUID()

    init(store: DictionaryStore = DictionaryStore()) { self.store = store }

    func refresh() async {
        do { dictionaries = try await store.dictionaries() }
        catch { status = "Could not read installed dictionaries. Check folder permissions and available disk space." }
    }

    func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchID = UUID()
        searchResults = []
        isSearching = false
        showSearchResults = false
        searchStatus = ""
    }

    func search(_ query: String, dictionaryID: String?) {
        resetSearch()
        guard !isBusy else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 256 else {
            searchStatus = "Enter a word or reading up to 256 characters."
            return
        }
        isSearching = true
        let id = searchID
        searchTask = Task { [weak self, store] in
            do {
                let results = try await store.search(text, dictionaryID: dictionaryID)
                guard let self, self.searchID == id, !Task.isCancelled else { return }
                self.searchResults = results
                self.searchStatus = results.isEmpty ? "No headword, reading, or Japanese base-form match. Check the OCR spelling and dictionary rule tags." : "\(results.count) entries (up to 30 shown)."
                self.showSearchResults = !results.isEmpty
                self.isSearching = false
                self.searchTask = nil
            } catch {
                guard let self, self.searchID == id, !Task.isCancelled else { return }
                self.searchStatus = (error as? DictionaryError)?.errorDescription
                    ?? "Dictionary search failed. Check that the dictionary is still installed."
                self.isSearching = false
                self.searchTask = nil
            }
        }
    }

    func chooseArchive() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Yomitan Dictionary"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startImport(url)
    }

    func startImport(_ url: URL) {
        guard !isBusy else { return }
        resetSearch()
        isBusy = true
        isImporting = true
        status = "Importing dictionary…"
        let id = UUID()
        operationID = id
        let scoped = url.startAccessingSecurityScopedResource()
        operation = Task { [weak self, store] in
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let self else { return }
            do {
                let summary = try await store.importDictionary(from: url) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.operationID == id, self.isBusy else { return }
                        self.status = "Importing: \(progress.terms.formatted()) entries · \(progress.files.formatted()) files processed…"
                    }
                }
                self.status = "Imported \(summary.title): \(summary.termCount.formatted()) entries and \(summary.resourceCount.formatted()) images."
            } catch is CancellationError {
                self.status = "Import cancelled. No dictionary was installed."
            } catch let error as DictionaryError {
                self.status = error.localizedDescription
            } catch {
                self.status = "Import failed. No dictionary was installed."
            }
            self.operationID = UUID() // Ignore queued progress from the completed operation.
            await self.refresh()
            self.isBusy = false
            self.isImporting = false
            self.operation = nil
        }
    }

    func cancel() {
        guard isBusy else { return }
        operationID = UUID()
        status = "Cancelling import…"
        operation?.cancel()
    }

    func delete(_ dictionary: ImportedDictionary) {
        guard !isBusy else { return }
        resetSearch()
        isBusy = true
        operation = Task { [weak self, store] in
            do {
                try await store.delete(id: dictionary.id)
                self?.status = "Dictionary deleted. The original ZIP was not changed."
            } catch {
                self?.status = "Could not delete the dictionary. Check folder permissions and try again."
            }
            await self?.refresh()
            self?.isBusy = false
            self?.operation = nil
        }
    }
}

struct DictionariesView: View {
    @StateObject private var model: DictionariesModel

    init(store: DictionaryStore) {
        _model = StateObject(wrappedValue: DictionariesModel(store: store))
    }

    @State private var pendingDeletion: ImportedDictionary?
    @State private var searchText = ""
    @State private var searchDictionaryID = ""

    private func search() {
        model.search(searchText, dictionaryID: searchDictionaryID.isEmpty ? nil : searchDictionaryID)
    }

    var body: some View {
        Form {
            Section("Test dictionary lookup") {
                Picker("Dictionary", selection: $searchDictionaryID) {
                    Text("All installed dictionaries").tag("")
                    ForEach(model.dictionaries) { dictionary in
                        Text(dictionary.title).tag(dictionary.id)
                    }
                }
                HStack {
                    TextField("Word or reading", text: $searchText, prompt: Text("猫 / ねこ"))
                        .onSubmit { search() }
                    Button("Search") { search() }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSearching)
                        .popover(isPresented: $model.showSearchResults, arrowEdge: .trailing) {
                            DictionaryResultsPopover(entries: model.searchResults, query: searchText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                model.showSearchResults = false
                            }
                        }
                    if model.isSearching { ProgressView().controlSize(.small) }
                }
                if !model.searchStatus.isEmpty {
                    HStack {
                        Text(model.searchStatus).font(.caption)
                        if !model.searchResults.isEmpty {
                            Button("Show Results") { model.showSearchResults = true }
                                .font(.caption)
                        }
                    }
                }
                Text("Headword/reading lookup + Japanese deinflection · Local only · No clipboard changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.isBusy || model.dictionaries.isEmpty)
            Section("Local dictionaries") {
                HStack {
                    Button("Import Dictionary…") { model.chooseArchive() }
                        .disabled(model.isBusy)
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                        if model.isImporting {
                            Button("Cancel Import") { model.cancel() }
                        }
                    }
                }
                Text(model.status).font(.caption).textSelection(.enabled)
                Text("Yomitan format 3 terms, tags, and PNG/JPEG/GIF/WebP images. Test imported entries above. Frequency, pitch-accent, kanji banks, and custom styles are not imported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Installed dictionaries") {
                if model.dictionaries.isEmpty {
                    Text("No dictionaries installed.").foregroundStyle(.secondary)
                }
                ForEach(model.dictionaries) { dictionary in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dictionary.title).fontWeight(.medium)
                            Text("\(dictionary.revision) · \(dictionary.termCount.formatted()) entries · \(dictionary.resourceCount.formatted()) images")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete…", role: .destructive) { pendingDeletion = dictionary }
                            .disabled(model.isBusy)
                    }
                }
            }
            Section("Storage and privacy") {
                Text("Imported dictionaries persist locally in Application Support/Snipper/Dictionaries. No dictionary data is uploaded. Only import dictionaries you have permission to use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
        .onDisappear { model.resetSearch() }
        .onChange(of: searchText) { _, _ in model.resetSearch() }
        .onChange(of: searchDictionaryID) { _, _ in model.resetSearch() }
        .onChange(of: model.dictionaries) { _, dictionaries in
            if !searchDictionaryID.isEmpty && !dictionaries.contains(where: { $0.id == searchDictionaryID }) {
                searchDictionaryID = ""
            }
        }
        .alert("Delete imported dictionary?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let dictionary = pendingDeletion { model.delete(dictionary) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the imported database and images, not the original ZIP. You can import it again later.")
        }
    }
}
