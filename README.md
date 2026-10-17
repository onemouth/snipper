# Snipper

Capture text from your screen, copy it instantly, and optionally translate it—all
from the macOS menu bar.

Snipper uses Apple Vision for on-device OCR and OpenRouter for optional cloud
translation. Built with Swift, AppKit, and SwiftUI, with no third-party dependencies.

## Features

- Select a screen region with a global shortcut, or recapture the last region.
- Automatically copy the **original text** as plain text with useful line breaks.
- Recognize English, Japanese—including vertical text—and other Vision-supported languages.
- Press **⌃⌥Z** and drag a region for local OCR and dictionary lookup.
- View results in a reusable floating panel without activating Snipper.
- Drag, resize, or pin the panel; reopen the latest result from the menu bar.
- Translate automatically or on demand into Traditional Chinese, Japanese, or English.
- Keep original and translated text separate, with explicit copy controls.
- Store API credentials in macOS Keychain.

## Requirements

- macOS 26 or later.
- Xcode with the macOS 26 SDK or later and Swift 6.2 or later to build.
- An OpenRouter API key and model for translation. **OCR works without either.**

## Build and run

```sh
git clone https://github.com/onemouth/snipper.git
cd snipper
bash scripts/build-app.sh
open dist/Snipper.app
```

Snipper runs in the **menu bar**, not the Dock. Click its text-viewfinder icon for
capture commands, settings, the latest result, or Quit. Closing a window does not
quit the app. Quit the existing copy before launching a rebuilt version.

The build produces a locally ad-hoc-signed app, not a notarized distribution.
Rebuilds may prompt macOS to request Screen Recording or Keychain access again.

## Usage

| Default shortcut | Action |
| --- | --- |
| **⇧⌘2** | Select a region and recognize its text |
| **⇧⌘1** | Recapture the last selected region |
| **⌃⌥Z** | Select a region for OCR and local dictionary lookup (no automatic copy) |
| **Escape / right-click** during selection | Cancel without changing the clipboard |

On first capture, grant Screen Recording access in **System Settings → Privacy &
Security → Screen & System Audio Recording**. Quit and reopen Snipper if macOS
requests it. Accessibility and Input Monitoring permissions are not required.

For normal capture (⇧⌘2 / ⇧⌘1), the original text is copied and displayed immediately. Drag the
panel by its title bar or use **Pin position** to keep it in place across captures.
Click inside the text, then press Escape to close; Escape is not intercepted while
you work in another app. **Show Last Result** reopens the latest result.

Shortcuts are configurable in Settings. If another app owns a shortcut, change it
or quit that app, then click **Retry Shortcut Registration**.

### Translation setup

1. Open **Settings → Translation**.
2. Enter an OpenRouter model ID and save your API key with **Save Key**.
3. Optionally use **Test Connection…** to check the saved key and model. It sends
   only the fixed sample “Hello.” and may incur a small API charge. **Check Key**
   checks local Keychain storage only.
4. Review the disclosure and enable **Allow cloud translation**—off by default.
5. Choose your target language and whether to **Translate automatically after capture**.

With automatic translation off, click **Translate** in the result panel to send
that capture. Changing the target clears the old translation but does not send a
new request until you click Translate or make a new automatic capture.

**Translation never automatically overwrites the clipboard.** Use Copy Translation
when you want it, or Copy Original to copy the recognized text again. Translation
failures leave the original available.

The built-in prompt preserves meaning, tone, names, numbers, and useful paragraph
breaks, using Taiwan vocabulary for Traditional Chinese. Captured text is sent
separately from translation instructions. Translation quality depends on the model;
there is no prompt editor or original-text editing workflow.

## Local dictionaries

In **Settings → Dictionaries**, choose **Import Dictionary…** and select a
Yomitan format 3 term dictionary ZIP. Imports run locally with progress and
cancellation. The list shows each dictionary’s title, revision, entry count, and
image count; Delete removes the imported copy, not your original ZIP.

Use **Test dictionary lookup** in the same tab to search an exact headword or
reading, such as `猫` or `ねこ`, across all dictionaries or a selected dictionary.
Press Return or click Search for a selectable results popover with readings,
headwords, dictionary labels, definitions, and inline local images. Show Results
reopens the popup; Escape or clicking outside dismisses it. Lookup never uploads
text or changes the clipboard automatically. Results are limited to 30 entries.

