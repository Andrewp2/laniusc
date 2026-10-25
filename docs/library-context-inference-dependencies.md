# Compiler dependencies from owning cursors and CSV

The owning hash cursor, CSV and regex application work exposed three compiler inference
limitations. Their library implementations and accepted fixtures use explicit
declared result types. The original expressions remain reduced reproductions;
the compiler has not been changed to accept them.

All three inference pairs were compiled with the current GPU compiler on Linux x86_64 on
2026-10-25. Each unannotated source failed during type checking. Each annotated
control compiled and its generated native executable exited successfully.
These are execution controls, not type-check-only acceptance.

## Nested hash insertion result

The [reproduction and full-context history](../tests/fixtures/stdlib_compiler_state/hash_insert_context/README.md)
retain a nested insertion/unwrap argument with the exact signed value
`-9223372036854775807`. The primitive-key reduction reports `LNC0006`
(`AssignMismatch`) at the nested `.unwrap()`. Explicitly binding the `i64`
value and exact `Result<Option<Entry<i32,i64>>,hash_map::Error>` result makes
the control execute, including its returned previous entry and stored bit
pattern `0x8000000000000001`.

| Source | Compile | Native execution | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `primitive_nested.lani` | `LNC0006` | No executable | `hash-context-nested.log` |
| `primitive_typed_control.lani` | Success | Exit 0 | `hash-context-typed.log`, `hash-context-typed-native.log` |

The accepted [owning hash model](stdlib-owning-hash.md) uses the same value and
passes all 5,368 cases with explicit locals. This does not isolate whether
the literal context, intermediate Result context, or their interaction causes
the original failure. The primitive reduction establishes that a custom key
is not required to reproduce the distinction.

## Generic byte-writer return

The [unannotated source](../tests/fixtures/extended/csv_write/generic_inference_untyped.lani)
calls `writer.write(...)` inside a function bounded by `W: core::io::Write`,
then calls `.is_err()` on its inferred local. It reports `LNC0027`
(`CallMismatch`). The [typed control](../tests/fixtures/extended/csv_write/generic_inference_typed.lani)
declares that local as the trait's exact
`core::result::Result<i32,core::io::Error>`. It executes and verifies the
byte written to the borrowed destination.

| Source | Compile | Native execution | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `generic_inference_untyped.lani` | `LNC0027` | No executable | `io-context-untyped.log` |
| `generic_inference_typed.lani` | Success | Exit 0 | `io-context-typed.log`, `io-context-typed-native.log` |

The [CSV writer](extended-csv-write.md) and
[column rewrite program](extended-csv-rewrite.md) declare I/O result locals
explicitly. Their runtime acceptance remains recorded in their own guides.
An analogous unannotated generic `flush()` result failed in the application;
the minimal pair above establishes the simpler Write case.

## Nested generic slice construction

The regex CLI originally constructed a raw slice inside a generic View factory
and unwrapped it directly in a function returning `View<u8>`. The
[reduction](../tests/fixtures/extended/regex_text/compiler_boundary/nested_view_untyped.lani)
reports `LNC0047` (`GenericInstantiationBoundary`, detail 3). The
[control](../tests/fixtures/extended/regex_text/compiler_boundary/nested_view_typed.lani)
declares an intermediate `[u8]` local and explicit `<u8>` arguments. It
compiles and executes, verifying the same byte through the returned View.

| Source | Compile | Native execution | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `nested_view_untyped.lani` | `LNC0047` | No executable | `regex-nested-view-untyped.log` |
| `nested_view_typed.lani` | Success | Exit 0 | `regex-nested-view-typed.log`, `regex-nested-view-typed-native.log` |

The [accepted regex CLI](extended-regex-text.md) uses that explicit form.
The pair changes both intermediate typing and explicit type arguments, so it
does not establish which annotation alone is sufficient. No compiler source
changed.

## Nested enum/literal pattern lowering

The writer's original failure-prefix fixture also failed during GPU lowering,
with `LNC0057` and flags `0x400`. A
[reduced classifier](../tests/fixtures/extended/csv_write/nested_literal_lowering.lani)
reproduces that failure: an outer `Cause::Io(error)` arm contains a nested
match with `core::io::Error::Host(7)` as a payload pattern. The
[control](../tests/fixtures/extended/csv_write/bound_payload_control.lani)
extracts the inner match into a helper, binds `Host(code)` and checks
`code == 7`. It compiles and executes, distinguishing Host(7), Host(8) and
the outer call-limit case.

| Source | Compile | Native execution | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `nested_literal_lowering.lani` | `LNC0057`, flags `0x400` | No executable | `csv-nested-literal.log` |
| `bound_payload_control.lani` | Success | Exit 0 | `csv-bound-payload.log`, `csv-bound-payload-native.log` |

This pair changes both match nesting and literal-payload handling; it does not
isolate which causes the lowering failure. The exact original writer fixture
is retained as
[`contracts_lowering_original.lani`](../tests/fixtures/extended/csv_write/contracts_lowering_original.lani).
Its active equivalent retains every prefix, boundary and budget assertion and
passes with the helper/bound-payload classifier. No compiler source changed.

## Reproduce

From the repository root, compile one source from an inference pair:

```sh
timeout --kill-after=2s 20s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib SOURCE.lani -o /tmp/context-control
```

For a successful control, make the output executable if necessary and run it
with a two-second deadline. The inference pairs do not need the extended source
root. The enum-lowering pair additionally needs `--source-root extended`.
Retain compiler diagnostics separately from native exit status; a rejected
source cannot establish runtime behavior.

These fixtures are outside ordinary library acceptance drivers. Future compiler
fixes should make the original expressions execute with the same assertions;
their current rejection is a dependency to remove, not a desired language rule.
