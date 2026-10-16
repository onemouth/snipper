# Snipper

Personal macOS 26 menu-bar OCR + translation app. No third-party dependencies.

## Milestones

- **Step 1 — complete:** AppKit menu bar, SwiftUI settings, persistent non-secret
  preferences, Keychain API-key storage, local app packaging, global shortcuts.
  User verified shortcut feedback. Four preference tests pass.
- **Step 2 — complete:** rectangle selection,
  ScreenCaptureKit screenshots, Apple Vision OCR, original-text clipboard copy,
  and recapture of the last region. Fourteen automated tests pass, including Vision
  recognition of generated English/Japanese text (no screen capture in tests).
- **Step 3 — complete (user confirmed):** one reusable,
  nonactivating result panel with read-only original text, copy, pin, drag, resize,
  close/Escape, and onscreen placement near the source.
- **Step 4 — implemented, awaiting manual translation verification:** OpenRouter
  translation, built-in prompt, automatic/manual modes, target selector, explicit
  translation copy, cancellation/latest-result-wins, bounded retry, and memory cache.
  Test Connection remains available independently.
- **Step 5 — pending:** final reliability testing.

## Build and run

Requires Xcode with the macOS 26 SDK and Swift 6.2+.

```sh
swift test
bash scripts/build-app.sh
open dist/Snipper.app
```

Quit the existing app before launching a rebuilt copy. Click the text-viewfinder
menu-bar icon for Capture Region, Recapture Last Region, Show Last Result,
Settings, and Quit.
Closing settings keeps the app running. Do not run multiple copies simultaneously.

The bundle identifier is `local.snipper.app`. Builds are ad-hoc signed, not
notarized or intended for distribution. Rebuilds may trigger renewed Keychain or
Screen Recording authorization. Consistent Developer ID signing is a future option.

## Capture and OCR

- **Shift–Command–2:** drag a rectangle around text. Escape or right-click cancels.
- **Shift–Command–1:** capture the last selected region again, without selecting.
- On success, original text is automatically copied and shown in a nonactivating
  result panel. Useful line breaks are preserved; styling is not. Copy Original
  copies it again explicitly. Cloud translation is optional; Copy Translation is
  enabled only after a successful translation and never runs automatically.
- Capture happens after releasing the mouse, not at the start of selection. For
  animated/game content, keep the text visible until recognition completes.
- Selection is limited to the display where dragging begins. Multiple displays
  are supported individually; a single rectangle cannot span displays.
- Last region and latest OCR result exist only in memory. Display movement is
  handled by retaining display-relative coordinates. Disconnecting or changing the
  selected display's logical size requires a new selection. Quit clears the region.
- Captures run one at a time; shortcuts during selection/capture/OCR are ignored.
- Cancelling, failed capture/OCR, and no-text results leave the clipboard unchanged.
  Settings shows the latest operation status without displaying the captured text.

### Result panel

One panel is reused for every successful capture, including when automatic
translation is disabled. Original text is selectable but not editable. Opening
it does not activate Snipper or take keyboard focus from the source app. Clicking
inside its text lets you select/copy and use Escape to close; Escape is not
intercepted globally while you continue typing or gaming in the source app.

Drag the native title bar to move it; resize from its edges. **Pin position** keeps
the current position for later captures (you can still drag while pinned). Unpinned
captures place it near the selected region and avoid source overlap where room
permits. Otherwise it minimizes overlap while staying onscreen. Display changes
clamp it back onto an available display. Pin and position are memory-only.

Close hides the panel without discarding the latest result. Use **Show Last Result**
in the menu bar to reopen it. It hides during selection/screenshot/OCR—even when
pinned—to avoid recognizing itself. A cancelled or failed capture restores the
previous panel only if it was visible before capture; its original text and your
clipboard remain unchanged on OCR/capture failures. If clipboard writing fails,
the new recognized text is still shown so Copy Original can retry.

### Permissions

Screen Recording permission is requested only when you first attempt capture.
Allow Snipper in **System Settings → Privacy & Security → Screen & System Audio
Recording**. Quit/reopen if macOS requests it, then retry. A permission-denied
capture does not read the screen or change the clipboard. No Accessibility or
Input Monitoring permission is required.

### Settings

Saved custom shortcuts are preserved. If another app (such as TextSniper) owns a
shortcut, settings reports the conflict and disables both shortcuts. Quit the
conflicting app or change the shortcuts, then click Retry. Shortcut edits
re-register automatically after a short delay. Keys currently use physical ANSI
positions, not layout-translated characters.

OCR language priority defaults to `en-US, ja-JP`. Vision automatic language
detection is enabled. Enter comma-separated language codes supported by the
installed Vision version; leave blank to use Vision's defaults. Unsupported codes
produce a configuration error rather than silently dropping the requested language.
OCR uses macOS 26's Vision `RecognizeDocumentsRequest`, including its document
reading-order transcript. This replaces the legacy text request, which missed the
reported vertical Japanese book page. Generated horizontal/vertical Japanese tests
and the supplied two-page sample now pass recognition/reading-order checks.
OCR is not limited to English/Japanese, but language support depends on Vision.
Furigana, unusual fonts, and complex layouts may still have recognition errors.

