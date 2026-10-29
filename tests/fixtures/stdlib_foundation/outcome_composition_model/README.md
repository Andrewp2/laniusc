# Eager outcome composition tagged-value model

This fixture independently models the fixed
[outcome composition contract](../../../../docs/library-outcome-composition-plan.md).
The adapter calls public Lanius free functions and methods; Python supplies
tagged-value tables and compares the actual observations. Binary transport and
Python are test infrastructure only.

## Finite corpus

There are **2,180 cases**, with seed `0xa7c20261031`, covering all 60 valid
operation/free-or-method/variant selectors:

| Operation | Cases |
| --- | ---: |
| Cross-type Option.and | 266 |
| Cross-type Result.and | 283 |
| Changed-error-type Result.or | 258 |
| Result flatten | 219 |
| Existing Option flatten plus its new method | 229 |
| Option<Result> to Result<Option> transpose | 221 |
| Result<Option> to Option<Result> transpose | 234 |
| Option<Result> inverse composition | 229 |
| Result<Option> inverse composition | 241 |

The base corpus applies all variant tables through both calling styles to
23 payload tuples, giving 1,380 cases. It includes all-zero/all-one payloads
and 21 rotated boundary patterns. Another 800 seeded cases vary every raw
word independently and regularly select NaN payloads. There are 1,097 free
function cases and 1,083 method cases.

Option.and changes `u64` to a compound record. Result.and changes its success
type from `u64` to that record while retaining its error type. Result.or keeps
the compound success type while changing its error from a signed-code/stamp
record to an array/Boolean record. Both binary inputs are built eagerly and
observed again after each operation.

The compound payload contains an `i64`, a two-word `u64` array, an `f64` and
`Option<bool>`. Observation checks the signed bit pattern, both full-width
words, exact float bits and optional Boolean tag independently. None,
Some(false), Some(true), zero success and zero-valued errors remain distinct.
Both old and replacement error fields are separately reported; unused fields
must remain zero. Integer cases include signed extrema, high-half-only words,
all ones and distinct byte patterns. Float encodings include both zero
signs, subnormal/normal boundaries, infinities and selected quiet/signaling
NaN payloads. Python never constructs floating values.

Nested Option/Result inputs retain separate outer/inner tags. Flatten is
checked against the appropriate inner/outer error source. Both transposes are
checked directly against their three-state tables. Both inverse cases also
report their actual intermediate shape, so matching inverse mistakes cannot
hide behind a recovered final value. Every case reports caller input copies
after the operation, including the otherwise discarded binary input.

## Protocol and acceptance

Each input case has eight little-endian `u64` words: operation, method flag,
variant, four payload words and identity. The adapter bounds the operation and
variant selectors. It calls only the selected public composition route.

Each output case has four 13-word observations: primary output, original
left/nested input, right binary input or an empty marker, and inverse middle
or an empty marker. An observation contains shape, outer tag, inner tag, five
payload fields, two old-error fields and three replacement-error fields.
Signed error codes use their full sign-extended word. The oracle checks every
word and rejects truncation or extra output; diagnostics retain the case and
seed. No error or presence tag is inferred from a payload's numeric value.

CPU controls pass, including manually checked selection/error/inverse cases.
Seven deliberate corruptions of presence, high payload bits, signaling-NaN
bits, a caller snapshot, signed error bits, replacement-error bits and an
inverse intermediate are rejected. The separate specialized-method admission
fixture has its own receipt.

The registered gate is
`independent_outcome_models_preserve_variant_tables_payloads_errors_and_inputs`
in `stdlib_outcome_composition_model_execution`. It uses shared strict x86 ELF
checks and one batched native process, with an 85-second outer timeout and a
70-second child timeout. Executable target: native Linux x86_64 CPU
output from the GPU compiler. Owner cleanup, borrowed strided payloads and
pure-phase host-call traces belong to separate focused contract tests. This
finite model supplies no automatic ownership, direct-device or formal claim.

The first registered runtime run passed: **one test and all 2,180 cases in
6.94 seconds**, with nine operations, both calling styles and seed
`0xa7c20261031`. The log is
`target/stdlib-work/outcome-composition-model-first.log`; its exact summary is
`outcome-composition cases=2180 operations=9 flavors=2 seed=0xa7c20261031`.
The accepted target is native Linux x86_64 CPU output from the GPU compiler.
This finite result covers the stated variant tables, payloads, errors, caller
snapshots and inverse intermediates. It does not establish arbitrary generic
shapes, cleanup authority or another target's exact-bit transfer behavior.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/option.lani` | `8b3cf42862f2c6c0203281d5b2b120124c0df74d1b0c664418f5a6e9f57938ee` |
| `stdlib/core/result.lani` | `1a036786910bdcb2f637a1d5e89d08881c2a2dea758beadc488065f8b23e748b` |
| `model.lani` | `f3811303c5e03f2bd1ab67fed3563876f8a99af83d600d8ebd18e267bba36a41` |
| `oracle.py` | `3319819648388cc96db5b0f3d0190a616889231fce2fef1cd373370ee8ab5bd5` |

```sh
python3 -B tests/fixtures/stdlib_foundation/outcome_composition_model/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/outcome_composition_model/oracle.py /path/to/model
```
