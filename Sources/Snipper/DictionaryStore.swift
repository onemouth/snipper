import CZipReader
import Foundation

struct DictionaryImportProgress: Sendable {
    let files: Int
    let terms: Int
}

struct DictionaryInflection: Sendable, Hashable {
    let source: String
    let base: String
    let reasons: [String]
}

struct DictionarySearchEntry: Identifiable, Sendable {
    let id = UUID()
    let dictionary: ImportedDictionary
    let term: DictionaryTerm
    let resources: URL
    var inflection: DictionaryInflection? = nil
}

struct DictionaryCandidateMatch: Sendable {
    let query: String
    let entries: [DictionarySearchEntry]
}

struct DictionaryImportLimits: Sendable {
    var archiveBytes = 1_000_000_000
    var expandedBytes = 2_000_000_000
    var fileBytes = 32_000_000
    var files = 100_000
    var terms = 2_000_000
}

actor DictionaryStore {
    static let defaultRoot = URL.applicationSupportDirectory
        .appendingPathComponent("Snipper/Dictionaries", isDirectory: true)
    private let root: URL
    private let limits: DictionaryImportLimits
    private var prepared = false
    private var japaneseDeinflector: JapaneseDeinflector?

    init(root: URL = DictionaryStore.defaultRoot, limits: DictionaryImportLimits = .init()) {
        self.root = root
        self.limits = limits
    }

    private func prepare() throws {
        guard !prepared else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Staging directories are never searchable; remove interrupted imports on first use.
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix(".import-") {
                try FileManager.default.removeItem(at: url)
            }
            prepared = true
        } catch { throw DictionaryError.storage }
    }

    func dictionaries() throws -> [ImportedDictionary] {
        try prepare()
        do {
            return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { UUID(uuidString: $0.lastPathComponent) != nil }
                .map { url in
                    let summary = try DictionaryDatabase(url: url.appendingPathComponent("dictionary.sqlite"), create: false).summary()
                    guard summary.id == url.lastPathComponent else { throw DictionaryError.storage }
                    return summary
                }
                .sorted { $0.importedAt < $1.importedAt }
        } catch { throw DictionaryError.storage }
    }

    func importDictionary(from archive: URL,
                          progress: @Sendable (DictionaryImportProgress) -> Void = { _ in }) throws -> ImportedDictionary {
        try prepare()
        try Task.checkCancellation()
        let installed = try dictionaries()
        let id = UUID().uuidString
        let staging = root.appendingPathComponent(".import-\(id)", isDirectory: true)
        let destination = root.appendingPathComponent(id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let summary = try DictionaryImport.run(archive: archive, staging: staging, id: id,
                                                   installed: installed, limits: limits, progress: progress)
            try Task.checkCancellation()
            // Publish only after the transaction and all file handles are closed.
            try FileManager.default.moveItem(at: staging, to: destination)
            return summary
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DictionaryError {
            throw error
        } catch { throw DictionaryError.storage }
    }

    func delete(id: String) throws {
        guard UUID(uuidString: id) != nil else { throw DictionaryError.missingDictionary }
        try prepare()
        let directory = root.appendingPathComponent(id)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw DictionaryError.missingDictionary }
        do { try FileManager.default.removeItem(at: directory) }
        catch { throw DictionaryError.storage }
    }

    func search(_ query: String, dictionaryID: String? = nil, limit: Int = 30) throws -> [DictionarySearchEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 256 else { return [] }
        return try matchCandidates([text], dictionaryID: dictionaryID, limit: limit)?.entries ?? []
    }

    func searchCandidateMatch(_ candidates: [String]) throws -> DictionaryCandidateMatch? {
        try matchCandidates(Array(candidates.prefix(80)).filter { !$0.isEmpty && $0.count <= 48 }, limit: 30)
    }

    private func matchCandidates(_ candidates: [String], dictionaryID: String? = nil,
                                 limit: Int) throws -> DictionaryCandidateMatch? {
        let installed = try dictionaries()
        if let dictionaryID, !installed.contains(where: { $0.id == dictionaryID }) {
            throw DictionaryError.missingDictionary
        }
        let selected = installed.filter { dictionaryID == nil || $0.id == dictionaryID }
        guard !selected.isEmpty else { return nil }
        let maximum = max(1, min(limit, 100))
        let databases = try selected.map { dictionary in
            try DictionaryDatabase(url: root.appendingPathComponent(dictionary.id).appendingPathComponent("dictionary.sqlite"), create: false)
        }
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            try Task.checkCancellation()
            var entries: [DictionarySearchEntry] = []
            // An exact headword/reading wins over all derived forms for this span.
            for (index, dictionary) in selected.enumerated() {
                let terms = try databases[index].lookup(candidate, limit: maximum - entries.count)
                let resources = root.appendingPathComponent(dictionary.id).appendingPathComponent("resources")
                entries += terms.map { DictionarySearchEntry(dictionary: dictionary, term: $0, resources: resources) }
                if entries.count >= maximum { break }
            }
            if !entries.isEmpty { return DictionaryCandidateMatch(query: candidate, entries: entries) }
            guard candidate.count <= 48, JapaneseDeinflector.looksJapanese(candidate) else { continue }
            if japaneseDeinflector == nil { japaneseDeinflector = try JapaneseDeinflector.load() }
            guard let deinflector = japaneseDeinflector else { throw DictionaryError.deinflectionRules }
            let forms = try deinflector.deinflect(candidate).filter { !$0.reasons.isEmpty }
            for (index, dictionary) in selected.enumerated() {
                try Task.checkCancellation()
                let matches = try databases[index].lookupDeinflected(forms, using: deinflector, limit: maximum - entries.count)
                let resources = root.appendingPathComponent(dictionary.id).appendingPathComponent("resources")
                entries += matches.map { term, form in
                    DictionarySearchEntry(dictionary: dictionary, term: term, resources: resources,
                                          inflection: DictionaryInflection(source: candidate, base: form.text,
                                                                           reasons: deinflector.displayReasons(form.reasons)))
                }
                if entries.count >= maximum { break }
            }
            if !entries.isEmpty { return DictionaryCandidateMatch(query: candidate, entries: entries) }
        }
        return nil
    }

    // Low-level exact lookup for import validation and format compatibility tests.
    func lookup(_ text: String, dictionaryID: String, limit: Int = 20) throws -> [DictionaryTerm] {
        guard UUID(uuidString: dictionaryID) != nil else { throw DictionaryError.missingDictionary }
        try prepare()
        let database = root.appendingPathComponent(dictionaryID).appendingPathComponent("dictionary.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { throw DictionaryError.missingDictionary }
        return try DictionaryDatabase(url: database, create: false).lookup(text, limit: limit)
    }
}