OpenRouter endpoint: `https://openrouter.ai/api/v1`. Enter a chosen model ID; none
is selected automatically. The API key is only stored in macOS Keychain, never
preferences or logs. The secure field clears after saving. “Check Key” checks local
storage only, not API validity, and does not reveal the key. The reusable chat
backend accepts compatible HTTPS base URLs in code; MVP settings expose the
OpenRouter preset only.

### Cloud translation

**Allow cloud translation is off by default**, including when upgrading an app
that already has a saved key. In Settings → Translation, review the disclosure,
enable that switch, and select a model. Your existing saved Keychain key is reused.
API charges and OpenRouter/model-provider data policies apply.

- With **Translate automatically after capture** on, each successful OCR capture
  copies/shows original text first, then translates asynchronously.
- With automatic translation off, captures stay local. Click **Translate** in the
  result panel to send that capture explicitly (cloud permission is still required).
- Target defaults to Traditional Chinese, with Japanese and English options in
  settings and the panel. Changing target clears stale translation but sends
  nothing until Translate or a new automatic capture.
- Original text is read-only. Copy Original and Copy Translation are separate;
  translation completion never touches the clipboard. Errors leave OCR useful.
- The built-in prompt requests fluent, faithful translation only, preserves names,
  numbers, tone and useful paragraphs, uses Taiwan vocabulary for Traditional
  Chinese, and treats captured content as data rather than instructions. There is
  no prompt editor or OCR editing workflow in the MVP. Prompt separation reduces
  instruction confusion; it cannot guarantee any model's translation behavior.
- Cancel stops local waiting. Closing the panel, starting capture, changing target,
  model, credentials, consent, or the automatic toggle cancels in-flight work.
  Old/cancelled results cannot replace a newer result or populate the cache.
  Configuration changes never silently translate an existing capture.
- Each request times out after 30 seconds. Only HTTP 429/502/503/529 get one retry
  after a 1-second delay; no timeout/network/authentication retries. Cancellation
  cannot undo provider processing or charges. A retry can also incur a charge.
- Input is capped at 12,000 characters, output at 8,192 completion tokens. Oversized
  input fails locally; output-limit responses are errors, not partial translations.
- An exact-text LRU cache is memory-only, capped at 32 entries / 200 KB of UTF-8
  source and translation. Keys include model, target, endpoint and prompt version.
  Quit, saved-key changes and revoking cloud permission clear it. Settings also
  offers Clear Translation Cache. It is never persisted or logged.

### Test Connection

1. Settings → Translation: enter your exact OpenRouter model ID.
2. Enter an API key and click **Save Key** (or reuse your previously saved key).
   Save or clear any unsaved new key before testing.
3. Click **Test Connection…**, review the possible API charge, and confirm.
4. Expect a progress indicator, then a success or sanitized failure message.

The test sends only the fixed sample `Hello.` for translation into Traditional
Chinese, independent of the target-language preference. It never reads captured
text or touches the clipboard. A nonempty model response confirms that the saved
key/model combination works; translation quality is not scored and the response
itself is not displayed or logged. Check Key remains a local storage check only.

Tests have a 30-second timeout, 256-completion-token cap, Cancel Test, and no
automatic retry. Reasoning models may exhaust this small output budget; use a
model suited to a short response. Cancellation/timeouts cannot reverse provider
work or charges already incurred. HTTP error bodies are not displayed; common
credential, quota, permission, model, rate-limit, and provider errors get safe
messages. Redirects are blocked; the HTTP session has no cache or cookies.

Automated tests use fake keys and injected responses, never your real key or a
billable request. Real OpenRouter connectivity and Keychain prompts require your
manual test. See [docs/connection-test-verification.md](docs/connection-test-verification.md).

## Privacy

Screenshots are transient in-memory images: never saved or sent over the network.
OCR runs on-device. No persistent capture history or source/translation/secret
logs. The latest OCR/translation result, selected region and bounded translation
cache are retained only in memory; copied
original text also remains in the system clipboard and may be read by clipboard
managers or synced by macOS according to system settings.

Test Connection sends only its fixed sample to OpenRouter and its selected model
provider, after explicit confirmation. It does not send captured text.

With Allow cloud translation enabled, automatic captures or an explicit Translate
send OCR text (with the built-in translation instructions) to OpenRouter and the
selected model provider—not screenshots. Translation never automatically
overwrites the clipboard.

## Step 2 manual verification

See [docs/step-2-verification.md](docs/step-2-verification.md). Interactive screen
capture, permission prompts, and focus restoration require verification on the
running app; automated tests use generated images only.

## Step 3 manual verification

See [docs/step-3-verification.md](docs/step-3-verification.md). Automated coverage
also exercises placement geometry, result replacement, pin state, and plain-text
copying using isolated test pasteboards (not your system clipboard).

## Step 4 manual verification

See [docs/step-4-verification.md](docs/step-4-verification.md). Automated translation
tests use injected responses and fake keys, not real or billable API calls. Coverage
includes prompt separation, consent, targets, cache limits, retries, cancellation,
late responses, credentials changes, and original-text preservation.
