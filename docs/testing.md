# Testing

Run automated tests with `swift test`. They cover OCR on generated horizontal and
vertical Japanese/English images, coordinate conversion, panel placement, clipboard
writes, translation prompts, consent, caching, retries, and stale-result rejection.
API tests use fake keys and injected responses; clipboard tests use isolated
pasteboards. They do not access real credentials or make billable requests.

The following checks need the running macOS app. Use non-sensitive sample text.
Quit the old copy, run `bash scripts/build-app.sh`, and open `dist/Snipper.app`.

## Local capture and panel

Keep **Allow cloud translation** off for these checks.

- Capture English and Japanese with ⇧⌘2. Original text should appear and copy as
  plain text, retaining useful line breaks. Include vertical Japanese and check
  top-to-bottom characters and right-to-left column order.
- Cancel selection with Escape/right-click. Try a tiny selection, blank region,
  or unsupported OCR language code. Clipboard should remain unchanged on failure.
- Change text inside the selected region and press ⇧⌘1. Expect the new text, with
  no selection overlay. After quitting/reopening, recapture should ask for a region.
- Deny Screen Recording permission: no capture or clipboard change. Grant access
  in System Settings, relaunch if requested, and verify capture works.
- Confirm shortcut conflicts are reported and Retry works after resolving them.
- Check that panel appearance does not take keyboard focus from the source app.
  Text is selectable but read-only; Copy Original copies the full result. Escape
  closes when interacting with the panel, not while typing in the source app.
- Exercise drag, resize, scrolling, pinning, close, and Show Last Result. New results
  reuse one panel. A pinned panel retains position across captures.
- Cover the remembered region with the panel and recapture: it must hide before
  capture so OCR reads the underlying source. Cancelled/failed captures restore
  the previous panel only if it was visible before capture.

## Translation

Real requests may incur API charges. Never include API keys in reports or screenshots.

- Save a Keychain key and model ID. Test Connection should require confirmation,
  send only its fixed sample, and leave the clipboard unchanged. Cancel its
  confirmation to verify nothing is sent. Unsaved keys must be saved or cleared first.
- With cloud permission off, captures stay local even if a key exists. Translate
  should explain the required setting. Enabling permission must not send an old capture.
- Enable cloud and automatic translation. Capture a short sample: original appears
  first, then translation. Pasting before/after completion should still give the
  original until Copy Translation is explicitly clicked.
- Turn automatic translation off. Only clicking Translate should send the capture.
  Test Traditional Chinese, Japanese, and English targets. Target/model/key changes
  clear stale translations without automatically resending an existing capture.
- Cancel while translating, close the panel, start a new capture, or revoke cloud
  permission. A late response must not replace the current result or reopen the panel.
- Test offline/invalid-model failures if practical. Errors must be safe and leave
  the original and Copy Original usable. No raw provider payload should be displayed.
- Repeat identical text with the same model/target: expect a memory-cache hit.
  Clear the cache and retry for a fresh request. Key changes/revoked consent clear
  it; a request already in flight can repopulate it after manual cache clearing.
- Translation input over 12,000 characters should fail locally without losing OCR.
  Output-limit responses should report failure rather than present incomplete text.

Test Connection has no retry. Translation retries HTTP 429/502/503/529 once after
one second; authentication, timeout, and network failures are not retried.
Cancellation does not guarantee the provider stopped processing or billing.

## Dictionary import

Automated tests generate tiny original ZIP fixtures, including structured content
and a local image. They cover exact headword/reading queries, persistence, deletion,
duplicates, invalid entries, missing images, unsafe paths/links, CRC errors, resource
limits, and cancellation rollback. No third-party dictionary is bundled.

For the supplied local integration dictionary (92,217 terms / 2,598 images), run:

```sh
SNIPPER_TEST_DICTIONARY="/path/to/local-dictionary.zip" swift test --filter localDictionaryIntegration
```

This uses a temporary database and removes it afterward. It does not install the
dictionary into your normal app storage or upload any content.

Manual checks in **Settings → Dictionaries**:
- Import your format 3 ZIP; verify progress, title, revision, entry/image counts.
- Close/reopen Settings or restart the app; the dictionary should remain installed.
- Import the same title again; it should be rejected without changing the installed copy.
- Cancel a large import. Nothing should appear installed; retry should work.
- Delete with confirmation; the imported database/images disappear, while the source ZIP remains.
- In Test dictionary lookup, search a headword and reading (for example `猫` and
  `ねこ`). Return and Search should open the same results popover. Check reading,
  headword, dictionary source, plain definitions, and entries containing local images.
- Select a dictionary, then All installed dictionaries; verify filtering. Search
  an absent word for a no-match message; inflected forms are not deinflected yet.
- Select/copy text explicitly; search itself must not change the clipboard. Scroll
  long definitions, close with Escape/click outside, and reopen with Show Results.
- Edit the query, change dictionaries, close Settings, or begin import/deletion
  during a search: stale results must not reopen a popup. Deleting the selected
  dictionary should reset selection to All installed dictionaries.
- Test in light/dark appearance. Dictionary HTML-like text is literal, links do
  not open/fetch, and basic structured formatting/images render without scripts.
