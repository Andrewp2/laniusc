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

The complete scope and dependency order are
tracked in the [library roadmap](../docs/library-roadmap.md). Package publishing,
other formats and protocols, and additional targets remain separate work.
