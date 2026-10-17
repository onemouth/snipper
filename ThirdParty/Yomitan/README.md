# Yomitan Japanese deinflection

- Upstream: https://github.com/yomidevs/yomitan
- Pinned revision: `e7334a96106a6c74e6fa75bd33a5ea1219d92712`
- License: **GPL-3.0-or-later**; see `LICENSE` here and at the project root.
- Copyright: Yomitan Authors (2024–2026 for rules/engine); Yomitan Authors
  (2023–2026) and Yomichan Authors (2020–2022) for test sources.

The files under `ext/` and `test/` are unmodified snapshots from that revision.
The transformer references upstream browser logging; the generator replaces only
that import with a fail-on-cycle diagnostic stub. It does not run browser modules.

## Native adaptation

`Sources/Snipper/JapaneseDeinflector.swift` adapts `language-transformer.js` to
Swift. `scripts/generate-japanese-deinflection.mjs` converts the Japanese descriptor
into 928 literal suffix/whole-word rules and produces 1,446 upstream test cases:

```sh
node scripts/generate-japanese-deinflection.mjs
swift test
```

Node is only needed to regenerate the checked-in JSON, not to build or run the app.
All rule helpers, condition hierarchies, dictionary-form masks, and rule order are
preserved. Swift keeps alternate explanation chains, collapses identical
text/conditions/reason states, checks rule cycles without logging input, indexes
rules by ending character, and limits work to 512 states / 16 steps / 48 characters.
Native database queries batch derived spellings and apply dictionary rule-tag
filtering before limiting results. Exact original matches win for each source
span; longer clicked spans are tested before shorter substrings.

Only Japanese algorithmic deinflection is integrated. Other languages, Yomitan
text preprocessors, and dictionary-provided `formOf` links are not implemented.
A dictionary's `rules` field must identify compatible parts of speech for derived
matches; entries without compatible tags remain available through exact lookup.

The native result presentation also references the visual hierarchy in upstream
`ext/css/display.css`: headword/reading separation, dictionary and definition-tag
badges, and grouped senses. No upstream CSS/HTML is bundled or executed; grouping,
hanging indents, emphasis, and nested lists use native Swift/AppKit attributed text.

The generated rules and fixtures are GPL-covered derivatives, not independently
created data. No third-party dictionary definitions or private ZIPs are included.
