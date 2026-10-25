# Unicode 17 line-breaking sources

The `unicode-lines-*.gz` files retain the original Unicode 17.0.0 property data,
complete official line-break conformance corpus, associated rule chart, and
UAX #14 revision 55 specification. `unicode-lines-manifest.json` records exact
source URLs, uncompressed byte counts, and SHA-256 hashes. Gzip timestamps are
zero; the generator verifies every hash before generating or checking output.

Unicode data and documentation copyright © 1991–2025 Unicode, Inc. The original
notices are retained in the files. Redistribution is under the retained
[Unicode License v3](LICENSE.txt). No host Unicode database contributes data.

`tools/generate_unicode_lines.py` generates only static property ranges, including
default LB1 resolution, from the pinned sources. The complete ordered algorithm
is implemented separately in Lanius. The specification and test corpus do not
generate algorithm code or expected results: the native test reads the official
opportunities directly from the corpus.