- Check capture and translation still work. Search/import must not modify
  credentials or cloud consent.

Imported data lives under `~/Library/Application Support/Snipper/Dictionaries/`.
A separate SQLite database and resources folder are published atomically for each
dictionary. Interrupted staging imports are removed on first dictionary access
after restarting. Do not run multiple Snipper copies against the same storage.

## OCR → dictionary region selection

Import a term dictionary, then use harmless text in a separate app:

- Press **⌃⌥Z**, release all keys, and drag a rectangle with the left mouse button.
  The selection overlay must remain available without holding modifiers.
- Escape/right-click/tiny selection cancels without changing the clipboard.
- After releasing the mouse, the dictionary panel should show persistent OCR
  progress, followed by the recognized original text. No source-app activation
  should occur merely because the result appears.
- Select a single known word: definitions should load automatically. Select a
  sentence or multiple lines: click words in the OCR source to change definitions.
  Clicking does not recapture the screen. Try Japanese inflections such as
  `食べなかった`, `読んでいる`, `行きました`, and `高かった`: verify base forms and
  explanation chains. The selection must stay on the original inflected text.
- Check the Lookup label and source selection identify the actual matched word,
  including repeated words, Japanese compounds, and text after emoji/combining marks.
- Original text starts in a 44-point strip; Expand text / Collapse text should make
  multiline text accessible without losing the selected word. Short words should
  not reserve a large empty source area. Drag to select/copy; source remains read-only.
- Identical spelling/reading results share one headword, followed by dictionary
  badges and numbered senses. Different readings stay separate. Check hanging
  indentation on wrapped senses, nested ordered/unordered lists, emphasis, and tags.
  Inflection explanations should not repeat for every identical entry.
- Scroll long text/definitions, resize/drag the panel, and check inline images.
- Click punctuation or an absent word: clear old definitions/selection and show
  safe guidance. Blank captures should show an OCR error rather than old entries.
- Rapidly click different words: old responses must not replace newer matches.
  Close while OCR/search is pending: late results must not reopen the panel.
- Click outside/close or Escape within the panel to dismiss it and discard its
  source/results. Escape in the source app is not intercepted globally.
- Copy a sentinel first: dictionary capture/search must leave it unchanged even
  with cloud permission and automatic translation enabled. No translation should start.
- Start normal ⇧⌘2 capture during dictionary capture: cancel dictionary work and
  preserve normal capture behavior. Lookup during normal capture is ignored.
  Dictionary capture must not replace the normal result or last recapture region.
- Cover source text with the normal OCR result panel: dictionary selection/capture
  should hide it, then restore it unchanged without cancelling its translation.
- Repeat horizontal/vertical Japanese and Retina/external/negative-origin displays.
  Selection remains on one display. Display changes cancel selection or dismiss
  the dictionary panel safely.
- With no dictionary installed, ask for import before selection or Screen Recording.
  Check permission denial, shortcut conflicts, and custom dictionary shortcut persistence.

Automated coverage includes all 1,446 pinned upstream Japanese deinflection cases
(including invalid cases and exact reason chains), rule-tag filtering before result
limits, exact-match precedence, ambiguous lemmas, bounded/cancelled expansion,
word candidates, exact matched occurrence, UTF-16 conversion, single-word auto
lookup, clickable multiword model state, stale-result rejection, safe failures,
OCR-to-SQLite matching, and existing capture geometry and horizontal/vertical OCR. Presentation tests cover stable grouping, distinct readings,
source badges, native emphasis/lists, sense indentation, and compact source sizing.
Native click hit-testing, permissions, focus, and actual
game/full-screen behavior still need manual checks.

## Deinflection packaging and licensing

- Check Settings lookup with inflected Japanese; it should match OCR lookup.
- Reuse an existing import without reimporting. Dictionaries without compatible
  rule tags must not supply derived results; exact matches still work.
- Check Settings → About, Open License, and Open Third-Party Notice. App resources
  must contain `JapaneseDeinflection.json`, `LICENSE`, and `Yomitan-NOTICE.md`.
- Build and copy the app away from the repository/build directory; verify lookup
  does not depend on SwiftPM’s absolute build-time resource path.
- Regenerate data with `node scripts/generate-japanese-deinflection.mjs`; files
  must be deterministic. Node is not needed for `swift test` or app packaging.

## Displays and full-screen apps

When available, test Retina/external displays arranged left, right, above, and below
the primary display. Select near each edge and drag in all directions. Selection
must stay on the starting display; the result panel should remain onscreen and
avoid source overlap where space allows.

Move a display without changing resolution: recapture should follow its
relative region. Disconnect/change its logical resolution: require a new region.
Changing displays during selection should cancel safely. Disconnect a display
with a pinned panel: the panel should move onto a remaining screen.

Check focus and capture in actual full-screen apps/games. Protected content and
exclusive full-screen modes may not be capturable.

## Reporting issues

Include reproduction steps, macOS version, model ID if relevant, safe status/error
wording, display arrangement, and whether focus or clipboard contents changed.
Use harmless examples rather than private captured text. Never share an API key.
