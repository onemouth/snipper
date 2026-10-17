# Snipper / Yomitan licensing notice

Snipper is free software licensed under the GNU General Public License, version 3
or (at your option) any later version (GPL-3.0-or-later).

The Japanese deinflection rules and native transformer adaptation incorporate work
from Yomitan (https://github.com/yomidevs/yomitan), revision
`e7334a96106a6c74e6fa75bd33a5ea1219d92712`.

Copyright (C) 2024–2026 Yomitan Authors (rules and transformer).
Copyright (C) 2023–2026 Yomitan Authors and 2020–2022 Yomichan Authors (test sources).
Copyright (C) 2026 Snipper contributors (native adaptation and integration).

Modifications: generated native JSON rules and fixtures; Swift transformer with
bounded search, cycle checks, duplicate-state removal, and no source-text logging;
SQLite dictionary matching and AppKit/SwiftUI presentation. The unmodified upstream
snapshots and regeneration instructions are in `ThirdParty/Yomitan/` in the source.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

A copy of the GNU GPL v3 is included as `LICENSE` beside this notice in the app's
Contents/Resources directory and at the root of the source distribution. See also
https://www.gnu.org/licenses/.

Project: https://github.com/onemouth/snipper
When distributing binaries, provide the corresponding source for that exact build
(including modifications and build scripts), or another GPL-compliant source
provision mechanism. A project URL alone is not a substitute for that obligation.
Imported dictionaries are separate user-supplied content and retain their own
licenses; this notice does not grant rights to redistribute them.