### OCR → dictionary

1. Import a dictionary, then press **⌃⌥Z** (Control–Option–Z).
2. Release the keys and **drag a rectangle with the left mouse button** around the
   text you want to read. Escape/right-click cancels.
3. Release the mouse. The dictionary panel shows **OCR recognition progress**.
4. A single selected word is looked up automatically. For longer text, **click a
   word in the read-only OCR text** to look it up. The matched text is selected,
   and the **Lookup** label confirms the query.

The panel shows readings, dictionary labels, definitions, and supported inline
images. Drag its title bar or resize it; scroll long OCR text and definitions.
Dragging within the OCR text selects text normally for explicit copying. Click
outside or the close button to dismiss; after clicking inside the panel, Escape
also closes it. Escape is not intercepted globally in the source app.

This workflow supports horizontal and vertical Japanese, runs entirely locally,
and **does not automatically copy text or start translation**. It does not replace
the last normal capture/result or remembered recapture region. Screenshots are
transient, and closing the dictionary panel discards its OCR text and results.
There is no continuous mouse tracking or background OCR loop.

Screen Recording permission and an installed dictionary are required. The shortcut
is configurable in General settings. Shortcuts during selection/capture/OCR are
ignored; starting normal capture cancels dictionary capture. Only one display can
be selected at a time. **Deinflection is not available yet**—use dictionary-form
words. OCR errors, small furigana, cropped words, and unusual layouts may prevent
matching. Clicking another word searches the existing OCR text without recapturing.

### Format support

Terms, tags, definition JSON, and PNG/JPEG/GIF/WebP images are preserved. The preview supports basic structured
content, not full Yomitan styling; links are text-only and unusually large previews
are shortened. Frequency, pitch-accent, kanji banks, and custom styles are not
imported. Duplicate titles are rejected; delete the installed version before
importing a replacement.

Dictionaries persist under `~/Library/Application Support/Snipper/Dictionaries/`.
Only import dictionaries you have permission to use; no third-party dictionaries
are bundled. Imports are limited to a 1 GB ZIP, 2 GB expanded data, 32 MB per file,
100,000 archive entries, and 2 million term entries.

## Privacy

- **Screenshots stay local:** processed in memory, never saved or uploaded.
- **Cloud translation is opt-in:** only OCR text and translation instructions go to
  OpenRouter and its selected model provider. Their data policies and API charges apply.
- **Secrets stay in Keychain:** API keys are not stored in preferences or logs.
- **No persistent capture history:** results, the last region, and the bounded
  translation cache exist only in memory and clear on quit.
- **No source, translation, or API-secret logging.**
- **Imported dictionaries stay local:** dictionary databases and images persist
  until deleted and are never uploaded.

Copied text remains in the system clipboard and may be accessed by clipboard
managers or synced according to your macOS settings. Clear Translation Cache in
Settings removes cached translations; saved-key changes and revoking cloud access
also clear the cache.

## Limitations

- A selection stays on one display. Recapture requires a new selection after the
  selected display disconnects or changes logical resolution.
- Capture occurs after releasing the mouse; keep animated text visible until OCR completes.
- OCR language priority defaults to `en-US, ja-JP`, with automatic language detection.
  Other language codes must be supported by the installed Vision version. Small
  furigana, unusual fonts, and complex layouts can still produce errors.
- Shortcut keys currently use physical ANSI positions rather than layout-translated characters.
- Translation input is limited to 12,000 characters and output to 8,192 completion tokens.
  Requests time out after 30 seconds; selected temporary provider errors get one retry.
  Cancelling cannot undo provider processing or charges already incurred.
- Settings expose OpenRouter only; the underlying chat client accepts compatible HTTPS endpoints.

## Development

```sh
swift test
```

Tests use generated OCR images, isolated pasteboards, fake keys, and mocked API
responses—not real credentials or billable requests. See [Testing](docs/testing.md)
for manual checks that require the running app.

SQLite and ZIP import use macOS’s system SQLite and libarchive libraries through
small C interop targets. Private dictionary ZIPs in `testdata/` and generated SQLite
files are ignored by Git. The optional real-dictionary import check is documented
in [Testing](docs/testing.md).

Regenerate the pixel-art app icon with:

```sh
swift scripts/generate-app-icon.swift
bash scripts/build-app.sh
```
