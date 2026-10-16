# Step 4 — translation verification

Quit the old Snipper and open the rebuilt `dist/Snipper.app`.
Use harmless English/Japanese samples. Real requests may incur API charges and
are subject to OpenRouter and its selected provider's data policies. Never include
your key in bug reports or screenshots. Automated tests use fake keys/stub replies.

## Setup and explicit permission

1. In Settings → Translation, reuse/save your Keychain key and enter an available
   OpenRouter model ID. Test Connection remains an optional fixed-sample test.
2. On a first launch/upgrade, Allow cloud translation must be off even if a key was
   already saved. Capture harmless text: original is copied/shown, no cloud request.
3. Clicking Translate with cloud permission off must explain how to enable it,
   without sending anything or changing the clipboard.
4. Review the cloud disclosure and enable Allow cloud translation. Enabling it must
   not send the old capture automatically. Each request can incur a charge.

## Automatic translation and clipboard

1. Enable Translate automatically after capture; target Traditional Chinese.
2. Capture `Hello. How are you today?`
3. Expect original text to appear/copy first, then a translating status/Cancel,
   then Traditional Chinese text. The result arriving must not move/activate the
   panel or replace clipboard contents.
4. Paste before and after translation. Both should paste original text.
5. Click Copy Translation, paste again: now it should be the translation.
6. Click Copy Original: the full original should copy again.
7. Repeat with Japanese, including vertical book text; inspect meaning/tone and
   paragraph flow. OCR errors remain visible; there is no original-text editor.

## Manual translation and targets

1. Turn automatic translation off. Capture: original-only, no automatic request.
2. Click Translate. Translation should arrive normally.
3. Change the panel target to English/Japanese. Old translation must clear and
   Copy Translation disable. Nothing is sent until Translate or a new automatic
   capture. Click Translate and inspect the new target language.
4. The target choice should also appear in settings and affect future captures.
5. Changing model or saving/deleting a key clears stale translation too.

## Cancellation, reuse, and failures

1. While translating, click Cancel. Original stays available; no late response
   should replace the cancellation status.
2. Start another translation, then close/Escape the panel. It must not reopen when
   the provider finishes. Show Last Result may reopen the original; Translate retries.
3. While an old translation is pending, capture new text. The prior request cancels.
   Only the new capture's result may be displayed or cached.
4. Revoke Allow cloud translation while a request is pending. It cancels, clears
   translation/cache, and cannot publish a late result. Original stays available.
5. Try offline or an invalid model (optional). Expect a translation-specific safe
   error, with original OCR and Copy Original still usable. No raw provider body,
   source text, or secret should appear in error messages.
6. Timeout/network/authentication failures aren't retried. HTTP 429/502/503/529 get
   at most one retry after 1 second. Cancellation/timeouts and retries may still
   incur provider charges; provider processing cannot be undone locally.
7. A capture over 12,000 characters should copy/show original, but fail translation
   locally. An output-limit response should be an error, not incomplete text.

## Cache and panel behavior

- Translate identical text with the same model/target again: reuse memory cache.
  Changing target/model must not reuse the wrong translation.
- Clear Translation Cache in settings before repeating if you want a fresh request.
  A request already running can finish and add its new result afterward.
- Saving/deleting a key or revoking cloud permission clears cached entries.
- Quit/relaunch: no OCR text, translations, region, pin position, or cache is restored.
  Non-secret preferences and Keychain credentials remain.
- Verify pin/drag/close and source-app focus still work while translations arrive.
- For instruction-like source text, verify the model translates it rather than
  following it. The built-in prompt separates instructions from captured content,
  but model behavior still needs real-world validation.

Report action steps, target/model ID (not API key), safe error/status wording, and
focus/clipboard behavior. Do not share private captured text unless you choose a
safe example.
