# Checked layout arbitrary-precision model

This fixture checks all eight free functions in the
[storage-layout contract](../../../../docs/library-layout-plan.md) against
unbounded integer arithmetic. Production remains Lanius. Python and the
binary adapter are test infrastructure only; neither creates pointers or
allocates backing based on a modeled size.

## Independent arithmetic

The reference recognizes alignment by membership in the explicit set
`{2^0, ..., 2^63}`. It computes ceiling multiples, sums and products with Python
arbitrary-precision integers, then compares the mathematical rounded result
with `isize::MAX`. It does not reproduce the implementation's bit checks,
subtraction guards, division-before-multiplication or checked-addition paths.

Array size includes the final element's stride padding. Extended records
retain their unpadded size, with a separately observed right-field offset;
the final maximum alignment is validated even if offset plus right size
would fit. Input validation follows the specified error order: alignment
before size in one Layout, left before right for extend, and existing Layout
before the requested alignment for align_to. A zero count never bypasses
element validation, while zero stride accepts every `usize` count.

## Finite corpus

There are **18,878 cases**, with seed `0x1a90a0261031`: 9,439 distinct
operation/operand tuples, each constructed through direct forged fields and
through mutation of an initially valid Layout. The paired forms check the
same public arithmetic contract without an unchecked constructor. Caller
left/right fields are observed after every operation.

| Operation | Cases |
| --- | ---: |
| from_size_align | 2,434 |
| validate | 2,488 |
| is_valid | 2,426 |
| padding_for | 2,426 |
| pad_to_align | 2,424 |
| align_to | 1,488 |
| array | 2,748 |
| extend | 2,444 |

The corpus combines a boundary grid; every valid alignment power; small
nonpowers and large malformed alignments; binary combinations of valid and
forged layouts; count quotient boundaries; explicit arithmetic record-field
compositions; and 2,000 seeded candidate tuples, deduplicated with the rest.

Values include zero, small padding transitions, `2^31`/`2^32` boundaries,
`isize::MAX` neighborhoods and `usize::MAX`. High alignment `2^63` is tested
with both legal zero size and rejected positive sizes. Count zero, zero stride
with `usize::MAX`, padded nonempty arrays, the final representable array and
the immediately overflowing count are included. Extend covers offset, sum and
final-rounding overflow, including different error classes on its two inputs.
These are byte-storage arithmetic records, not inferred compiler-native
record layouts or evidence that huge storage can be obtained.

Expected results comprise 8,004 successful Result values, 2,728
InvalidAlignment errors, 5,720 SizeOverflow errors and 2,426 boolean is_valid
observations. All payload fields, auxiliary stride/offset/padding values,
error tags and original operands are compared exactly.

## Protocol and acceptance

Each input case is eight little-endian `u64` words: operation, four operands,
construction form, identity and reserved zero. The Lanius adapter verifies
the 64-bit usize transfer profile, bounds the selector and calls the selected
public function. It never uses a modeled layout as an actual allocation size.

Each output case has ten words: operation, result/bool tag, error kind,
result size, result alignment, auxiliary value and both original Layouts.
The auxiliary value carries stride, offset, padding or a Boolean as appropriate.
Unused result fields must remain zero. The oracle rejects mismatched,
truncated or extra output and includes the full case and seed in diagnostics.

CPU controls pass with explicit constructor/padding/array/extend/precedence
vectors. Seven intentional corruptions of retained size, error precedence,
array stride, high alignment, extension offset, caller fields and boolean
validity are rejected.

The registered native gate passed on its first attempt: **1 test in 5.46s**,
with all **18,878 cases / 8 functions / 2 construction forms** reported by the
native process at seed `0x1a90a0261031`. The receipt is
`target/stdlib-work/layout-model-first.log`. This includes executable behavior,
exact result/error observations and unchanged input fields, beyond compilation.

The registered Rust gate is
`arbitrary_precision_layout_models_match_values_precedence_and_input_preservation`
in `stdlib_layout_model_execution`. It checks executable ELF admission before
publication and uses shared x86 jump validation, one batched native process,
an 85-second outer timeout and a 70-second child timeout. Accepted target:
native Linux x86_64 CPU output from the GPU compiler, with the current 64-bit
usize/isize profile. Arena allocation, physical layout/backing and pure-phase
host-effect checks belong to separate consumer/contract tests. No direct GPU,
arbitrary-target, automatic ownership or formal verification claim is made.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/layout.lani` | `d6e302727f3b865711f3904c7139efd0afdaa82fd438778124ddf23b0334c5a4` |
| `model.lani` | `d3c174d7e6c83831e3c9f23ac36e9877a2d3656094d4f01f861ec03e8c8fc740` |
| `oracle.py` | `d88e6334f3d8eacc1bb49801bdf50730848c0d94e9ce6befe6dcaf14b93002dd` |

```sh
python3 -B tests/fixtures/stdlib_foundation/layout_model/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/layout_model/oracle.py /path/to/model
```
