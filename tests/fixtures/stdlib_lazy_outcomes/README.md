# Lazy outcome direct gates

The fixtures call the real `core::option`, `core::result` and canonical
`core::function::{Mapper,Producer}` APIs. The contract is
[`library-lazy-outcomes-plan.md`](../../../docs/library-lazy-outcomes-plan.md).

## Scope

- `admission.lani` admits the new callback identity and argument-free Producer,
  generic method forwarding, compound values, full-width words and short
  circuits. The production source agent owns this fixture.
- `branches.lani` exercises all nineteen operations as both free functions and
  methods with both receiver variants. Each invocation checks the precise
  result and zero/one callback events, selected operand, unchanged source and
  complete unused log guards. Every unselected callback is armed to fail if
  invoked. Optional/result chains also return None/Err deliberately; predicates
  return both Booleans. Eager `map_or` fallback expressions emit an event before
  the selected mapper, independently witnessing that eager argument behavior
  remains distinct from lazy invocation. This is 112 direct new-API invocations,
  with assertions on each result and trace.
- `types.lani` forwards generic methods through bounded helpers and generic
  Mapper/Producer implementations. It checks multiword records, nonempty arrays,
  enum errors, nested `Option<bool>`, borrowed View offsets/stride/content and
  all source bytes; f32/f64 signed-zero, NaN-payload and infinity bits; stored
  false; and actual selected/skipped zero-sized payload/error/Producer paths.
  Custom callback and payload types require neither Clone nor Destroy.
- Eight Option and six Result negative fixtures isolate missing Mapper or
  Producer, wrong callback input/output, non-Boolean predicate output, wrong
  chain error/recovery value, and each callback of a dual-callback operation.
  All use receiver variants that would skip the invalid callback at runtime.
  Both free and method entry points occur. The driver requires `LNC0008` with a
  primary label on the marked call; arbitrary compilation failure cannot pass.

Positive fixtures compile to native Linux x86_64 ELF, pass the shared
in-function jump checks and execute under a full syscall trace. Only successful
exec and clean exit are admitted, with empty stdout/stderr; allocations and all
other host effects fail. Callback instrumentation uses caller-backed arrays.
Live nested ownership, selected callback allocation/failure and explicit
cleanup are exercised by the separate resource gates.

## Receipts

The initial registered tiny admission passed 1/1 in 4.96 s, with a separate
1.60 s harness build. Root's log is
`target/stdlib-work/lazy-outcomes-admission.log`. Tested production hashes were
function `a6e9f1ed`, Option `54629225`, Result `a0f37cd2`; fixture `4be3bfd0` and
initial one-selector driver `7aba70ca5be3f5cf97e3cb96b9c840d77f59b17c709d65b9c4939efdeea1ed26`.
The final driver below only adds the remaining selectors and rejection helper;
tiny compilation/execution helpers and its fixture are unchanged.

The four remaining registered groups passed together in 13.20 s, with the tiny
group filtered out, in `target/stdlib-work/lazy-outcomes-direct.log`:

| Group | Accepted scope |
| --- | --- |
| `lazy_outcomes_all_free_and_method_branches_execute_without_host_effects` | All nineteen operations, both forms and receiver variants; 112 checked new-API invocations and full no-host-effect trace |
| `lazy_outcomes_generic_compound_float_view_and_zero_size_values_execute` | Actual generic compound/view/float/zero-sized execution and full no-host-effect trace |
| `lazy_option_requires_exact_mapper_and_producer_bounds_on_skipped_branches` | Eight intended source-local capability rejections |
| `lazy_result_requires_matching_values_errors_and_both_callback_bounds` | Six intended source-local capability rejections |

All five direct groups are accepted across these two runs: three executable
positive groups and two rejection groups covering fourteen negative fixtures.
Independent direct-suite review passed at the frozen hashes below. The combined
harness/inventory build attempt also encountered a stale include of a previously
deleted Base64 fixture in a separate foundation target; the direct executable
was produced and used for the passing run above. That inventory build issue is
separate from these direct receipts and does not indicate a production failure.
Root corrected the stale inventory path; its rebuild is outside this direct-test
receipt.

No GPU-device execution, other platform/ABI or formal verification is claimed.
Shallow/manual lifetime contracts remain caller obligations; these fixtures do
not admit invalid descriptors or callback contract violations.

## Frozen source

| File | SHA-256 |
| --- | --- |
| `stdlib/core/function.lani` | `a6e9f1ed8b8f5a426e0443abceb1c39bce175c14e350c91433a454706d2790f5` |
| `stdlib/core/option.lani` | `54629225246fc9309eb54317026d1982f347e98974c1e465de5edadcc329290d` |
| `stdlib/core/result.lani` | `a0f37cd203c9103bdda5231c11aad61e7cd46692c561362d2c46faa92c5849c3` |
| `tests/stdlib_lazy_outcomes_execution.rs` | `479804f526c244eb0db389476d8d465b80390a46cfa2fa8ef8eacdcb74ee60bd` |
| `admission.lani` | `4be3bfd0b91efd518026d85cb35a7114ca3aa1215531c95afa58062651bc83a8` |
| `branches.lani` | `5c6c45a0938f558a95e4f75540d66f893d2df6e464feef6a2267f15f023666d1` |
| `types.lani` | `27a216744a250e298819037ec88bca3673f9735d37b002d3222ecb48fc375bd9` |

Root owns all compiler/native/Cargo gates, serialized under the library lock
with each outer command capped at 100 seconds. Source authors performed no
native runs for these direct fixtures.