private enum DictionaryImport {
    static func run(archive: URL, staging: URL, id: String, installed: [ImportedDictionary],
                    limits: DictionaryImportLimits,
                    progress: @Sendable (DictionaryImportProgress) -> Void) throws -> ImportedDictionary {
        let values = try archive.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let bytes = values.fileSize, bytes <= limits.archiveBytes else {
            throw DictionaryError.limits
        }
        guard let reader = sn_archive_open(archive.path) else { throw DictionaryError.invalidArchive }
        defer { sn_archive_close(reader) }
        let database = try DictionaryDatabase(url: staging.appendingPathComponent("dictionary.sqlite"), create: true)
        try database.execute("BEGIN IMMEDIATE")
        let resources = staging.appendingPathComponent("resources", isDirectory: true)
        var indexData: Data?
        var title: String?
        var revision: String?
        var files = 0, termCount = 0, expanded = 0
        var paths = Set<String>(), resourcePaths = Set<String>(), references = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 65536)
        var lastProgress = ContinuousClock.now
        while true {
            try Task.checkCancellation()
            var pathPointer: UnsafePointer<CChar>?
            var declaredSize: Int64 = 0
            var kind: Int32 = 0
            let status = sn_archive_next(reader, &pathPointer, &declaredSize, &kind)
            if status == 0 { break }
            guard status == 1, let pathPointer, let rawPath = String(validatingCString: pathPointer) else {
                throw DictionaryError.invalidArchive
            }
            guard kind == 1 || kind == 2 else { throw DictionaryError.unsafePath }
            let path = try DictionaryFormat.safePath(kind == 2 && rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath)
            // Reject duplicate/case-equivalent paths before writing on macOS filesystems.
            guard paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw DictionaryError.unsafePath
            }
            files += 1
            guard files <= limits.files, declaredSize >= 0, declaredSize <= limits.fileBytes else { throw DictionaryError.limits }
            var data = Data()
            while true {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes { sn_archive_read(reader, $0.baseAddress, $0.count) }
                guard count >= 0 else { throw DictionaryError.invalidArchive }
                if count == 0 { break }
                expanded += Int(count)
                guard expanded <= limits.expandedBytes, data.count + Int(count) <= limits.fileBytes else { throw DictionaryError.limits }
                data.append(contentsOf: buffer.prefix(Int(count)))
            }
            guard data.count == declaredSize else { throw DictionaryError.invalidArchive }
            if kind == 2 { continue }
            if path == "index.json" {
                let metadata = try DictionaryFormat.index(data)
                guard !installed.contains(where: { $0.title == metadata.title }) else { throw DictionaryError.duplicate }
                indexData = data
                title = metadata.title
                revision = metadata.revision
            } else if path.range(of: #"^term_bank_[1-9][0-9]*\.json$"#, options: .regularExpression) != nil {
                guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw DictionaryError.invalidTerm }
                guard termCount + rows.count <= limits.terms else { throw DictionaryError.limits }
                termCount += try database.insertTerms(rows, check: { try Task.checkCancellation() }, references: &references)
            } else if path.range(of: #"^tag_bank_[1-9][0-9]*\.json$"#, options: .regularExpression) != nil {
                guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw DictionaryError.invalidTag }
                try database.insertTags(rows)
            } else if DictionaryFormat.imageExtensions.contains((path as NSString).pathExtension.lowercased()) {
                let destination = resources.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination)
                resourcePaths.insert(path)
            }
            // Other banks/styles are deliberately not imported in this first version.
            if files == 1 || lastProgress.duration(to: .now) >= .milliseconds(100) {
                progress(DictionaryImportProgress(files: files, terms: termCount))
                lastProgress = .now
            }
        }
        guard let indexData, let title, let revision else { throw DictionaryError.invalidIndex }
        guard termCount > 0 else { throw DictionaryError.unsupportedFormat }
        guard references.isSubset(of: resourcePaths) else { throw DictionaryError.missingResource }
        try Task.checkCancellation()
        let summary = ImportedDictionary(id: id, title: title, revision: revision, termCount: termCount,
                                         resourceCount: resourcePaths.count, importedAt: Date())
        try database.finish(summary: summary, metadata: indexData)
        return summary
    }
}
