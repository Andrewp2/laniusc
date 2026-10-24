# Unicode 17 sentence data

These sentence-family files are archived official Unicode Consortium UCD 17.0.0
inputs. `sentences-manifest.json` records original URLs, byte counts, SHA-256
hashes of the originals, and SHA-256 hashes of the checked-in gzip files. Gzip
uses level 9 and mtime zero. Existing `LICENSE.txt` is Unicode License v3 and
applies to the data and derived property table.

- `sentences-SentenceBreakProperty.txt.gz`:
  https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakProperty.txt
- `sentences-SentenceBreakTest.txt.gz`:
  https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakTest.txt
- Algorithm: UAX #29 revision 47, Unicode 17.0.0:
  https://www.unicode.org/reports/tr29/tr29-47.html#Sentence_Boundaries

`tools/generate_unicode_sentences.py` verifies both compressed and original
hashes and transforms only `Sentence_Break` properties into sorted disjoint
Lanius ranges. It does not consult a host Unicode database. The complete 512
official sentence boundary vectors remain independent test input; they are
not used to generate production behavior.

```sh
python3 tools/generate_unicode_sentences.py
python3 tools/generate_unicode_sentences.py --check
```
