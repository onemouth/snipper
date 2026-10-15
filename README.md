# Snipper

Personal macOS 26 menu-bar OCR + translation app. No third-party dependencies.

## Milestones

- **Step 1 — complete:** AppKit menu bar, SwiftUI settings, persistent non-secret
  preferences, Keychain API-key storage, local app packaging, global shortcuts.
  User verified shortcut feedback. Four preference tests pass.
- **Step 2 — implemented, awaiting manual capture verification:** rectangle selection,
  ScreenCaptureKit screenshots, Apple Vision OCR, original-text clipboard copy,
  and recapture of the last region. Fourteen automated tests pass, including Vision
  recognition of generated English/Japanese text (no screen capture in tests).
- **Steps 3–5 — pending:** floating result panel, OpenRouter translation, final
  reliability testing. Translation preferences currently make no network requests.

## Build and run

Requires Xcode with the macOS 26 SDK and Swift 6.2+.

```sh
swift test
bash scripts/build-app.sh
open dist/Snipper.app
```

Quit the existing app before launching a rebuilt copy. Click the text-viewfinder
menu-bar icon for Capture Region, Recapture Last Region, Settings, and Quit.
Closing settings keeps the app running. Do not run multiple copies simultaneously.

The bundle identifier is `local.snipper.app`. Builds are ad-hoc signed, not
notarized or intended for distribution. Rebuilds may trigger renewed Keychain or
Screen Recording authorization. Consistent Developer ID signing is a future option.

## Capture and OCR

- **Shift–Command–2:** drag a rectangle around text. Escape or right-click cancels.
- **Shift–Command–1:** capture the last selected region again, without selecting.
- On success, original text is automatically copied; a nonactivating toast confirms
  the character count. Paste into a text editor to inspect OCR until Step 3 adds
  the result panel. Useful line breaks are preserved; styling is not.
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
OCR is not limited to English/Japanese, but support depends on Vision. Complex
columns, vertical writing, and unusual game fonts may need future refinement.

OpenRouter endpoint: `https://openrouter.ai/api/v1`. Enter a chosen model ID; none
is selected automatically. The API key is only stored in macOS Keychain, never
preferences or logs. The secure field clears after saving. “Check Key” checks local
storage only, not API validity, and does not reveal the key. Translation is not
implemented yet, even if its preference is enabled.

## Privacy

Screenshots are transient in-memory images: never saved or sent over the network.
OCR runs on-device. No persistent capture history or source/translation/secret
logs. Only the latest OCR text and selected region are retained in memory; copied
original text also remains in the system clipboard and may be read by clipboard
managers or synced by macOS according to system settings.

In a later milestone, requesting translation will send only OCR text—not
screenshots—to OpenRouter and the selected model provider. Translation cache will
be memory-only. Translation will never automatically overwrite the clipboard.

## Step 2 manual verification

See [docs/step-2-verification.md](docs/step-2-verification.md). Interactive screen
capture, permission prompts, and focus restoration require verification on the
running app; automated tests use generated images only.
