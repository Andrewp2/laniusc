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
| `image_tool.lani` | `tests/extended_image_tool_execution.rs`, x86_64 Linux; PNG pixel models, crop/rotate/flip order, caps, staged output and allocation/I/O failures | [PNG inspection and transformation](../../docs/extended-image-tool.md) |
| `wave_tool.lani` | `tests/extended_wave_tool_execution.rs`, x86_64 Linux; WAVE conversion, gain, mono, metrics and allocation/I/O failures | [WAVE processing](../../docs/extended-wave-tool.md) |
| `shape_hull.lani` | `tests/extended_shape_hull_execution.rs`, x86_64 Linux; CSV coordinates, exact hull/area, limits and allocation/I/O failures | [CSV convex hull](../../docs/extended-shape-hull.md) |
| `http_message.lani` | `tests/extended_http_message_execution.rs`, x86_64 Linux; offline HTTP framing/body inspection, chunking, limits and allocation/file/I/O failures | [HTTP message processing](../../docs/extended-http-message.md) |
| `http_fetch.lani` | `tests/extended_http_client_execution.rs`, x86_64 Linux; numeric IPv4/IPv6 cleartext exchange, binary bodies, informational responses, early final replies, bounded work/deadlines and cleanup failures | [Connected HTTP client](../../docs/extended-http-client.md) |
| `csv_table.lani` | `tests/extended_csv_table_execution.rs`, x86_64 Linux; Unicode cells, alignment, width policy, progress, limits and allocation/I/O failures | [CSV tables](../../docs/extended-csv-table.md) |
| `library_tests.lani` | `tests/stdlib_development_execution.rs`, x86_64 Linux; explicit suites, checks, properties and native measurement | [Lanius test workflow](../../docs/stdlib-development.md) |
| `dns_message.lani` | `tests/extended_dns_execution.rs`, x86_64 Linux; binary query writing, packet inspection, compression/RDATA limits and allocation/I/O faults | [Offline DNS messages](../../docs/extended-dns.md) |
| `websocket_wire.lani` | `tests/extended_websocket_wire_execution.rs`, x86_64 Linux; handshakes, binary/fragmented messages, close state, limits and allocation/I/O faults | [Offline WebSocket processing](../../docs/extended-websocket.md) |
| `kv_tool.lani` | `tests/extended_kv_execution.rs`, x86_64 Linux; checked snapshot storage, model/corruption cases and native replacement/fault cleanup | [Key-value snapshots and file replacement](../../docs/extended-kv.md) |
| `wave_spectrum.lani` | `tests/extended_wave_spectrum_execution.rs`, x86_64 Linux; WAVE/FIR/window/FFT CSV, numerical models and allocation/I/O faults | [WAVE spectrum](../../docs/extended-wave-spectrum.md) |
| `timezone_tool.lani` | `tests/extended_timezone_tool_execution.rs`, x86_64 Linux; TZif inspection, instant/local conversion, ambiguity, limits and allocation/I/O faults | [Time-zone queries](../../docs/extended-timezone.md) |
| `text_sentences.lani` | `tests/extended_text_sentences_execution.rs`, x86_64 Linux; official sentence vectors, exact CSV/framed output, limits and allocation/I/O faults | [Sentence segmentation](../../docs/extended-text-sentences.md) |
| `text_wrap.lani` | `tests/extended_text_wrap_execution.rs`, x86_64 Linux; Unicode boundaries, independent cell-fitting models, limits and allocation/I/O faults | [Text wrapping](../../docs/extended-text-wrap.md) |
| `tcp_exchange.lani` | `tests/stdlib_tcp_exchange_execution.rs`, x86_64 Linux; independent IPv4/IPv6 peers, empty/binary/1 MiB data, deadlines and allocation/I/O faults | [Binary TCP exchange](../../docs/stdlib-tcp-exchange.md) |
| `directory_report.lani` | `tests/stdlib_directory_execution.rs`, x86_64 Linux; raw byte names, OS metadata model, depth/filter/resource limits and descriptor/allocation/I/O cleanup | [Directory reporting](../../docs/stdlib-directory.md) |
| `dns_query.lani` | `tests/extended_dns_client_execution.rs`, x86_64 Linux; IPv4/IPv6 peers, UDP/TCP correlation/fallback, exact framing, fixed deadlines and allocation/host-error cleanup | [DNS transport](../../docs/extended-dns-client.md) |
| `run_command.lani` | `tests/stdlib_command_execution.rs`, x86_64 Linux 5.11+; argv/environment/cwd, redirected files, child status, startup ambiguity, syscall/allocation failures and reaping | [Command runner](../../docs/stdlib-command.md) |
| `capture_command.lani` | `tests/stdlib_command_capture_execution.rs`, x86_64 Linux 5.11+; concurrent binary stdin/stdout/stderr, exact caps, child status, deadlines, persistent interruptions and allocation/FD/I/O cleanup | [Bounded command capture](../../docs/stdlib-command-capture.md) |
| `settings_inspect.lani` | `tests/extended_settings_execution.rs`, x86_64 Linux; JSON/TOML/environment overlays, exact typed values, provenance, limits and allocation/I/O cleanup | [Settings inspection](../../docs/extended-settings.md) |
| `sample_distribution.lani` | `tests/extended_sample_distribution_execution.rs`, x86_64 Linux; seeded continuous samples, CSV models, resource and allocation/I/O failures | [Distribution sampling](../../docs/extended-sample-distribution.md) |
| `sample_counts.lani` | `tests/extended_sample_counts_execution.rs`, x86_64 Linux; seeded discrete counts, independent predictions/moments/exceedances, resource and allocation/I/O failures | [Count simulation](../../docs/extended-sample-counts.md) |

Compile these applications with both `--stdlib-root stdlib` and `--source-root extended`.
The library implementations are Lanius; the Rust test harness supplies inputs and
checks the resulting native executable.
