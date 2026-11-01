# Arbitrary precision integers

`alloc::big_uint` (`BigUint`) and `alloc::big_int` (`BigInt`) are owned
arbitrary precision integers in the `alloc` layer. They depend only on `core`
and `alloc::vec`. They used to be the optional modules `ext::big_uint` and
`ext::big_int`. The code moved without changing its ownership or limit
contracts, and every repository consumer now imports the `alloc` paths.
`ext::decimal`, the `bigcalc` program and the test fixtures are among them.

This page covers the layout, the algorithms, the performance work and the
evidence. The per-operation contracts are in two other guides.

- [Unsigned contracts](stdlib-big-uint.md): limbs, `Limits`, `Error`, Knuth
  division bounds, equality and hashing.
- [Signed contracts](stdlib-big-int.md): sign handling, truncating and
  Euclidean division, infinite two's complement bit operations.
- [`bc` program](stdlib-bc.md): an expression calculator over stdin, checked
  against Python integers.

## Operations

| Area | `BigUint` | `BigInt` |
| --- | --- | --- |
| Construction | `zero`, `from_u64`, `parse(View<u8>, radix, limits)` | `zero`, `from_i64`, `from_u64`, `parse` with optional sign |
| Arithmetic | `add`, `sub` (rejects underflow), `mul` | `add`, `sub`, `mul`, `neg`, `abs` |
| Division | `div_rem` (Knuth algorithm D) | `div_rem` (truncating), `div_rem_euclid` |
| Powers | `pow(u32)`, `mod_pow(exponent, modulus)` | `pow(u32)`, `mod_pow(exponent, modulus)` |
| Number theory | `gcd` | `gcd` (nonnegative) |
| Bits | `shl`, `shr`, `bit_and`, `bit_or`, `bit_xor`, `bit`, `bit_length` | `shl`, arithmetic `shr`, `bit_and`, `bit_or`, `bit_xor`, `bit_not` |
| Comparison | `compare`, lawful `Eq`/`Ord`/`PartialOrd`, `Hash` | `compare`, lawful `Eq`/`Ord`/`PartialOrd` |
| Text | `format_radix`, `format_into`, radix 2 to 36 | same, with a leading `-` |

Every fallible operation takes `alloc::big_uint::Limits` by value. It returns
`core::result::Result<_, alloc::big_uint::Error>`. Allocation is explicit:
each success returns a new owner, which must be destroyed exactly once.
Operands are borrowed and survive every error.

`Error` has a new final variant, `NegativeExponent`. Only
`BigInt::mod_pow` returns it.

## Multiplication: schoolbook and Karatsuba

`mul` uses Karatsuba when **both** operands have at least
`alloc::big_uint::KARATSUBA_THRESHOLD` (32) limbs, the full product fits in
`max_limbs`, and the workspace described below also fits in `max_limbs`.
Otherwise it uses the existing schoolbook loop, including the
edge case where the product is exactly one limb longer than `max_limbs` and
must be clamped.

The Karatsuba kernel works on limb windows of the operands and does not copy
them. It accumulates `out[at..] += x[window] * y[window]`:

- It trims high zero limbs from each window first. Sparse values and sums with
  a zero carry limb therefore recurse on their real size.
- It uses schoolbook below the threshold. The inner step is
  `factor*x_j + out + carry <= (B-1)^2 + 2(B-1) = B^2-1`, which is exact in
  `u64`.
- **Unbalanced operands:** when the shorter operand fits in the low half of
  the longer one, only the longer operand is split. The two partial products
  are accumulated at offsets `0` and `k`.
- **Balanced operands:** with `k = ceil(n/2)`, it computes `z0 = x0*y0`,
  `z2 = x1*y1` and `z1 = (x0+x1)(y0+y1) - z0 - z2`. The difference equals
  `x0*y1 + x1*y0 >= 0`, so the in-place subtraction cannot underflow. Then it
  adds `z0`, `z1 << k` and `z2 << 2k` into the output.

`mul` allocates exactly two vectors: the product and one workspace. A
balanced node of `n` limbs keeps `z0[2k]`, `z2[2k]`, both half sums `[k+1]`
and `z1[2k+2]` in `8k+4` workspace limbs. It hands the rest of the workspace
to its children, which run one at a time. Unbalanced nodes need no storage of
their own. The workspace size is therefore the sum of `8k+4` over the chain
`n -> k+1` while the size stays at or above the threshold, which is about
`8*max(n, m)` limbs.

The workspace goes through the same bounded `fresh` path as every other
vector. When it would exceed `max_limbs`, `mul` uses schoolbook instead. When
an allocation fails, `mul` destroys whatever it has already allocated and
returns `AllocationFailed`. Both operands are preserved.

Every window the kernel writes holds the complete value it accumulates. Carry
propagation is bounded by the window end and never leaves the window.

Work accounting keeps the existing conservative charge of `n*m` limb
products. Karatsuba performs fewer, so the same `max_work` admits the same
calls.

## Modular exponentiation

`BigUint::mod_pow(exponent, modulus, limits)` first reduces the base modulo
`modulus`. It then runs left-to-right square-and-multiply over the exponent's
bits and reduces each product with Knuth division.

- The result is in `[0, modulus)`.
- A zero modulus returns `DivisionByZero`.
- A modulus of one returns zero, including for `0^0`.
- Like `pow` and `gcd`, it keeps one remaining work budget across all steps.
  Each step is charged `len(a)*len(b) + division_work(len(a)+len(b), len(m))`
  before it runs.
