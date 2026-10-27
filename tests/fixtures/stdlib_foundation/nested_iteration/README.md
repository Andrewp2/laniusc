# Public scan and nested iteration gates

Status: both public smokes compiled and executed successfully through the real
CLI; all three model/payload-shape Rust gates also passed native execution.
These fixtures import the actual `core::iter` public adapters; caller-defined
iterators, callbacks and retirement policies exercise ordinary cross-module
trait dispatch. No local adapter or production implementation is substituted.

The first admission checkpoint is deliberately split:

- `scan_smoke.lani`: lazy Scan/TryScan construction, initially empty sources,
  caller-owned running state, terminating None consuming its boundary, one
  transferred wide error, fused later calls, and direct source resumption.
- `nested_smoke.lani`: lazy TryFlatten/TryFlatMap construction, empty inner
  retirement before another outer acquisition, exact initial effects, active
  finish refusal, retirement failure retaining the updated inner, one error and
  fused calls, explicit take/retry, fresh shared-outer continuation, no-effect
  early finish, empty outer exhaustion, and mapper failure with outer remainder.

The nested smoke's inner is a caller-defined allocation-free cursor. It proves
no native backing retirement, owning collection behavior, resource balance,
allocator failure handling, or real-program behavior. Those need their own
executable gates. The accepted target is native Linux x86_64 CPU execution of
programs emitted by the GPU compiler. No user-program GPU execution or other
host support is established here.

## Accepted public admission

Both smoke commands emitted native Linux x86_64 ELFs which exited zero. These
are direct CLI receipts, not Rust integration-test execution. The compiler CLI
SHA256 was `1c2718d4c17b7da613f999412bff037eef3770cb755a74e35e7eebd2cfc202f6`
and the accepted `core::iter` SHA256 was
`7256a39462db691ece403a6d9a409947f7fafa7919783be474d510f1bf63ce3c`.

| Fixture | Compile log in `target/stdlib-work/` | Native log in the same directory |
| --- | --- | --- |
| `scan_smoke.lani` | `nested-public-scan-smoke-visibility-retry.log` | `nested-public-scan-smoke-native-first.log` |
| `nested_smoke.lani` | `nested-public-nested-smoke-first.log` | `nested-public-nested-smoke-native-first.log` |

The scan fixture SHA256 is
`b8e5b0a48e9c688898c4cbc587bbd24f830be78526fead4d77b8b605b687ab19`;
its ELF is `dcb2c42bcd4c3d19c79f356657e07665fdb1c2e073b7eb1b40dd5541913c4452`.
The nested fixture SHA256 is
`89ea4e7f97c9e184703c2e39c5f632df863b9a3a2f0af662895ebae8631964ac`;
its ELF is `bd055701c614b5101f4c46f28867ebd6ea5aaa60954f8d55f5cd0f2021ff708e`.
An earlier whole-module admission failed before native emission with LNC0021:
the private identity type's implementation of public Mapper required `pub impl`.
The production author added that visibility keyword; fixture assertions and
implementation bodies were unchanged before the accepted retry.

## Accepted model and payload gates

All three tests passed in
`target/stdlib-work/nested-public-models-shapes-first.log`, using
`stdlib_nested_iteration_execution-23eb12057e9b34ab`. The combined invocation
took 9.31 seconds; this is not a per-test timing. The two Rust smoke
registrations were filtered out because their direct CLI/native receipts above
already established their execution. Acceptance therefore consists of three
Rust tests and two direct CLI programs, not an all-five Rust test run.

| Accepted Rust filter | Executed scope |
| --- | --- |
| `public_nested_actions_match_independent_shared_sequence_models` | 360 binary command scenarios |
| `public_scan_actions_match_independent_shared_sequence_models` | 672 binary command scenarios |
| `public_nested_generic_payloads_strided_views_and_zero_sized_items_execute` | Native value/count assertions in `shapes.lani` |

- `nested_model.lani` and `model.py nested`: 360 binary commands compare every
  action snapshot and full callback/source/retirement trace against ordinary
  Python row generators and finite deque remainders. Commands cover empty
  inners, retirement and mapping failures, two distinct adapters sharing an
  outer, interleaved traversal, active finish refusal, take-once, manual
  recovered traversal/retirement, and fresh-adapter resumption. The reference
  does not reproduce production Option move-out/reinstall storage. Final
  borrowed-only cursor cleanup follows the emitted observations and is not a
  native-owner evidence gate.
- `scan_model.lani` and `model.py scan`: 672 commands compare independently
  latched adapters over a shared consumed sequence, direct source consumption,
  fresh construction, caller-owned running state, stop/error priority and
  exact effects. A terminating None consumes its input; an error is one item.
- `shapes.lani`: nested Option/Result/array items and errors, full-width unsigned
  and signed fields, nonzero-start native-stride views, records, and zero-sized
  items. Caller generic policies own no backing. Assertions exercise actual
  values and callback/retirement counts rather than type-checking alone.

The first Rust driver build failed with harness E0308: the timeout helper
required `&mut Command`, while the smoke launcher passed a Command value. Root
added that borrow only; Lanius fixtures, models and assertions were unchanged.
The corrected build passed in 1.39 seconds in
`target/stdlib-work/nested-semantic-app-drivers-borrow-retry.log`, before the
three accepted native gates. The accepted driver SHA256 is
`0dce26080aaa8ff35f818b3d321624974d45a64e79e8337bd010c47a704d64c1`.

| Accepted model/payload source | SHA256 |
| --- | --- |
| `nested_model.lani` | `907fe5d545cf323d2df9b40e449e70114b6917d53a927ec8ec1716c21b061c91` |
| `scan_model.lani` | `bd4839f54c06e6d4908045e633d25ca26add9b0fb1ff2fa9edc92e36ec1b211c` |
| `shapes.lani` | `c5899e7e4441bcd04c5c461aad629af4de0fd93b98ed7b322808a3c508d592fc` |
| `model.py` | `8f42d07d063649423ebde0a392474cb1bb0c9172b0ba6806856f0c1011f7d720` |

Python-only model controls separately pass 18 assertions, including hand-checked empty
retirement order, finish preservation, updated-inner recovery, one-error
fusion, mapping rejection, shared scan state, and strict binary framing/content
mutations. These controls execute no compiler or native Lanius.

The driver also registers each accepted smoke for future regression runs;
its registration is not a second acceptance receipt. It preserves the shared
strict x86 ELF validator. Each native smoke has a five-second deadline; model
processes have a 30-second Python deadline and a 45-second outer deadline.

Strict native-owner/fault campaigns are separate from these semantic tests.
Their first gate stopped at a parser failure before native execution; it has no
owner-acceptance receipt here. These results do not establish native backing
release, pre-exit mapping balance, allocator failure behavior, or the separate
`flatten_sum` application's acceptance.

```sh
python3 -B tests/fixtures/stdlib_foundation/nested_iteration/model.py controls
```

Root serializes compiler/native commands. This author performed no compiler or
native execution. Every command must remain below two minutes.
