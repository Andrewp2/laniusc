# Library compiler and runtime dependencies

This list records boundaries encountered while building the libraries. A row
does not mean unrelated library work is blocked.

| Dependency | Evidence | Affected APIs | Status |
| --- | --- | --- | --- |
| Nested match with a wildcard arm | `tests/fixtures/stdlib_foundation/repro_nested_error_match.lani`: x86 compilation reports LNC0005 at `false` inside the inner wildcard arm on base `441e66f9` | Direct nested matching of `Result<_, Error>` | Reproduced 2026-10-22. A separately typed error-matching helper compiles and executes; String tests use helpers. |
| Slice and string length access | Language symbols contain data-pointer and slice-stride intrinsics but no length projection; existing `repro_string_length.lani` is a known gap | Count-free slice APIs, construction from `str`, borrowed text views | Needs an explicit checked projection; no pointer reinterpretation or NUL scan substitutes for it. |
| Immutable views and ownership | Slices are writable; container handles copy and destruction is explicit | Safe borrowed String bytes, automatic destruction, deep-owned containers | Public lifetime and read-only conventions are documented; not compiler-enforced. |
| Complete host services | `std::net` and `std::thread` advertise unavailable bindings | Sockets, threads, protocols and concurrent utilities | Runtime implementation remains. |

## Build setup

Use an absolute `CARGO_TARGET_DIR`. A relative value can put shader artifacts
under the shader crate while the compiler reads relative to its invocation
directory. The initial build reproduced this as LNC0057 during lexer
initialization. Rebuilding with an absolute target directory fixed the artifact
location without changing compiler source.

The library execution gate is documented in [stdlib-string.md](stdlib-string.md).
Compiler reproductions are separate from executable support claims.
