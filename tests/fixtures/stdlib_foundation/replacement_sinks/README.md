# Replacement sink semantic execution gates

Status: both semantic gates passed in separate commands. These fixtures use the
actual public `core::iter` helper and all four actual collection delegates.
The source writer owns `smoke.lani` separately.

## Accepted receipts

| Rust filter | Executed scope | Log in `target/stdlib-work/` | Invocation elapsed |
| --- | --- | --- | --- |
| `replacement_sink_phases_identity_progress_retry_and_all_facades_match_model` | 53 binary command scenarios | `replacement-model-typed-prime-retry.log` | 9.73 seconds |
| `replacement_sink_nested_optional_wide_zero_sized_and_duplicate_policies_execute` | Native optional/wide/zero-sized and four-facade policy assertions | `replacement-shapes-local-projection-retry.log` | 9.49 seconds |

The other test was filtered out in each invocation. No combined both-passing
duration is recorded. Accepted source SHA256 values:

| Source | SHA256 |
| --- | --- |
| `model.lani` | `143ce22b758311ef193ecdc55699245df9deda53eca6bfc8b60b8d0027b4ea48` |
| `model.py` | `213308ef7f5ba9c6d030ca7f1d29992ae70a6005bbbeee6e90b7a265dbf1f57e` |
| `shapes.lani` | `36239e34f9fd9326f28ee43b5afc8ee3fd6250d1ee554302a0c4f44963baa21c` |
| `tests/stdlib_replacement_sinks_execution.rs` | `dbbbfdb72415a11f2d2084740862acedca282910868e627051550ec506700c34` |

The accepted target is native Linux x86_64 CPU programs emitted by the GPU
compiler. These semantic receipts establish no user-program GPU, other-host,
strict native-owner/allocation-injection or real-program acceptance.

## Finite independent model

`model.lani` receives eight binary u64 words per command. `model.py` supplies
53 scenarios: ten profiles for each of four actual facades and one scripted
replacement sink, plus three focused precommit-rejection profiles. HashMap and
HashSet keys all collide; tree keys compare only logical identity. Distinct
representative tokens and full-width values expose old-key loss, returning the
supplied set item, or retaining an old representative instead of the incoming.

The Python expectation builds a finite source queue and dictionary timeline of
complete item tuples, then derives the consumed prefix, progress, deliveries
and effect trace. It implements no production iterator or collection. Every
phase compares complete replacement contents, displaced history, returned
failure item, source position/calls and delivery attempts. Script replacement
counts include setup insertions, with its trace starting after setup. Actual
collection replacement counts are unavailable and encoded as zero, without
claiming no replacement operation occurred.

Each scenario performs bounded transfer, retry with failure still armed, retry
after clearing failure, source resumption, MAX drain, zero quota and another EOF
observation. Zero and exact quotas must not probe EOF. Rejected returns the
incoming item without committing it; Undelivered includes the committed update
and returns the old item. Delivery retry performs no second replacement.
Logical representative inventory is conserved across destination, accepted
history, pending failure and source remainder after every phase. Logical tokens
do not establish native resource ownership.

Only mode zero supplies scripted precommit rejection. Actual allocator failure
and strict ownership campaigns are separate. Fixture-only observation/factory
traits inspect concrete collections without wrapping the replacement
destination passed to the helper. Their `arm` hook configures only the scripted
sink and deliberately does nothing on real facades.

## Payload and existing-policy checks

`shapes.lani` checks optional items/errors whose absence stays distinct from
insertion/displacement and success/rejection, nested Result errors, wide arrays,
and actual zero-sized item and both error types. It verifies progress, source/
callback counts, zero-sized array writes, explicit recovery and resumed source.

Each real facade replaces a distinct stored key representative, returns/checks
the complete old item, then applies existing duplicate-rejecting
`try_transfer_up_to` with a third representative. Rejection must return the
supplied item and preserve the currently stored key/value. Nested wide record
values have no Eq, Hash, Ord, Clone or Destroy implementation; only stable key
identity has the required key bounds. Collection storage is explicitly
destroyed. Scalar payloads imply no String-owner or pre-exit ledger claim.

Python-only controls separately pass 18 assertions for zero/exact/EOF behavior,
both failure phases, retry, representative order, inventory and strict binary
framing/content mutations. They execute no compiler or native Lanius.

## Earlier failures and separate call dependency

The initial Rust driver built in 1.77 seconds, then a mixed two-test invocation
failed in 10.74 seconds: `replacement-models-shapes-first.log` (SHA256
`d9732104205c5fa159e3f0be948ead034b51f715e843cfbe8f29a92d33655476`).
Neither timing describes a passing gate.

- Original model `2820de9a901f6756b65c452c0306f14dd19ea681b14e6c250a4671a12fb35041`
  stopped pre-native at CallMismatch token 4173/detail 777 in a chained generic
  setup query. Equivalent typed `T`, `Result<Option<T>,RE>` and `Option<T>`
  intermediates admitted the unchanged contract/model; no general inference
  defect is inferred from this source-form receipt.
- Original shape `3e1f815964f97f724ebcb7d7051f02ab9a4e7580d2f54c6904ba2c5f0b089b15`
  compiled but trapped without output. The marker diagnostic `586dce67...`
  emitted exactly `AabcdefghijklmB`, proving the optional/nested-wide/error-tag
  profile completed before entering the zero-sized profile. The Unit diagnostic
  `44386838...` had correct source/R/D effects and Err/Undelivered tags, but
  progress became `(0,0)` when passed through an extra fixture Unit-returning
  function. These observations are in `replacement-shapes-diagnostic-*` and
  `replacement-unit-diagnostic-*` logs, under `target/stdlib-work/`.
- Direct public failure construction/projection, public Result enclosure and
  generic return, and equivalent caller-defined enum controls passed their
  layout checks. Only the extra `(Progress,Unit,Unit)->Unit` fixture call
  corrupted fields. A standalone no-import reproduction confirms that specific
  compiler/runtime call boundary; its scalar-return-only control passes.
  Minimal sources and exact hashes/receipts are preserved in
  [replacement_zst_return](../../stdlib_compiler_state/replacement_zst_return/README.md).

The active shape asserts the failure variant and progress directly and extracts
the Unit item locally. It keeps every original zero-sized type and progress/
counter/array-write/recovery expectation. Public failure storage and the
replacement helper's Unit API are covered by passing controls and the actual
shape gate. No public payload is padded or scalar-wrapped; no production,
compiler or ABI implementation changed. The separate dependency does not block
this accepted API subset. Intermediate diagnostic source copies were removed
from the permanent fixture directory and archived under
`target/stdlib-work/replacement-semantic-diagnostics/`; logs remain under
`target/stdlib-work/`. The full library goal remains open.

```sh
python3 -B tests/fixtures/stdlib_foundation/replacement_sinks/model.py controls
```

Root serializes compiler/native commands, each below two minutes. The native
model deadline is 30 seconds with a 45-second outer deadline; shapes have five
seconds. The driver retains the shared strict ELF validator. This author
performed CPU/static work only.
