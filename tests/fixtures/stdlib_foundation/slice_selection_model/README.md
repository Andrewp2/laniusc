# Checked nth-selection sorted-reference model

This fixture checks both public checked View selection functions against
Python's independently sorted ranks. The oracle does not reproduce BFPRT,
group medians, pivot choices, swaps or the implementation's explicit stack.
Production remains Lanius; the binary adapter and Python are test infrastructure.

## Observed contract

For every accepted case, the oracle checks the selected sorted rank, every
before/after partition inequality, a complete whole-value permutation and
unchanged surrounding backing. It accepts all lawful unstable arrangements,
including different representatives within an equal-key class and internally
unordered partitions. No exact callback sequence or permutation is expected.

Success metadata must describe the original absolute `start + nth` and one
element with the original native stride. The returned element must match the
stored nth element. The adapter snapshots the complete backing, then mutates
only through the returned View and emits a second complete snapshot. Exactly
the stored nth element must change by the specified bit mutation. This tests
aliasing beyond a detached selected-value comparison.

Families include natural u8, natural full-width i64, and compound records
with independent IDs, high-bit markers, two i64 payload words and Option<bool>.
Record comparators use ascending, descending and low-two-bit equivalence
orders, fixed during each call. Descending compares relations directly and
does not negate i64::MIN. Callback counters start at a nonzero sentinel;
invalid input and singleton selection preserve them exactly. Other valid
record cases must compare, without an exact count requirement.

Native stack and explicitly prepared storage are separate backing forms.
For u8 these exercise actual descending native and ascending packed strides.
The current i64/record ABI retains descending strides in both forms; no
positive-stride scalar/record ABI is invented. Valid intervals come through
a nested nonzero subview. Rejected metadata is forged directly, including
negative and overflowing start/length and invalid nth, and must preserve
all backing and callback state before access.

## Finite corpus

There are **11,976 distinct cases**, seed `0x5e1ec0261101`. Case identity is
excluded from deduplication, so repeated shapes do not inflate the count.

| Family / comparator | Cases |
| --- | ---: |
| Natural u8 | 2,768 |
| Natural i64 | 3,094 |
| Records ascending | 2,844 |
| Records descending | 1,636 |
| Records low-bit equivalence | 1,634 |

The corpus includes every rank of all length-1-through-4 sequences over a
three-value alphabet, every rank of every five-distinct-value permutation,
all-equal/ascending/descending/organ-pipe/sawtooth shapes at lengths through
40 and group/short-group boundaries, interior views, signed extrema and
nearby/full-width values, explicit invalid metadata/ranks and 200 seeded
shape candidates. Each shape covers both backing forms. There are 150
rejected and 314 accepted singleton cases; these are reference classifications.

CPU controls accept two different legal unstable tie choices and internally
unordered partitions. Seven corruption controls reject a wrong rank despite
permutation preservation, wrong partitions despite a correct rank, missing
alias mutation, wrong returned metadata, mismatched returned identity,
outside-storage corruption and a changed compound payload. An independent
integer simulation computes fourteen active median-only frames for
i32::MAX; it allocates no huge native arrays. Actual comparison-growth tests
are separate and this small model makes no empirical global complexity claim.

## Protocol and acceptance

Each binary request contains eight little-endian u64 header words followed
by at most forty scalar keys. Fields select family/form, supplied View
metadata, nth, comparator policy and case identity. Each response has a
ten-word metadata/counter/stride header, the returned element and two complete
48-element backing snapshots. Scalars use one word, compound records six.
The oracle rejects truncated/extra output and reports the complete case and
seed on mismatch. No JSON or product transport is added.

The first native gate stopped in the oracle after 6.82s because the reference
incorrectly required native stack u8 stride to equal -1. The observed stride
was -8; the producer already required only a negative native stride. The
oracle now checks negative native stride, packed stride +1 and exact returned
versus original stride equality. This was a fixture-only assumption failure;
production and the Lanius producer were unchanged.

The amended gate passed **1 registered test in 8.71s**, reporting all
**11,976 cases / 3 families / 2 backing forms / 3 record policies** at seed
`0x5e1ec0261101`. The receipt is
`target/stdlib-work/slice-selection-model-stride-oracle-retry.log`; the first
stop remains recorded in `target/stdlib-work/slice-selection-model-first.log`.
The accepted model's maximum source length is **40**. Larger comparison-growth
gates have separate receipts and do not expand this model's tested size range.
The seven corruption controls and fourteen-frame integer bound above are CPU
oracle controls, separate from the native case-summary observations.

The registered test is
`sorted_reference_checks_selection_rank_partitions_permutation_and_alias`
in `stdlib_slice_selection_model_execution`. It checks executable ELF before
publication and shared strict x86 jumps, then runs one batched native process
with a 90-second outer timeout and 75-second child timeout. Accepted scope is
finite Linux x86_64 CPU output from the GPU compiler. Owner cleanup, pure-phase
host effects, missing trait bounds, large comparison scaling and the real
selection program have separate gates. No direct GPU-device, stability,
arbitrary-target or formal verification guarantee is claimed.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/slice.lani` | `d77cb28ceb9f6df5e3fa0f752a36409bc4d2ddab1bd35214969fc39614fd13d5` |
| `model.lani` | `4aeb9ef2b9d0b46ed9f7b24c8499f8b533eda0dc7053b59cb204fa5634e780ef` |
| `oracle.py` | `db7a5e4772be2521a3e771c7478dce4ecba0f9cec561b2c69ee182839971b95e` |

```sh
python3 -B tests/fixtures/stdlib_foundation/slice_selection_model/oracle.py controls
cargo test --test stdlib_slice_selection_model_execution sorted_reference_checks_selection_rank_partitions_permutation_and_alias -- --nocapture
```
