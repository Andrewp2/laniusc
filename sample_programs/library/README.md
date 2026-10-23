# Library applications

These applications use scenario-based execution tests instead of the top-level
sample runner's fixed argument and text-output fixture.

| Application | Execution evidence | Commands and contracts |
| --- | --- | --- |
| `path_join.lani` | `tests/path_execution.rs`, x86_64 Linux; raw-byte/NUL output, options, allocation and write failures | [Byte paths and owned buffers](../../docs/stdlib-paths.md#application) |
| `path_filter.lani` | `tests/extended_path_filter_execution.rs`, x86_64 Linux; byte/NUL records, recursive globs, limits, buffer reuse and allocation/I/O failures | [Byte-glob filtering commands and contracts](../../docs/extended-glob.md#path-filter-application) |
| `uri_component.lani` | `tests/extended_uri_component_execution.rs`, x86_64 Linux; borrowed components, raw percent-decoded bytes, absence, limits and allocation/output failures | [URI component extraction](../../docs/extended-uri-component.md) |
| `uri_resolve.lani` | `tests/extended_uri_resolve_program_execution.rs`, x86_64 Linux; strict reference resolution, global options, limits, prevalidation and allocation/output failures | [URI resolution program](../../docs/extended-uri-resolve-program.md) |
| `compress_bytes.lani` | `tests/extended_compress_bytes_execution.rs`, x86_64 Linux; raw/zlib/gzip interoperability, exact limits, checksums, diagnostics and allocation/I/O failures | [Binary compression application](../../docs/extended-compress-bytes.md) |
| `tar_bytes.lani` | `tests/extended_tar_bytes_execution.rs`, x86_64 Linux; ustar/gzip creation, binary members, NUL listings, complete archive validation and allocation/I/O failures | [Binary TAR application](../../docs/extended-tar-bytes.md) |
| `zip_bytes.lani` | `tests/extended_zip_bytes_execution.rs`, x86_64 Linux; stored/DEFLATE creation, NUL listings, selected reads, payload verification and allocation/I/O failures | [Binary ZIP application](../../docs/extended-zip-bytes.md) |
| `zip_manifest.lani` | `tests/extended_zip_manifest_execution.rs`, x86_64 Linux; all-payload ZIP checks, exact binary names, CBOR manifests, limits and allocation/I/O failures | [Checked ZIP manifest in CBOR](../../docs/extended-zip-manifest.md) |
| `arena_words.lani` | `tests/stdlib_arena_words_execution.rs`, x86_64 Linux; streamed binary word counts, stable typed arena keys, ordered maps, exact limits and allocation/I/O failures | [Arena-backed word counting](../../docs/stdlib-arena-words.md) |
| `address_filter.lani` | `tests/stdlib_address_filter_execution.rs`, x86_64 Linux; numeric addresses/sockets/CIDRs, canonical output, prefix selection and allocation/I/O failures | [Address filter](../../docs/stdlib-address-filter.md) |
| `bigcalc.lani` | `tests/extended_bigcalc_execution.rs`, x86_64 Linux; arbitrary precision arithmetic, radices, limits and allocation/I/O failures | [Integer calculator](../../docs/extended-bigcalc.md) |
| `json_check.lani` | `tests/extended_json_check_execution.rs`, x86_64 Linux; schema validation, exact numbers, limits and allocation/I/O failures | [JSON validation program](../../docs/extended-json-check.md) |
| `float_normalize.lani` | `tests/stdlib_float_format_execution.rs`, x86_64 Linux; conversion, rounding, limits and stream failure checks | [Floating number normalizer](../../docs/stdlib-float-normalize.md) |
| `text_normalize.lani` | `tests/extended_text_normalize_execution.rs`, x86_64 Linux; Unicode normalization, scalar/grapheme counts and allocation/I/O failures | [Unicode normalization program](../../docs/extended-text-normalize.md) |
| `text_case.lani` | `tests/extended_text_case_execution.rs`, x86_64 Linux; contextual casing, locales, limits and allocation/I/O failures | [Unicode casing program](../../docs/extended-text-case.md) |
| `text_grep.lani` | `tests/extended_text_grep_execution.rs`, x86_64 Linux; streamed UTF-8 regex matching, counts, numbering and allocation/I/O failures | [Regex search program](../../docs/extended-text-grep.md) |
| `toml_normalize.lani` | `tests/extended_toml_normalize_execution.rs`, x86_64 Linux; typed TOML normalization, quiet checking and allocation/I/O failures | [TOML normalizer](../../docs/extended-toml-normalize.md) |
| `primes.lani` | `tests/stdlib_primes_execution.rs`, x86_64 Linux; owned bitsets, independent small listings, twenty-million bound and allocation/write failures | [Prime sieve](../../docs/stdlib-primes.md) |
| `decimal_ledger.lani` | `tests/extended_decimal_ledger_execution.rs`, x86_64 Linux; exact decimal CSV calculations, rounding, limits and allocation/I/O failures | [Decimal ledger](../../docs/extended-decimal-ledger.md) |
| `data_analyze.lani` | `tests/extended_data_analyze_execution.rs`, x86_64 Linux; numerical CSV summaries, QR regression and allocation/I/O failures | [CSV analysis and regression](../../docs/extended-data-analyze.md) |
| `expr_calc.lani` | `tests/extended_expr_calc_execution.rs`, x86_64 Linux; parser cursors, inline stacks, checked arithmetic, format strings and allocation/I/O failures | [Integer expression calculator](../../docs/extended-expr-calc.md) |
| `text_patch.lani` | `tests/extended_text_patch_execution.rs`, x86_64 Linux; minimal unified diffs, exact apply/check, byte preservation and allocation/file/I/O failures | [File comparison and patch application](../../docs/extended-text-patch.md) |

Compile these applications with both `--stdlib-root stdlib` and `--source-root extended`.
The library implementations are Lanius; the Rust test harness supplies inputs and
checks the resulting native executable.
