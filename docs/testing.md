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
