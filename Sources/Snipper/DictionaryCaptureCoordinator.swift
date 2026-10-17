import AppKit
import Combine
import ScreenCaptureKit

/// Separate from normal OCR capture: never writes clipboard or starts translation.
@MainActor
final class DictionaryCaptureCoordinator: ObservableObject {
    @Published private(set) var status = "Press the dictionary shortcut, then drag a region to look up text."
    @Published private(set) var isBusy = false
    private let settings: AppSettings
    private let store: DictionaryStore
    private let resultPanel: ResultPanelController
    private let ensurePermission: () -> Bool
    private let selector = RegionSelector()
    private let ocr = OCRService()
    private let popup = DictionaryCapturePanel()
    private let model: DictionaryCaptureModel
    private let toast = StatusToast()
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var restoreResult = false

    init(settings: AppSettings, store: DictionaryStore, resultPanel: ResultPanelController,
         ensurePermission: @escaping () -> Bool) {
        self.settings = settings
        self.store = store
        self.resultPanel = resultPanel
        self.ensurePermission = ensurePermission
        model = DictionaryCaptureModel(store: store)
        popup.onDismiss = { [weak self] in self?.cancel() }
    }

    func perform() {
        guard !isBusy else { return }
        cancel()
        isBusy = true
        status = "Preparing dictionary selection…"
        let id = generation
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let installed = try await self.store.dictionaries()
                try Task.checkCancellation()
                guard !installed.isEmpty else {
                    self.isBusy = false
                    self.work = nil
                    self.report("No dictionaries installed", detail: "Import a Yomitan dictionary in Settings → Dictionaries first.")
                    return
                }
                let allowed = self.ensurePermission()
                try Task.checkCancellation()
                guard self.generation == id else { return }
                guard allowed else {
                    self.isBusy = false
                    self.work = nil
                    self.status = "Screen Recording permission is required for dictionary capture."
                    return
                }
                try Task.checkCancellation()
                guard self.generation == id else { return }
                self.restoreResult = self.resultPanel.hideForDictionaryCapture()
                self.status = "Dictionary selection — drag with the left mouse button; Escape/right-click cancels."
                self.work = nil
                self.selector.begin { [weak self] region in
                    guard let self, self.generation == id else { return }
                    guard let region else {
                        self.isBusy = false
                        self.restoreResultPanel()
                        self.status = "Dictionary selection cancelled. Clipboard unchanged."
                        return
                    }
                    self.capture(region, generation: id)
                }
            } catch is CancellationError {
                // Cancel/quit must not start a delayed selection overlay.
            } catch {
                guard self.generation == id else { return }
                self.isBusy = false
                self.work = nil
                self.report("Dictionary unavailable", detail: "Check the installed dictionaries and try again.")
            }
        }
    }

    private func capture(_ region: CaptureRegion, generation id: UUID) {
        let languages = settings.recognitionLanguages
        status = "Capturing dictionary region…"
        work = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == id {
                    self.restoreResultPanel()
                    self.isBusy = false
                    self.work = nil
                }
            }
            do {
                // Wait for selection overlays to leave the compositor.
                try await Task.sleep(for: .milliseconds(150))
                guard let screen = self.screen(for: region), let primary = NSScreen.screens.first else {
                    self.report("Display changed", detail: "Select a new dictionary region.")
                    return
                }
                let screenFrame = screen.frame
                let source = region.localRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
                let image: CGImage
                do {
                    image = try await SCScreenshotManager.captureImage(in: region.quartzRect(screenFrame: screenFrame, primaryMaxY: primary.frame.maxY))
                } catch {
                    try Task.checkCancellation()
                    self.report("Dictionary capture failed", detail: "Check Screen Recording permission and try again. Clipboard unchanged.")
                    return
                }
                try Task.checkCancellation()
                guard self.generation == id else { return }
                self.restoreResultPanel()
                self.status = "OCR recognizing selected text locally…"
                self.model.beginRecognizing()
                // Show persistent progress only after screenshot capture, never in it.
                self.popup.show(model: self.model, near: source, on: screen)
                let text = try await self.ocr.recognize(image, languagePreference: languages)
                try Task.checkCancellation()
                guard self.generation == id else { return }
                guard self.screen(for: region)?.frame == screenFrame else {
                    self.model.failRecognition("Display changed. Select a new dictionary region.")
                    return
                }
                self.model.setSource(text)
                self.status = "Dictionary OCR complete. Click a word in the result to look it up. Clipboard unchanged."
            } catch is CancellationError {
                // A dismissed popup or a normal capture cannot receive old OCR.
            } catch let error as OCRError {
                guard self.generation == id else { return }
                self.model.failRecognition(error.localizedDescription)
                self.status = "Dictionary OCR failed. Clipboard unchanged."
            } catch {
                guard self.generation == id else { return }
                self.model.failRecognition("Recognition failed. Select a clearer region and try again.")
                self.status = "Dictionary OCR failed. Clipboard unchanged."
            }
        }
    }

    func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
        selector.cancel()
        isBusy = false
        restoreResultPanel()
        popup.hide()
        model.clear()
        toast.hide()
    }

    private func restoreResultPanel() {
        if restoreResult { resultPanel.showLastResult() }
        restoreResult = false
    }

    private func screen(for region: CaptureRegion) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
                && region.isValid(on: $0.frame.size)
        }
    }

    private func report(_ title: String, detail: String) {
        status = "\(title): \(detail)"
        toast.show(title, detail: detail)
    }
}