- Intermediate products need up to `2*len(modulus)` limbs, under `max_limbs`.

`BigInt::mod_pow` matches Python's `pow(a, e, m)` for `e >= 0`:

- A nonzero result takes the sign of the modulus, so `0 <= r < m` or
  `m < r <= 0`.
- A negative base with an odd exponent maps `r` to `|m| - r` before the sign
  step.
- A negative exponent returns `NegativeExponent`. Modular inverses are not
  provided.

## Radix conversion

Parsing and formatting accept every radix from 2 to 36. They now process
`g` digits per pass, where `g` is the largest value with `radix^g < 2^32`. For
example, `g = 9` for radix 10, `g = 7` for radix 16 and `g = 31` for radix 2.

- **Parsing** computes `value = value*radix^g + chunk` with one
  `mul_add_small` per group. It also reserves its final limb count once:
  `ceil(log2 radix)` bits per digit, capped by `max_limbs`. Before this change
  every new limb reallocated the vector exactly.
- **Formatting** divides by `radix^g` once per group and emits `g` digits. The
  most significant group stops at its last nonzero digit, and zero still
  formats as `0`.

Both conversions are still quadratic in the number of digits; the constant is
now about `g` times smaller. The work accounting is unchanged. It counts one
pass of `limbs+1` per group, so a given `max_work` allows strictly more
digits than before. The output limit is checked before every byte.

## Performance work

The hot inner loops now index each vector's initialized slice directly
instead of calling `Vec::get_or` and `Vec::set`, which build an `Option` or
`Result` for each limb. These loops are:

- small multiply-add and small division;
- the Karatsuba schoolbook leaf and the workspace window add, subtract and
  clear;
- the Knuth multiply-subtract step.

Slice indexing keeps the language's bounds checks.

These timings are from one local run on the 3070 laptop on 2026-10-31, with
other agents competing for the machine. They are observations, not
guarantees.

| Workload, via `bc` with `--ibase 16` | Before | After |
| --- | ---: | ---: |
| Parse 200 hex numbers of 513 limbs | 1.33 s | 0.60 s |
| Parse one 4,943-digit decimal number and print it again | 0.44 s | 0.03 s |
| 100 products of 513×513 limbs, schoolbook only (threshold set to 1,000,000) | 12.9 s | n/a |
| 100 products of 513×513 limbs, Karatsuba at 32 limbs, with per-node temporaries | 2.8 s | 1.8 s, including 0.7 s of parsing |
| The same, with one Karatsuba workspace | | 0.55 s, including 0.33 s of parsing (about 2.2 ms per product) |
| The radix 10 part of the `bc` oracle (5 MB of input) | 11.5 s | 3.8 s |

Moving the threshold from 32 to 64 limbs changed the 513-limb case only
within noise.

With per-node temporaries, a 513-limb product made about 400 allocations, each
an `mmap` with fresh page faults. The single workspace removed nearly all of
the system time.

What remains is mostly the code generator's cost of about 20 ns per
inner-loop iteration. Quadratic radix formatting of the 1,000-limb products
also costs more than multiplying them.

## Verification

All evidence is native x86_64 Linux execution of binaries compiled by
laniusc. It is not evidence of GPU kernel arithmetic.

- `tests/stdlib_bc_execution.rs` compiles `sample_programs/library/bc.lani` and
  runs `tests/oracles/bc_oracle.py`. The oracle is an independent Python
  integer reference with fixed seed `0xBC2026`. On 2026-10-31 it checked
  **9,526 values and 103 diagnostics** in radices 10, 16, 2, 3, 7 and 36, in
  about 11 s, including Python generation. The checked cases are:
  - 1,515 Karatsuba products, with both operands of at least 32 limbs;
  - 1,695 schoolbook products, using sizes 0–3, 30–34, 63–66, 95–97, 127–129,
    200, 257 and 513 limbs;
  - 76 squares;
  - 1,192 quotients and 1,192 remainders, including constructed `a*b+r`
    dividends;
  - 66 division-by-zero diagnostics;
  - 384 modular powers, with negative bases, negative moduli and `±1` moduli;
  - 258 powers, 240 GCDs and 240 absolute values;
  - 360 each of add, sub, and, or and shr, plus 366 shl cases;
  - 582 random expression trees;
  - fixed precedence, zero and syntax cases.

  The value patterns are random, all ones, a single top bit, sparse, and a
  top limb of exactly one. Signs are mixed.
- The existing unsigned model oracle in `tests/extended_big_uint_execution.rs`
  was compiled against the `alloc` path and run directly against
  `big_uint_model`: it verified all 2,366 cases. Its products have one operand
  of at most 16 limbs, so they stay on the schoolbook path. Only the
  squarings inside `pow` (for example `2^4096`) reach Karatsuba. The
  `big_uint_contracts`, `big_int_contracts`, `big_uint_smoke` and
  `decimal_arithmetic_contracts` fixtures also exit 0 natively.
- The allocation-denial suites require `strace` and were not run for this
  increment. The Karatsuba cleanup paths (product, then workspace) are
  therefore reviewed but not fault-injected. Under the user's current rule,
  cargo tests are not run: the registered Rust tests were written, and the
  same oracle scripts were run directly against binaries compiled by
  laniusc.
