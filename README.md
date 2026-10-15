# Snipper

Personal macOS 26 menu-bar OCR + translation app.

## Current milestone: foundation only

Implemented:
- Native AppKit menu bar and SwiftUI settings.
- Persistent non-secret preferences: shortcut combinations, OCR language priority,
  translation toggle, target language, OpenRouter model.
- Save/check/delete the OpenRouter API key using macOS Keychain.
- Local app-bundle packaging, with no third-party dependencies.

Not implemented yet: shortcut registration, screenshot capture, OCR, result panel,
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

Default shortcut preferences: Control–Option–2 (capture), Control–Option–3
(recapture). These are not registered until the capture milestone. Conflicts with
other applications will need handling when registration is implemented.

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
