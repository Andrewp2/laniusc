# Arbitrary precision calculator

`sample_programs/library/bigcalc.lani` is a native streaming calculator built from
`ext::big_int`, `ext::big_uint`, `ext::cli`, `alloc::vec`, `std::args`, and
`std::stream`. Its operands and results use owned arrays of limbs. Arithmetic
executes in Lanius; the program does not call a host integer library.

Build and run from the repository root:

```sh
cargo run -- --stdlib-root stdlib --source-root extended \
  sample_programs/library/bigcalc.lani -o /tmp/bigcalc
chmod +x /tmp/bigcalc
printf 'add 18446744073709551616 1\ndivmod -17 5\nedivmod -17 -5\n' | /tmp/bigcalc
```

The output is:

```text
18446744073709551617
-3 -2
4 3
```

## Input and output

Each stdin line is one command, `OP LEFT RIGHT`. The unary commands `abs`, `neg`,
and `not` take only `LEFT`. ASCII space, tab, and carriage return separate tokens;
line feed ends the record. Blank lines are accepted. EOF also ends the last
record. There are no comments, quotes, or escapes.

An operand is an optional `+` or `-`, followed by one or more digits in the
selected radix. Both letter cases are accepted. Prefixes such as `0x`, digit
separators, decimal points, NUL, and other bytes are rejected. Results use lower
case letters, no leading `+`, and no leading zeroes. Zero always prints `0`.

| Command | Result |
| --- | --- |
| `add A B`, `sub A B`, `mul A B` | Sum, difference, product |
| `div A B`, `rem A B`, `divmod A B` | Quotient, remainder, or both; quotient truncates toward zero |
| `ediv A B`, `erem A B`, `edivmod A B` | Euclidean quotient, remainder, or both |
| `cmp A B` | `-1`, `0`, or `1` for less, equal, or greater |
| `shl A B`, `shr A B` | Shift left or arithmetic shift right by `B` bits |
| `and A B`, `or A B`, `xor A B`, `not A` | Infinite two's complement bit operations |
| `abs A`, `neg A` | Absolute value or negation |
| `gcd A B` | Nonnegative greatest common divisor; `gcd 0 0` is zero |
| `pow A B` | Integer power; `0^0` is one |

Truncating division satisfies `A = Q*B + R`, `abs(R) < abs(B)`, and a nonzero
remainder has the sign of `A`. Euclidean division satisfies the same identity
with `0 <= R < abs(B)`, including when the divisor is negative. Dividing by zero
is an error.

Shift counts use the selected radix too. They must be nonnegative and fit in
`u64`. An arithmetic right shift rounds negative values toward negative infinity;
for example, `shr -17 2` prints `-5` in decimal. A shift count may exceed the
operand's bit length. Exponents also use the selected radix and must fit in
`u32` (0 through 4294967295). Powers still obey limb and work limits.

Each answer occupies one line. `divmod` and `edivmod` print `Q R`, with one space.
Comparison results use the selected radix like every other result. Operands come
from stdin so their size is independent of native argument storage limits.

## Options and limits

Only options appear on the command line. For example:

```sh
printf 'mul ffffffffffffffff 10\n' | /tmp/bigcalc --radix=16
printf 'shl 1 100000\n' | /tmp/bigcalc --max-limbs 4000 --max-output 40000
```

| Option | Default | Meaning |
| --- | ---: | --- |
| `--radix N`, `-r N` | 10 | Input and output radix, 2 through 36 |
| `--max-limbs N` | 32768 | Maximum limb count for each big integer; each limb holds 32 bits |
| `--max-work N` | 100000000 | Work budget passed to each provider call |
| `--max-output N` | 1048576 | Maximum bytes in one output record, including sign, separator, and newline |
| `--max-line N` | 1048576 | Maximum input bytes before a line feed; a carriage return counts |
| `--help`, `-h` | | Print usage and exit |

Options accept `--name N` and `--name=N`; the last repeated value wins. Values are
unsigned decimal integers. Work accepts the full `u64` range; limb count accepts
0 through 536870911; line and output sizes accept 0 through 2147483647. Argument
capture allows 32 tokens totaling 8192 bytes. These limits concern option text,
not operands.

Work limits follow the provider contract: each parse, arithmetic operation, and
format call receives the configured budget. The budget starts afresh for each
call and record; it is not a total instruction count for the process. Signed
operations may call several unsigned primitives. Line scanning and native I/O
are outside that work budget and are bounded per record by `--max-line` and
`--max-output`. The process accepts an unlimited number of records and retains
only a reusable input buffer and the current record's owners. Buffer growth can
reserve spare capacity, and arithmetic can own temporary integers as well as its
inputs and outputs. These options do not specify a total process memory limit.

All successful values for a record are formatted before the program writes that
record. A malformed operand, exceeded output limit, or allocation failure emits
none of the current answer. Earlier successful answers remain visible. A native
write can transfer a prefix before failing, so an I/O error may leave a partial
answer. The program stops at the first error and releases all current owners.

## Exit status and diagnostics

| Status | Meaning |
| ---: | --- |
| 0 | Every consumed record succeeded, or help was written |
| 2 | Invalid options, unknown operation, wrong arity, or malformed operand |
| 3 | Input line, limb, output, or storage capacity limit |
| 4 | Provider work limit |
| 5 | Allocation failure |
| 6 | Native read, write, or diagnostic write failure |
| 7 | Division by zero, invalid shift count, or invalid exponent |

Errors attempt a single allocation-free stderr diagnostic, for example:

```text
bigcalc: invalid-operand line=3 byte=6 operand=2
```

Line numbers start at 1, including blank lines. Byte positions start at 0 within
the original line. Operand numbers are 1 or 2. Missing operands point to the end
of the line; excess operands point to their first byte. Provider failures point
to the relevant operand start during parsing or operation start during arithmetic
and formatting. Division-by-zero, invalid-shift, and invalid-exponent diagnostics identify the right
operand. Argument diagnostics use `argument=N` and `byte=N`; argument 0 is
the first option after the executable. If writing the diagnostic itself fails,
the final status is 6.

## Verification

`tests/extended_bigcalc_execution.rs` compiles the real sample through GPU code
generation and executes the resulting x86_64 Linux program. It compares signed
arithmetic, both division modes, comparisons, shifts, bit operations, powers, and
greatest common divisors with
Python integers using a fixed seed in radices 2, 3, 10, 16, 35, and 36. Its large
operand workload uses 4000 and 1900 decimal digits, including multiplication and
both division modes, and reports native wall time including process startup.
Python is used only by the test oracle. One local run on 2026-10-23 processed
29543 input bytes and 21912 output bytes in 1.25 seconds; this is an observation,
not a throughput guarantee.

The focused suite also checks binary malformed input, positional diagnostics,
blank lines, CRLF, EOF, arity, radix and resource boundaries, prior-record output,
and help. On Linux it traces every allocation in a Euclidean `divmod` record,
denies each observed allocation in turn, and checks that all successful mappings
are unmapped exactly once. It injects read and write failures, zero-progress
writes, interrupted calls, and a stderr failure, and checks cleanup. The suite
requires `python3` and `strace`.

The execution evidence is for x86_64 Linux. GPU compilation is not evidence of
GPU kernel execution, and the sample's native descriptor adapters target Linux.
