# Unicode 17.0.0 source data

These are the Unicode Consortium's archived Unicode Character Database files
for **17.0.0**. This library version is explicit; it is not a claim to use the
latest Unicode release.

Each `.txt.gz` contains the original bytes from the corresponding official UCD
URL. Compression uses gzip with modification time zero. `manifest.json` records
each source URL, original length, original SHA-256, compressed SHA-256 and the
license checksum. [LICENSE.txt](LICENSE.txt) contains Unicode License V3.

```sh
timeout --kill-after=2s 100s python3 tools/unicode17/verify_data.py
```

Run the command from the repository root. It checks the committed source and
license bytes without accessing the network. The official source directory is
[the archived UCD 17.0.0 release](https://www.unicode.org/Public/17.0.0/ucd/).

| Source | Use |
| --- | --- |
| `UnicodeData`, `DerivedCoreProperties`, `PropList` | Categories, combining classes, character and identifier properties |
| `CaseFolding`, `SpecialCasing` | Versioned case mapping data; each implemented API documents its precise casing policy |
| `DerivedNormalizationProps`, `CompositionExclusions` | Normalization and composition tables |
| `NormalizationTest` | Official normalization conformance corpus |
| `auxiliary/GraphemeBreakProperty`, `emoji/emoji-data`, `DerivedCoreProperties` | Extended grapheme boundary properties, pictographs and Indic conjunct classes |
| `auxiliary/GraphemeBreakTest` | Official extended grapheme conformance corpus |
| `auxiliary/WordBreakProperty`, `emoji/emoji-data` | Default word boundary properties and pictographs |
| `auxiliary/WordBreakTest` | Official default word boundary conformance corpus |

Scripts in `tools/unicode17` generate committed Lanius data tables from these
sources. Python is used for data generation and tests. Library lookups,
normalization and segmentation execute as Lanius; deployed programs do not
read these archives or invoke a Python, ICU or operating-system Unicode API.
