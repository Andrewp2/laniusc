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

The complete scope and dependency order are
tracked in the [library roadmap](../docs/library-roadmap.md). Package publishing,
other formats and protocols, and additional targets remain separate work.
