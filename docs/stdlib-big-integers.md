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
| Division | `div_rem`: Knuth algorithm D, Burnikel-Ziegler above 1,024 limbs | `div_rem` (truncating), `div_rem_euclid` |
| Powers | `pow(u32)`, `mod_pow(exponent, modulus)` | `pow(u32)`, `mod_pow(exponent, modulus)`, including negative exponents |
| Inverses | `mod_inverse(modulus)` | `mod_inverse(modulus)` |
| Number theory | `gcd` | `gcd` (nonnegative) |
| Bits | `shl`, `shr`, `bit_and`, `bit_or`, `bit_xor`, `bit`, `bit_length` | `shl`, arithmetic `shr`, `bit_and`, `bit_or`, `bit_xor`, `bit_not` |
| Comparison | `compare`, lawful `Eq`/`Ord`/`PartialOrd`, `Hash` | `compare`, lawful `Eq`/`Ord`/`PartialOrd` |
| Text | `format_radix`, `format_into`, radix 2 to 36 | same, with a leading `-` |

Every fallible operation takes `alloc::big_uint::Limits` by value. It returns
`core::result::Result<_, alloc::big_uint::Error>`. Allocation is explicit:
each success returns a new owner, which must be destroyed exactly once.
Operands are borrowed and survive every error.

`Error` has two new final variants:

- `NotInvertible`: returned by `mod_inverse`, and by `BigInt::mod_pow` with a
  negative exponent, when `gcd(a, m) != 1`.
- `NegativeExponent`: no library operation returns it any more, because
  signed `mod_pow` now accepts negative exponents. It stays for callers;
  `bc` reports it for `^`.

The thresholds are public constants:

| Constant | Value | Used for |
| --- | ---: | --- |
| `KARATSUBA_THRESHOLD` | 32 limbs | Both multiplication operands |
| `BURNIKEL_ZIEGLER_THRESHOLD` | 1,024 limbs | The divisor, and the dividend's excess over it |
| `CONVERSION_THRESHOLD` | 1,024 limbs | Divide-and-conquer formatting |

Parsing switches to divide and conquer above 8,192 digits.

## Multiplication: schoolbook and Karatsuba

`mul` uses Karatsuba when **both** operands have at least
`alloc::big_uint::KARATSUBA_THRESHOLD` (32) limbs and the full product fits in
`max_limbs`. Otherwise it uses the existing schoolbook loop, including the
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

The workspace is the one vector allowed to exceed `max_limbs`. It is bounded
by `8*max_limbs+64` and by the vector's limb capacity; past either bound, `mul`
uses schoolbook instead. An earlier draft also required the workspace to fit
in `max_limbs`. That sent large squarings in `pow` to schoolbook: `2^100000000`
under `bc`'s 65,536-limb limit took more than 20 s. With the current bound it
reaches `WorkLimit` in about 1 s. When an allocation fails, `mul` destroys whatever it has already allocated and
returns `AllocationFailed`. Both operands are preserved.

Every window the kernel writes holds the complete value it accumulates. Carry
propagation is bounded by the window end and never leaves the window.

Work accounting keeps the existing conservative charge of `n*m` limb
products. Karatsuba performs fewer, so the same `max_work` admits the same
calls.

## Division: Burnikel-Ziegler

`div_rem` uses recursive Burnikel-Ziegler division when the divisor has at
least 1,024 limbs and the dividend has at least 1,024 more. Otherwise it uses
Knuth algorithm D. The recursion follows CPython's `_pylong` formulation:

- `fast_div` shifts the divisor so that its bit length `n` is a whole number
  of limbs. It then divides the dividend in `n`-bit chunks from the top, and
  each chunk's quotient is copied straight into its limb position. Rebuilding
  the quotient with repeated shift-and-add would be quadratic.
- `div2n1n(a, b, n)` requires `a < b*2^n`, with `b` exactly `n` bits long. It
  makes two `div3n2n` calls on halves; an odd `n` first doubles both
  operands.
- `div3n2n` estimates the quotient from the top halves, either recursively or
  as the saturated `2^n-1`. It subtracts `q*b2` and corrects at most twice. The
  test `rr < q*b2` adds `b` before subtracting, so all values stay unsigned.
- The base case is Knuth division whenever `n` or the quotient length is
  below the threshold.

The cost is `O(M(n) log n)`, where `M` is the Karatsuba multiplication time.

Work accounting still charges the Knuth bound, `division_work`, so a
`max_work` value admits the same calls on either path. Million-digit inputs
therefore need a large `max_work`.

Internal steps use a context that records the first error and returns zero
owners. Every intermediate is destroyed on every path. A failure is reported
only after cleanup, and both operands are preserved. Intermediate values may
exceed `max_limbs` by the shift and recombination headroom. The quotient and
remainder are checked against `max_limbs` at the end.

## Modular inverse

`BigUint::mod_inverse(modulus)` runs the extended Euclidean algorithm over
magnitudes:

- It keeps `u_{i+1} = u_{i-1} + q_i*u_i`, which uses the invariant
  `r_i ≡ (-1)^(i+1) * u_i * a`. It returns `u_k` or `modulus - u_k`, depending
  on the parity of the step where `r_k = 1`.
- A remainder of zero first returns `NotInvertible`, a zero modulus
  `DivisionByZero`, and a modulus of one returns zero.
- A remaining work budget is charged once per step, at the Knuth division
  bound plus the coefficient product.

