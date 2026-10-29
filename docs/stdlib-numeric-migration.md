# Numeric helper consolidation

Ordinary library code and samples use the canonical primitive modules:
`core::i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32` and `u64`. The redundant
`core::number_i8`, `number_i16`, `number_i32`, `number_u16`, `number_u32`,
`byte` and `narrow` implementations have been removed. There are no forwarding
aliases. The migration follows the executable primitive contracts in
[narrow integers](stdlib-narrow-integers.md) and
[native integers](stdlib-native-integers.md).

## Arithmetic and conversion policies

Existing saturation, wrapping, ASCII classification, case conversion, nibble
and hexadecimal behavior is preserved at the new primitive paths. Failure
policies belong to each caller:

| Old operation | Canonical expression and policy |
| --- | --- |
| `number_T::saturating_*` / `wrapping_*` | `T::saturating_*` / `wrapping_*` |
| `byte` ASCII and hex functions | Corresponding `u8` functions |
| `narrow::T_from_S_wrapping(x)` | `T::wrapping_from_S(x)` |
| `narrow::T_from_S_saturating(x)` | `T::saturating_from_S(x)` |
| `narrow::T_from_S_or(x, fallback)` | `option::unwrap_or(T::checked_from_S(x), fallback)` |
| Fallible multiply, power, division, remainder, LCM or alignment | Check the corresponding `checked_*` result; apply an explicit fallback only where the caller requires it |
| Signed `gcd_or(a,b,fallback)` | Compute the unsigned `T::gcd` magnitude, then check its conversion back to T before applying the fallback |
| Legacy next-power-of-two overflow returning zero | `option::unwrap_or(T::checked_next_power_of_two(x), 0)` where that policy is required |

The retained numeric policy fixtures exercise these explicit fallback choices,
including signed MIN magnitudes, `MIN / -1`, zero divisors, invalid alignment,
overflowing powers and conversion extremes. Canonical plain operations keep
their own documented trapping contracts; a rename does not change them into
legacy sentinel operations.

`narrow_byte_report` accepts any valid i32, including the formerly reserved
parse sentinel `123456789`. It preserves its 12-byte input budget and accepts
surrounding space, tab, CR and LF. Checked parsing separates failure from every
valid value. Its byte conversion fallback of 17 remains an explicit
application policy. Input and parsing failures return status 2 before output.

## Ordinary native consumers

The recent-value, sorted-median, frequency and distinct-sum samples parse with
`core::decimal::parse_T` and store primitive keys and values. Their bounded line
reader still provides i32 byte cells; each sample copies the actual returned
bytes into a packed buffer before parsing. Signed lines accept one optional
plus or minus, unsigned lines accept digits only, and both accept leading
zeros. Whitespace, CR, separators, sign-only input and overflow are rejected.
The existing 20-byte line limit and exit statuses are preserved.

Full-width collection samples retain their filenames containing `wide` because
they accept the full 64-bit range. They now use native i64/u64 values. Signed
and unsigned ordering, first-seen frequency order, duplicate identity and sums
modulo 2^64 remain unchanged. Sorted medians now use `alloc::vec` with explicit
mutation errors. Allocation denial returns status 4 before report output, and
every owner is destroyed on input, allocation and output failures.
Each of these 15 owned numeric consumers explicitly selects BrokenPipe Ignore
through `std::signal` as its first main action. A closed stdout pipe therefore
becomes checked EPIPE and status 5 after cleanup. Signal setup failure also
returns 5, before input or allocation. This is an executable-specific policy.

The expression calculator uses `core::i64::checked_mul` directly, retaining its
overflow diagnostics and batch output behavior. No workload generator imports
the removed numeric modules, so its generated programs need no numeric rewrite.

## Represented wide APIs and protected evidence

The two-word `core::wide_i64` / `wide_u64` APIs and their checked, bit, binary,
hex, host-I/O and reference fixtures remain supported separately. Their
algorithms, invalid-shift policy and public signatures are preserved. Only
`wide_u64`'s wrapping-u32 multiplication dependency and `hex_wide_u64`'s ASCII
hex dependency move to the corresponding canonical primitive helpers.

Dedicated factorial, fingerprint, radix and bit examples continue to exercise
represented arithmetic. The [native varint consolidation](stdlib-varint.md)
separately retires the three signed/two-word codec modules and migrates both
frame examples to core::varint with native u64/i64, typed Result/Decoded and
explicit errors. The native codec and migrated consumers have separate
executable acceptance. That change does not retire the wide arithmetic types
or extend historical numeric-migration receipts to the new API. Compiler-state historical
snapshots and hash manifests retain their historical paths. Compiler, runtime, formal and proof
sources are unchanged.

## Focused execution evidence

`tests/stdlib_numeric_migration_execution.rs` runs the retained numeric policy
fixtures, composition controls for hash/text/hex/arrays and represented-wide
arithmetic/hex, and real recent/median/frequency/distinct consumers. Native
cases include signed and unsigned extrema, high-word distinctions, zero,
leading signs and zeros, invalid input and bounded lines. Allocation denial is
injected at every allocation reached by each collection workload; traces match
every released address and size. Output failures are exercised through
`/dev/full` and a real closed-reader stdout pipe for all 15 owned numeric
consumers. A representative injected signal setup failure verifies status 5
before input and allocation.

`tests/stdlib_narrow_execution.rs` checks the converted narrowing fixture and
input-driven byte report, including the sentinel correction. The expression
calculator's existing independent checked arithmetic oracle covers its direct
native multiplication. Source-name coverage checks tied to the deleted helper
namespaces were removed; their behavioral fixtures remain executable.

The original five numeric migration groups, both narrowing/report tests, the
calculator oracle and the owned-string edit/trim fixture passed. The additional
gate passed for closed stdout pipes across all 15 owned numeric consumers and
one representative signal setup failure. Focused source-pack gates also passed
for primitive modules, trait obligations, represented ordering and
native helper execution. These packs explicitly include the canonical modules'
dependencies; the aggregate primitive pack also needed its previously missing
f32 memory/result dependencies. No compiler change was required. Logs are in
`target/stdlib-work/numeric-migration/`.
