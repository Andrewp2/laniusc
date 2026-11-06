# Select a generic type despite a colliding module import

The [item-import contract](../../../../docs/language-ergonomics.md#item-imports)
says an explicit item import wins over module imports for the same name.
`core::slice` exports `View<T>`; `ext::weighted_graph` exports a nongeneric
`View`. Importing `core::slice::View` explicitly should select the slice type
for an unqualified `View<u8>` annotation.

The original `route_cost` application was rejected at its first short
`View<u8>` return annotation despite that explicit import. Receipt
`target/stdlib-work/route-cost-functional.log` records `LNC0007 unknown type`
at `route_cost.lani:31:36` in all three selected tests, before executable
launch. The application now uses qualified slice types. The small fixtures
below reproduce a source-pack type-check rejection and establish executing
controls; they do not identify its internal cause.

## Reduction and controls

| Fixture | Difference | Observed result |
| --- | --- | --- |
| `selected.lani` | Both module imports, explicit slice item import, short return type | Source-pack type-check rejection: LNC0007 at 6:31 |
| `qualified.lani` | Only the return type is qualified | Compiles and executes; exit 0, empty output |
| `no_collision.lani` | Only the weighted-graph import is removed | Compiles and executes; exit 0, empty output |

The 15-line selected fixture calls one function returning a borrowed slice
descriptor over `[7]`, then checks its start, length and selected byte. The
constructor and its local annotation are qualified in every fixture. This
keeps the only short `View` use at the function return annotation, where the
application failed. There are no graph algorithms, allocations or host I/O
in the source; the weighted-graph module is present only to supply its public
type name.

The existing [generic function-name collision fixture](../item_import_priority/README.md)
records a related import-priority observation without duplicating its
analysis here.

## Focused driver and current evidence

`tests/stdlib_weighted_view_import_execution.rs` uses the same native-link
source-pack API as `route_cost`, with the real `stdlib` and `extended` roots.
Successful compilation must be followed by execution on Linux x86_64 CPU,
exit status 0 and empty output. Each runtime invocation has a 15-second
timeout; compiler invocations use the shared GPU-codegen timeout and
serialized lane.

| Selector | Default state |
| --- | --- |
| `weighted_view_qualified_return_executes` | Active control |
| `weighted_view_item_import_without_collision_executes` | Active control |
| `weighted_view_item_import_beats_colliding_module_type` | Ignored diagnostic; run explicitly with `--ignored --exact` |

The selected test asserts the intended successful behavior and remains
ignored as a confirmed compiler dependency awaiting repair. No test requires
the documented import form to remain rejected. Remove its ignore once
successful behavior is accepted.

`target/stdlib-work/weighted-view-import-results.log` records an explicit
run including the ignored test: **2 passed, 1 failed in 7.90 seconds**. The
selected fixture rejects with `LNC0007 unknown type` at line 6, column 31,
before native emission or execution. Both otherwise-identical controls
compile through the GPU compiler and execute on Linux x86_64 CPU. The failed
intended-success test is diagnostic evidence, not an accepted behavior gate.

Qualifying `core::slice::View<u8>` is the executing workaround used by the
application. No compiler source, ABI or proof files were changed, and this
reduction establishes no general generic-type or graph-runtime failure.
