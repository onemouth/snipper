import AppKit
import Combine
import ScreenCaptureKit

/// No screenshots are saved; only the latest OCR result and region remain in memory.
struct CaptureResult {
    let text: String
    let region: CaptureRegion
}

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var status = "Ready to capture."
    @Published private(set) var isBusy = false
    @Published private(set) var lastResult: CaptureResult?
    private(set) var lastRegion: CaptureRegion?

    private let settings: AppSettings
    private let resultPanel: ResultPanelController
    private let selector = RegionSelector()
    private let ocr = OCRService()
    private let toast = StatusToast()
    private var work: Task<Void, Never>?
    private var permissionRequested = false

    init(settings: AppSettings, resultPanel: ResultPanelController) {
        self.settings = settings
        self.resultPanel = resultPanel
    }

    func perform(_ action: CaptureAction) {
        guard !isBusy else {
            // Do not display a toast over a region currently being selected.
            return
        }
        if case .recapture = action, lastRegion == nil {
            report("No previous region", detail: "Select a region first with your capture shortcut.")
            return
        }
        guard ensurePermission() else { return }
        toast.hide()
        switch action {
        case .selectRegion:
            isBusy = true
            resultPanel.suspendForCapture()
            status = "Selecting region — Escape cancels."
            selector.begin { [weak self] region in
                guard let self else { return }
                guard let region else {
                    self.isBusy = false
                    self.status = "Selection cancelled. Clipboard unchanged."
                    self.resultPanel.restoreAfterCancelledOrFailedCapture()
                    return
                }
                self.lastRegion = region
                self.capture(region)
            }
        case .recapture:
            guard let lastRegion else {
                report("No previous region", detail: "Select a region first with your capture shortcut.")
                return
            }
            guard screen(for: lastRegion) != nil else {
                self.lastRegion = nil
                report("Previous region is unavailable", detail: "Display changed or disconnected. Select a new region.")
                return
            }
            isBusy = true
            resultPanel.suspendForCapture()
            capture(lastRegion)
        }
    }

    func stop() {
        work?.cancel()
        work = nil
        selector.cancel()
        toast.hide()
        resultPanel.stop()
        lastResult = nil
        lastRegion = nil
    }

    func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !permissionRequested {
            permissionRequested = true
            if CGRequestScreenCaptureAccess() { return true }
        }
        status = "Screen Recording permission required. Clipboard unchanged."
        let alert = NSAlert()
        alert.messageText = "Allow Snipper to read text from your screen"
        alert.informativeText = "Enable Snipper in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Snipper if macOS requests it. Screenshots are processed locally and are not saved."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func screen(for region: CaptureRegion) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
                && region.isValid(on: $0.frame.size)
        }
    }

    private func capture(_ region: CaptureRegion) {
        status = "Capturing selected region…"
        let languages = settings.recognitionLanguages
        work = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isBusy = false
                self.work = nil
                self.resultPanel.restoreAfterCancelledOrFailedCapture()
            }
            do {
                // Let hidden overlays/toasts leave the compositor before capture.
                try await Task.sleep(for: .milliseconds(150))
                guard let screen = self.screen(for: region), let primary = NSScreen.screens.first else {
                    self.report("Capture failed", detail: "Display configuration changed. Select a new region.")
                    return
                }
                let rect = region.quartzRect(screenFrame: screen.frame, primaryMaxY: primary.frame.maxY)
                let image: CGImage
                do {
                    image = try await SCScreenshotManager.captureImage(in: rect)
                } catch {
                    guard !Task.isCancelled else { return }
                    // Avoid system error payloads that could include sensitive metadata.
                    self.report("Capture failed", detail: "Check Screen Recording permission and try again. Clipboard unchanged.")
                    return
                }
                try Task.checkCancellation()
                self.status = "Recognizing text locally…"
                let text = try await self.ocr.recognize(image, languagePreference: languages)
                try Task.checkCancellation()
                let result = CaptureResult(text: text, region: region)
                let copied = ClipboardWriter.write(text)
                self.lastResult = result
                self.resultPanel.present(result, copiedAutomatically: copied)
                guard copied else {
                    self.report("Clipboard failed", detail: "Text is available in the panel. Use Copy Original to try again.")
                    return
                }
                self.status = "Original text copied (\(text.count) characters)."
            } catch is CancellationError {
                // Stop/quit never publishes a late result or writes the clipboard.
            } catch let error as OCRError {
                self.report("OCR failed", detail: error.localizedDescription)
            } catch {
                self.report("OCR failed", detail: "Recognition could not finish. Clipboard unchanged.")
            }
        }
    }

    private func report(_ title: String, detail: String) {
        status = "\(title): \(detail)"
        toast.show(title, detail: detail)
    }
}
