# Additional Unicode 17 terminal-width inputs

The terminal generator uses the Unicode 17 files already recorded in this directory's manifest: UnicodeData, DerivedCoreProperties, PropList, GraphemeBreakProperty, and emoji-data. The following additional official files were retrieved on 2026-10-23 and stored as deterministic gzip (`mtime = 0`). Hashes cover the uncompressed UTF-8 bytes.

| Stored file | Official source | SHA-256 |
| --- | --- | --- |
| `terminal-EastAsianWidth.txt.gz` | https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt | `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33` |
| `terminal-emoji-variation-sequences.txt.gz` | https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-variation-sequences.txt | `bb3d09ef03f206012c7532dd52dc0a21c9efddba0135ea4cf0d9201b8b9bba7e` |

These files carry Unicode's copyright and Unicode License v3, available in `LICENSE.txt`. `tools/unicode17/generate_terminal.py` only transforms static data. The runtime width policy is implemented in `extended/ext/terminal.lani` and documented in `docs/extended-terminal.md`.
