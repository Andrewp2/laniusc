# Checked nested aggregate callee results

These diagnostic-only controls were introduced while investigating
`tests/fixtures/stdlib_foundation/clone_values/nested.lani`. The production
entry initially failed before ELF emission with LNC0017, "x86 callee function
lost its checked aggregate result layout", at its imported generic clone
consumer. The first target LIR opcode was 21. The historical parent log is
`target/stdlib-work/clone-values-composition-first.log`.

Every control transfers the same nested
`Option<Result<Pair<String,Vec<i32>>,String>>` value and returns an outer
`Result` whose error is a separate nested generic enum graph. All error enums
are inhabited. No control imports `core::clone_values`, so none introduces
its empty `Infallible` enum. `Transfer<T,E>` deliberately consumes its source;
it is not an identity implementation of the independent-owner TryClone law.
The returned value is the one active owner and is released once.

| Entry | Boundary |
| --- | --- |
| `concrete.lani` | Concrete local function returns the complete aggregate type |
| `imported_plain.lani` | Imported generic function returns `Ok(source)` directly |
| `local_trait.lani` | Local generic function forwards a checked trait result |
| `imported_trait.lani` | Imported generic function forwards the same checked trait result |

Each entry covers both active variants of the inner Result. It asserts binary
String bytes including NUL and UTF-8, signed integer extremes, and variant
identity after return. The focused Rust driver
`tests/compiler_structural_clone_result_execution.rs` uses the unchanged strict
ELF checker, a bounded native subprocess and an exact address/request-length
mapping ledger for the two original Strings and one Vec.

## Recorded results and scope

On 2026-10-25, all four controls passed serialized compilation and native
execution in 7.95 seconds, including the strict ELF check and exact owner
mapping ledger. The receipt is
`target/stdlib-work/structural-clone-result-controls.log`.

After the known-empty-enum native-width producer correction, the original
`clone_values` gate also passed all five groups in 19.37 seconds, including
the original nested clone, exact scalar bits, minimal bounds, protocol
rejections, 18 callback cases, 14 owned errors and all 45 reached allocation
failures. Its receipt is `target/stdlib-work/clone-values-native-current.log`.
The true empty `Infallible` enum and the original assertions were retained.

The earlier LNC0017 was a downstream symptom of that producer-width issue.
No separate callee-result replay or x86 return-layout repair was needed. The
diagnostic text alone does not establish a particular callee width, and these
inhabited controls are not reproductions of the empty-enum failure.

These results cover the stated finite source shapes on native Linux x86_64:
the GPU compiler emits CPU programs. They do not establish arbitrary generic
replay, all aggregate layouts or other targets. This reduction adds only its
fixtures and driver; it changes no production library, compiler, IR, proof,
existing assertion or shared checker. The producer correction is separate
from this reduction, and no per-type fallback or validation bypass was added.