`BigInt::mod_inverse` matches Python's `pow(a, -1, m)`. A negative `a` maps to
`m - inverse`. A nonzero result takes the modulus's sign.

`BigInt::mod_pow` with a negative exponent computes
`mod_pow(mod_inverse(a), -e, m)`, which is Python's `pow(a, -e, m)`.

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

Parsing and formatting accept every radix from 2 to 36. They choose one of
three paths:

- **Power-of-two radices** (2, 4, 8, 16, 32) use linear bit packing and
  unpacking for inputs above 600 digits or values above 1,024 limbs. A
  million-digit hexadecimal round trip went from 17.7 s to 0.63 s.
- **Other radices, large values:** divide and conquer, which costs
  `O(M(n) log n)`.
  - Parsing above 8,192 digits splits the digit string at `g*2^j` digits and
    computes `high*radix^(g*2^j) + low`.
  - Formatting above 1,024 limbs divides by the precomputed squares
    `(radix^g)^(2^i)`. It emits the quotient, then the remainder left-padded to
    exactly `g*2^i` digits. A quotient of zero becomes zeros on padded paths.
  - Both build only the powers they need, by repeated Karatsuba squaring.
    Formatting stops at the first power whose square exceeds the value.
- **Small values** use the basecase loops below. The new paths charge the
  same basecase work bound, so a limit admits the same inputs either way.

The basecase loops process
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

## Million-digit oracle

`tests/oracles/bc_million.py` uses fixed seed `0x1E6`. It runs each operation
in its own `bc` process and compares the full decimal output with Python
3.12.3 `int`. The operands are:

- `A`, with exactly 1,000,000 digits;
- `B`, with exactly 500,000 digits;
- a 3,000-digit odd modulus `M`.

The `bc` time includes start-up, parsing, the operation and printing. The
Python time covers `int()`, the operation and `str()`. Python 3.12 also uses
subquadratic conversion and division for numbers this large. These results
are from one local run on 2026-10-31.

| Operation | Result digits | `bc` | Python | Ratio |
| --- | ---: | ---: | ---: | ---: |
| Round trip `A` | 1,000,000 | 30.7 s | 0.93 s | 33× |
| `A+B` | 1,000,000 | 32.0 s | 1.05 s | 30× |
| `A*B` | 1,500,000 | 57.4 s | 1.51 s | 38× |
| `B*B` | 1,000,000 | 37.6 s | 1.22 s | 31× |
| `A/B` | 500,000 | 24.2 s | 1.11 s | 22× |
| `(-A)%B` | 500,000 | 31.8 s | 2.63 s | 12× |
| `modpow(B[:20000], B[:3000], M)` | 3,000 | 51.0 s | 1.81 s | 28× |

All seven outputs match Python exactly.

**Where the time goes:**

- Decimal conversion dominates. Parsing a million digits takes 15 s, and
  printing them takes about twice as long. Both reduce to Karatsuba
  multiplications, at about 26 ns per 32-bit multiply-add with the current
  code generator.
- The hexadecimal round trip takes 0.63 s.

**Before this change,** the quadratic basecase needed about 5.5 s for 50,000
digits. Scaled by `n^2` that is roughly 40 minutes for a million digits; this
is an estimate, and a million-digit basecase run was not attempted.

**Remaining gap to Python:** 64-bit limbs, Toom-Cook and leaner allocations.

**Threshold choices:**

| Configuration | 200,000-digit division | `modpow`, 3,000-digit modulus, 300-digit exponent |
| --- | ---: | ---: |
| Burnikel-Ziegler at 64 limbs | 1.84 s | 9.73 s |
| Burnikel-Ziegler at 256 limbs | 1.53 s | 6.44 s |
| Burnikel-Ziegler at 1,024 limbs | 1.56 s | 5.20 s |
| Burnikel-Ziegler at 2,048 limbs | 1.71 s | 5.11 s |

For formatting 200,000 digits, a 1,024-limb leaf (2.12 s) was faster than 64
or 256 limbs (2.37 s).

**A bug found during tuning:** Karatsuba's workspace check compared against
`max_work as i64`. A `max_work` of `u64::MAX` became `-1`, which silently
disabled Karatsuba. The check now compares unsigned values.

## Verification

All evidence is native x86_64 Linux execution of binaries compiled by
laniusc. It is not evidence of GPU kernel arithmetic.

- `tests/stdlib_bc_execution.rs` compiles `sample_programs/library/bc.lani` and
  runs `tests/oracles/bc_oracle.py`. The oracle is an independent Python
  integer reference with fixed seed `0xBC2026`. The current oracle adds
  inverse cases: 378 `modinv` calls and 155 `modpow` calls with negative
  exponents, including not-invertible pairs. It checked
  **9,735 values and 326 diagnostics** in radices 10, 16, 2, 3, 7 and 36, in
  about 23 s.

  Its operands have at most 513 limbs, so with the final thresholds it
  exercises Knuth division and basecase formatting. The same oracle also
  passed against a build with both the Burnikel-Ziegler and conversion
  thresholds at 64 limbs, which drives those paths through the same values.
  The million-digit oracle covers the final thresholds.

  The category list below is from the earlier run of 9,526 values and 103
  diagnostics. That run used the same generator without the inverse cases: The checked cases are:
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
- Separate Python checks of radices 2, 4, 8 and 32 cover the
  power-of-two paths. They used products of up to 200,000 bits, plus a
  900-digit run of zeros.
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
