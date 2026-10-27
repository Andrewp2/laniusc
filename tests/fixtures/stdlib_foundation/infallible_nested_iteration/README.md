# Ordinary nested iteration semantic gates

Status: both model and shape Rust gates compiled and passed native execution.
The source writer's public smoke also passed separately through the real CLI.
The smoke was not rerun solely for a different launcher receipt.

## Exact executable receipts

`target/stdlib-work/infallible-nested-model-shapes-first.log` records a successful
Rust build in 1.76 seconds and both semantic tests passing together in 9.38
seconds. The latter is a combined invocation timing, not two separate test
durations. The binary was
`stdlib_infallible_nested_iteration_execution-091f5eb48bb47d23`.

| Accepted Rust filter | Native scope |
| --- | --- |
| `plain_nested_actions_match_existing_independent_sequence_oracle` | 24 binary command scenarios against the shared independent reference |
| `plain_nested_optional_wide_strides_zero_sized_and_composition_execute` | All plain item/value/stride/Unit/recovery/composition assertions in `shapes.lani` |

Accepted source SHA256 values:

| Source | SHA256 |
| --- | --- |
| `model.lani` | `a4e32b7c0bc8cb80b83bc7f8e7dcfd079c1b575cc020fa5fc0e48e88a4e62892` |
| `model.py` | `98f0f9c1492b96383dd8c76ce60de6944dd29e9b3a1a3b9bb652935be91503ed` |
| `shapes.lani` | `2b010a8aa820be581e22bd860c2090cbf14858514e12d301f9b084edc46fafa7` |
| `tests/stdlib_infallible_nested_iteration_execution.rs` | `5cfbb4c3648ec99843d419e58003fa952d1bf3012a650251258f45f9736a04bf` |
| `stdlib/core/iter.lani` | `5034fbac8a84b1499af18fbaf2963d54da4452e633413d33804b154e1a108a64` |

Model and shape native ELFs were retained at
`/tmp/infallible_nested_native_model_lani_486601_0` and
`/tmp/infallible_nested_native_shapes_lani_486601_2` respectively.
Their SHA256 values are
`06e69f968df14d20792fe5787abebb9362d14dd7e650b019743cb09440c96acc`
and `cc227625cbae1f069902d67e049cc63c7adf142444ebc5868d712478c138543e`.

The public `smoke.lani` SHA256
`2e8f7c798e523fdbf7d89c1903efe1448d6944eeb49c7ab63a64bff4b5d1aa53`
compiled and executed with exit zero, recorded in
`target/stdlib-work/infallible-nested-public-smoke-first.log` and
`target/stdlib-work/infallible-nested-public-smoke-native-first.log`. Its ELF
SHA256 is `262636b9c15f4c702eed2c724e3295a58849ecd2a403be496073b8c5a1f3a1b7`.
This separate CLI smoke covers caller-defined factories/policies, lazy/empty
construction, empty-inner retirement order, finish refusal, take/resume,
remaining outer continuation and fused EOF. It is not another Rust test receipt.

## Shared state model

`model.py` imports the accepted independent generator/deque oracle and strict
binary validator from [nested_iteration/model.py](../nested_iteration/model.py).
The old oracle, Lanius sources and accepted 360/672-case checks are unchanged.
The reused reference SHA256 is
`8f42d07d063649423ebde0a392474cb1bb0c9172b0ba6806856f0c1011f7d720`.
There is no new reference traversal engine. Twenty-four commands pair twelve
curated row/action profiles with real ordinary Flatten and FlatMap:

- Empty outer, finish before pulling, all-empty inners and mixed empty/data
  inners, with retirement before another outer acquisition and fused EOF.
- Active finish refusal, take-once with no source/retirement effects, manual
  recovered-inner traversal/retirement and fresh-adapter source resumption.
- Two independent adapters interleaving active inners over one outer source.
- A row whose last item was returned but whose None has not been observed:
  finish still refuses, take recovers the exhausted cursor, and explicit
  retirement precedes resumption.
- Take before any pull closes without acquisition; fresh construction resumes.

The new `model.lani` retains the existing 25-word request and 14-word per-action
snapshot protocol. Its callbacks use `Mapper<S,J>` and the actual
`InnerRetirement<J,core::clone_values::Infallible>`; constructors are checked for
zero source/callback/policy effects. `next` is explicitly `Option<u64>`, with
no exposed Result wrapper. The impossible error selectors remain disabled in
the reused reference protocol. The policy returns None, without fabricating an
Infallible value or replacing it with Unit or a scalar error.

Snapshots compare values, both active states, shared outer position/calls,
mapping/retirement counts, actual recovered position and the complete ordered
effect trace. Final borrowed-only cursor cleanup follows the emitted snapshot
trace and makes no native-owner claim.

## Plain payloads and composition

`shapes.lani` checks:

- `Some(None)` as an ordinary optional item followed by another item, and an
  ordinary nested Err payload, distinct from termination or adapter failure.
- Full-width u64/i64 fields, nested arrays and optional bool data with complete
  value assertions. No Clone/Destroy or per-type overload is required.
- Nonzero-start views with actual descending native byte stride and packed
  positive byte stride over live stack backing; prefix/suffix sentinels remain.
- Actual zero-sized Unit items, zero-stride backing, finish refusal, recovery
  of an already-exhausted Once cursor, take-once/fusion, explicit infallible
  retirement and shared-source resumption. No bare Unit-return helper is used.
- Both ordinary adapters composed with Scan and a two-item Take. No third pull
  or retirement occurs at the quota. The still-active exhausted inner is
  recovered, retired, then a fresh adapter drains the remaining row.

All backing and callback state remain live through their last observation.
The selected policies own no native backing. Owning Vec/Deque retirement,
allocation injection, strict pre-exit resource balance and application gates
are separate; these fixtures do not substitute for them.

## Current CPU evidence and exact gates

Python-only controls pass nine assertions: 24-case selection, no error channel,
hand-checked exhausted-active finish/take state, no-effect early finish, shared
validator round-trip and partial/extra/mutated binary output rejection. These
controls execute no compiler or native Lanius and do not rerun old native tests.

Exact filters in `stdlib_infallible_nested_iteration_execution`:

- `plain_nested_actions_match_existing_independent_sequence_oracle`
- `plain_nested_optional_wide_strides_zero_sized_and_composition_execute`

```sh
python3 -B tests/fixtures/stdlib_foundation/infallible_nested_iteration/model.py controls
```

Root serialized compiler/native commands, each below two minutes. The native
model deadline is 30 seconds with a 45-second outer deadline; shapes have five
seconds. The driver uses the existing strict ELF validator. The accepted target
is native Linux x86_64 CPU programs emitted by the GPU compiler, without a
user-program GPU or other-host claim. The full library goal remains open.
