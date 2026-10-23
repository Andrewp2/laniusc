# Extended library

Optional libraries live under this source root and use the `ext` namespace.
They are implemented in Lanius and import the standard library through its
ordinary modules. Add this root only when an application needs an extended
module:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/csv_normalize.lani -o /tmp/csv-normalize
```

The compiler binary must already be built. Paths above are relative to the
repository root. An application imports the CSV module with `import ext::csv;`.

| Module | Working surface | Execution evidence |
| --- | --- | --- |
| [`ext::csv`](ext/csv.lani) | Incremental UTF-8 decoding, reusable packed records, whole tables, borrowed/copied fields and canonical encoding | x86_64 Linux; [contracts and tests](../docs/extended-csv.md) |
| [`ext::json`](ext/json.lani) | Parse/build owned documents, query nodes, encode compact JSON with exact number text | x86_64 Linux; [contracts and tests](../docs/extended-json.md) |
| [`ext::cli`](ext/cli.lani) | Borrowed raw-byte argument parser, short groups, exact long names, required/optional values and structured errors | x86_64 Linux; [contracts and tests](../docs/extended-cli.md) |
| [`ext::config`](ext/config.lani) | Owned strict JSON sources, bounded file loading, borrowed typed queries and explicit shallow precedence | x86_64 Linux; [contracts and tests](../docs/extended-config.md) |
| [`ext::log`](ext/log.lani) | Severity filters, borrowed typed records and atomic caller-buffer preparation of JSON log records | x86_64 Linux; [contracts, delivery and tests](../docs/extended-log.md) |
| [`ext::glob`](ext/glob.lani) | Compiled raw-byte patterns, ASCII classes/case rules, recursive components and bounded matches with caller scratch | x86_64 Linux matcher and path-filter application tests; [contracts and evidence](../docs/extended-glob.md) |
| [`ext::percent`](ext/percent.lani) | Checked raw-byte component percent encoding/decoding, caller buffers, in-place conversion and atomic errors | x86_64 Linux; [contracts and tests](../docs/extended-percent.md) |
| [`ext::uri`](ext/uri.lani) | Strict borrowed RFC 3986 URI-reference parsing, exact encoded component views, IPv4/IPv6/IPvFuture syntax and explicit limits | x86_64 Linux; [contracts and tests](../docs/extended-uri.md), [component application](../docs/extended-uri-component.md) |
| [`ext::uri_resolve`](ext/uri_resolve.lani) | Owned strict RFC 3986 resolution and recomposition, linear dot-segment removal, final-output limits and explicit allocation errors | x86_64 Linux; [contracts and tests](../docs/extended-uri-resolve.md), [resolution program](../docs/extended-uri-resolve-program.md) |
| [`ext::deflate`](ext/deflate.lani) | Allocation-free raw DEFLATE encoding with fixed Huffman LZ77, stored-block fallback, caller scratch and atomic output failures | x86_64 Linux; [contracts, tests and measurements](../docs/extended-deflate.md) |
| [`ext::inflate`](ext/inflate.lani) | Allocation-free raw DEFLATE decoding with stored/fixed/dynamic blocks, history limits and explicit prefix progress | x86_64 Linux; [contracts and tests](../docs/extended-inflate.md) |
| [`ext::compression`](ext/compression.lani) | Owned raw/zlib/gzip encoding and checked decoding, concatenated gzip, output limits and allocation cleanup | x86_64 Linux; [contracts and tests](../docs/extended-compression.md), [binary application](../docs/extended-compress-bytes.md) |
| [`ext::tar`](ext/tar.lani) | Borrowed POSIX ustar metadata/data and atomic caller-buffer multi-member writing, checked headers/padding/footer and raw byte paths | x86_64 Linux; [contracts and tests](../docs/extended-tar.md), [TAR/gzip application](../docs/extended-tar-bytes.md) |
| [`ext::zip`](ext/zip.lani) | Bounded classic single-disk ZIP metadata, checked stored/DEFLATE member extraction and deterministic owned multi-member writing | x86_64 Linux; [contracts and tests](../docs/extended-zip.md), [binary application](../docs/extended-zip-bytes.md) |
| [`ext::cbor`](ext/cbor.lani) | Allocation-free iterative CBOR wire events, full-width integers and float bits, definite/indefinite structures, strict text, caller scratch and atomic encoding | x86_64 Linux; [contracts and tests](../docs/extended-cbor.md), [checked ZIP manifest](../docs/extended-zip-manifest.md) |

The complete scope and dependency order are
tracked in the [library roadmap](../docs/library-roadmap.md). Package publishing,
other formats and protocols, and additional targets remain separate work.
