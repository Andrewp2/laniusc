# Library applications

These applications use scenario-based execution tests instead of the top-level
sample runner's fixed argument and text-output fixture.

| Application | Execution evidence | Commands and contracts |
| --- | --- | --- |
| `path_join.lani` | `tests/path_execution.rs`, x86_64 Linux; raw-byte/NUL output, options, allocation and write failures | [Byte paths and owned buffers](../../docs/stdlib-paths.md#application) |
| `path_filter.lani` | `tests/extended_path_filter_execution.rs`, x86_64 Linux; byte/NUL records, recursive globs, limits, buffer reuse and allocation/I/O failures | [Byte-glob filtering commands and contracts](../../docs/extended-glob.md#path-filter-application) |
| `uri_component.lani` | `tests/extended_uri_component_execution.rs`, x86_64 Linux; borrowed components, raw percent-decoded bytes, absence, limits and allocation/output failures | [URI component extraction](../../docs/extended-uri-component.md) |

Compile these applications with both `--stdlib-root stdlib` and `--source-root extended`.
The library implementations are Lanius; the Rust test harness supplies inputs and
checks the resulting native executable.
