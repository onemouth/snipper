# Step 3 — result panel verification

Quit the old Snipper and launch the rebuilt `dist/Snipper.app`. Use non-sensitive
English/Japanese sample text. No API key is needed and no translation request runs.

## Original text, focus, and clipboard

1. Capture sample text with Shift–Command–2. Expect one panel near the selected
   region, preferably not overlapping it, and entirely within the usable screen.
2. Verify the original is shown immediately after OCR and matches what pastes.
   Translation explains that Step 4 is pending; Copy Translation is disabled.
3. Without clicking Snipper, type in the source app. The source must still own
   keyboard focus. Escape in the source app must NOT close Snipper's panel.
4. Click inside Original, select some text, and use Command–C. Selection copying
   should work; typing or pasting into Original must not edit the OCR text.
5. Click Copy Original. Paste elsewhere to verify the full original, not merely
   its selection, is copied as plain text with useful line breaks.
6. Click inside the panel's text, then Escape. The panel closes and focus returns
   to the source. The native close button also hides it.
7. Choose Show Last Result from the menu bar. The same latest result reopens.
8. Try a very long capture; scrolling and window resizing must keep text and
   controls usable.
9. Capture vertical Japanese book text. Verify characters read top-to-bottom within
   a column, then columns right-to-left. For two-page spreads, verify the right page
   precedes the left. The macOS 26 document-recognition API is used for this; the
   previous legacy text API returned no text for the reported sample. Small furigana
   and unusual typography may still need correction.

## Reuse, pin, and capture safety

1. Capture twice. Only one result panel should exist and contain the newest text.
2. Drag its title bar. Pin position, then capture a region elsewhere. The panel
   should reappear at the pinned position, with the new original.
3. Drag it while pinned; another capture should retain that new position.
4. Unpin and capture again; it should position near the new source.
5. Move the panel so it covers part of the remembered capture region. Recapture
   using Shift–Command–1. It must hide before the screenshot and recognize the
   underlying source, not Snipper's previous result or placeholder.
6. Start selection, then Escape/right-click. A previously visible panel should
   return unchanged; clipboard stays unchanged. If the panel was already closed,
   cancellation should NOT reopen it.
7. Capture a blank area. Expect an OCR error and the prior visible result restored,
   not an empty panel or clipboard. A closed panel should stay closed on failure.
8. Turn automatic translation off in settings, then capture. The original panel
   still appears and is copied. Translation stays unavailable regardless of the
   setting until Step 4.

## Displays (if available)

Capture near all four screen edges and on another display, including negative
screen origins. The panel should remain onscreen. When no adjacent area can fit
the panel, some source overlap is unavoidable; dragging/pinning offers control.
Pin it on a secondary display, disconnect that display, and confirm it moves onto
a remaining screen. Full-screen/game focus and panel visibility need checking in
your actual apps.

Report observed focus/clipboard behavior, display arrangement, and action steps.
No private OCR text or screenshots are needed.
