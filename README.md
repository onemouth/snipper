# Snipper

Personal macOS 26 menu-bar OCR + translation app.

## Step 1: foundation — complete

Verified: four preference tests pass, release app builds, and the user confirmed
shortcut confirmation feedback works. Steps 2–5 have not started.

Implemented:
- Native AppKit menu bar and SwiftUI settings.
- Persistent non-secret preferences: shortcut combinations, OCR language priority,
  translation toggle, target language, OpenRouter model.
- Save/check/delete the OpenRouter API key using macOS Keychain.
- Local app-bundle packaging, with no third-party dependencies.

Global shortcuts are registered for a foundation smoke test: pressing either shows
an on-screen confirmation without taking screenshots or activating Snipper. Settings
shows registration status and the last received action. No Accessibility or Input
Monitoring permission is needed. Actual capture remains unimplemented.

Not implemented yet: screenshot capture, OCR, result panel,
translation requests, or translation cache. The capture menu entry is intentionally
disabled. No screen-recording permission is requested by this build.

## Build and run

Requires Xcode with the macOS 26 SDK and Swift 6.2+.

```sh
swift test
bash scripts/build-app.sh
open dist/Snipper.app
```

Click the text-viewfinder icon in the menu bar, then **Settings…**.
Closing settings keeps the app running; use **Quit Snipper** to exit.
Settings activation is intentional; the future result panel will not steal focus.

The bundle uses the stable identifier `local.snipper.app` and a local ad-hoc
signature. It is not notarized or intended for distribution. Rebuilds may cause
Keychain authorization prompts; consistent Developer ID signing is a future option.
Do not run multiple copies simultaneously.

## Settings

Default shortcut preferences: Shift–Command–2 (capture), Shift–Command–1
(recapture). Press them to test the confirmation toast. If another app (such as
TextSniper) owns a shortcut, settings reports the conflict and disables both
shortcuts. Quit the conflicting app or change the shortcuts, then click Retry.
Changing preferences automatically re-registers after a short delay. Saved custom
shortcuts are preserved. Letter/digit keys currently use physical ANSI positions,
not layout-translated characters.

OCR language priority defaults to `en-US, ja-JP`. Actual supported languages and
validation will come from Vision in the OCR milestone.

OpenRouter endpoint: `https://openrouter.ai/api/v1`. Enter your chosen model ID;
none is selected automatically. Provider prices and availability vary.
The API key is never stored in preferences, source files, or logs; the secure field
is cleared after saving. “Check Key” checks local storage only, not API validity.
It does not display the saved key.

## Privacy contract for subsequent milestones

OCR stays on-device. Only recognized text—not screenshots—will be sent to
OpenRouter and the selected model provider when translation is requested.
No persistent capture history, screenshots, source/translation logs, or API-secret
logs. Translation cache is memory-only. Original text is automatically copied;
translation is copied only on explicit request.
