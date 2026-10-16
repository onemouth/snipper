# Test Connection — manual verification

The connection test sends only its fixed sample. Captured-text translation is a
separate feature gated by Allow cloud translation (off by default). Real tests
may incur an API charge. Never paste your API key into chat, bug reports, or a screenshot.

## Successful connection

1. Quit Snipper, rebuild, and launch the updated app.
2. Open Settings → Translation. Enter an exact available OpenRouter model ID.
3. Save your API key with Save Key. The secure field should clear. If your key is
   already stored, Check Key confirms local storage only.
4. Copy a harmless sentinel into the clipboard.
5. Click Test Connection. Verify its confirmation explains the fixed sample and
   possible charge. Cancel first: there should be no request.
6. Reopen the confirmation and accept. Expect a progress indicator and a success
   message once the selected model returns visible text.
7. Paste the clipboard sentinel to verify the test did not overwrite it.
8. Leave Allow cloud translation off, then capture harmless text. The panel shows
   original text only—Test Connection does not grant permission to send OCR text.

The fixed sample is “Hello.”, translated into Traditional Chinese, regardless of
the currently selected target language. The test response is not shown or logged.
A success means the key/model returned text, not that translation quality was
evaluated. All automated tests use fake keys and mocked responses.

## Failure / cancellation checks (optional)

- Blank model: Test Connection is disabled until a model ID is supplied.
- Unsaved new key: Test Connection is disabled; save or clear the input first.
- No saved key: local error asks you to save one. No network request is made.
- Invalid saved key: authentication error, without raw response or key exposure.
  Do not replace a working key merely to exercise this optional scenario.
- Invalid model: safe rejected-model/request message.
- Offline: safe network error; UI becomes usable again.
- A long-running test: Cancel Test returns control. Its result must not later
  replace the cancelled status. A request already processed can still be charged.
- Edit the model or save/delete a key after a test: stale success should clear.
- Reasoning-heavy model: may hit the 256-token test limit or return no visible
  text. Choose a short-response model; do not repeatedly retry without reviewing
  possible charges.

No automatic retries occur. Each confirmed button press represents one application
request. A timeout/cancellation does not guarantee the provider stopped billing.
