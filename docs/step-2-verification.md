# Step 2 — manual verification

Use non-sensitive sample text. Do not paste private captures into bug reports.
Turn Allow cloud translation off for this local-only check. Quit the old Snipper,
build, and launch `dist/Snipper.app`. Quit any app owning
Shift–Command–2 or change the shortcut in settings.

## 1. First capture / permission

1. Type `clipboard sentinel` into a text editor and copy it.
2. Press Shift–Command–2 and follow the Screen Recording permission prompt.
3. If denied, verify there is no selection capture and the sentinel still pastes.
4. Allow Snipper in System Settings; quit/reopen if requested by macOS.
5. Retry Shift–Command–2. Expect a dim overlay and crosshair cursor.

Permission UI and wording vary with macOS. No Accessibility/Input Monitoring
permission should be requested. Permission prompts may activate Snipper; ordinary
capture should not activate it.

## 2. OCR and original clipboard

Display these lines in a text editor, reasonably large (e.g. 24 pt):

```text
Hello Snipper
日本語のテスト
This is the original text.
```

1. Close Snipper Settings so it does not cover the source.
2. Select only the sample lines with Shift–Command–2.
3. Expect the overlay to disappear, then the original-text result panel. Its footer
   confirms the original was copied automatically.
4. Paste into another document. Expect original English/Japanese text with line
   breaks, not a translation. No API key is needed.
5. Check that the source app retains keyboard focus after selection.
6. Try the menu-bar Capture Region command too.

## 3. Cancel and empty OCR

1. Copy the sentinel again, invoke selection, and press Escape. Clipboard unchanged.
2. Repeat and right-click to cancel. Clipboard unchanged.
3. Try a tiny click/drag (under 4 points). It cancels without copying.
4. Capture a blank area. Expect “No readable text” and unchanged clipboard.
5. In settings enter `not-a-language` as the OCR language, then capture sample text.
   Expect an OCR configuration error and unchanged clipboard. Restore `en-US, ja-JP`.

## 4. Recapture

1. Select the sample text normally.
2. Change text inside that same source area; wait for it to render.
3. Press Shift–Command–1. No overlay; newly recognized original text is copied.
4. Invoke shortcuts rapidly during capture/OCR. Operations must not overlap or
   publish a delayed older clipboard result after a newer capture.
5. Quit/reopen and try recapture first. Expect “No previous region”; clipboard
   unchanged. No permission prompt is needed merely to report no previous region.

## 5. Displays and game use (if available)

- Repeat capture on each display, including Retina/external displays and displays
  arranged left of, above, or below the primary display. Verify the selected area
  matches copied content, not a vertically shifted area.
- Drag in all directions. Selection remains within the starting display.
- Move a display's arrangement without changing resolution; recapture should follow
  its display-relative region. Change its logical resolution/disconnect it; expect
  a request to select a new region rather than capturing a different display.
- Change display configuration during selection; selection should cancel safely.
- Try ordinary full-screen apps and visible game dialogue. Protected content and
  exclusive full-screen games may not be capturable; record app/mode and symptom
  without sharing private content. Verify focus returns after overlay dismissal.

## Reporting a failure

Provide the operation, whether permission was granted, display arrangement/scale,
expected behavior, observed toast or Settings status, and whether clipboard/focus
changed. Captured text and screenshots are not needed unless you explicitly choose
to share safe examples.
