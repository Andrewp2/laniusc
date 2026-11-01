# bc: integer expression calculator

`sample_programs/library/bc.lani` is a calculator in the style of `bc`. It
reads stdin and evaluates exact integer expressions with `alloc::big_int`. All
arithmetic runs in Lanius; no host integer library is used. It also uses
`ext::cli` for its options and `std::stream` for I/O.

```sh
target/release/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/bc.lani -o target/claude-work/bc
printf '2^128 - 1\nmodpow(3, 10^20, 1000000007)\n(-7) / 2\n' | target/claude-work/bc
```

The output is:

```text
340282366920938463463374607431768211455
139421235
-3
```

## Language

Each line holds one expression, and its value is printed on its own line.

- Blank lines and lines that hold only a `#` comment print nothing.
- A `#` starts a comment that runs to the end of the line.
- Space, tab and carriage return separate tokens.
- `quit` on its own line stops processing.

Operators, from lowest to highest precedence:

| Precedence | Operators | Meaning |
| --- | --- | --- |
| 1 | `\|` | Infinite two's complement OR |
| 2 | `&` | Infinite two's complement AND |
| 3 | `<<` `>>` | Left shift; arithmetic right shift (rounds toward negative infinity) |
| 4 | `+` `-` | Sum, difference |
| 5 | `*` `/` `%` | Product; quotient truncated toward zero; remainder with the dividend's sign |
| 6 | unary `-` `+` | Negation |
| 7 | `^` | Power, right associative |

The binary operators at levels 1 to 5 group left to right.

**Differences from POSIX `bc`:**

- `^` binds tighter than unary minus, as in Python and mathematics. So
  `-2^2` is `-4` and `(-2)^2` is `4`; POSIX `bc` gives `4` for `-2^2`.
- Bit operators and shifts are additions to the language.
- There is no `scale`; all values are integers. `/` and `%` match `bc` with
  `scale=0`: `-7/2` is `-3` and `-7%3` is `-1`.

Functions:

- `abs(a)`;
- `gcd(a, b)`, which is never negative;
- `modpow(a, e, m)`, which matches Python's `pow(a, e, m)`. The result has
  the modulus's sign. A negative `e` uses the modular inverse.
- `modinv(a, m)`, which matches Python's `pow(a, -1, m)`.

**Numbers** are runs of `0-9A-Z` in the input base. Digits above 9 must be
uppercase letters, as in `bc`; lowercase letters are reserved for function
names. Output always uses lowercase digits, a leading `-` for negative
values, and no prefix.

## Options

| Option | Default | Meaning |
| --- | ---: | --- |
| `--ibase N`, `-i N` | 10 | Input base, 2 to 36 |
| `--obase N`, `-o N` | 10 | Output base, 2 to 36 |
| `--max-limbs N` | 65536 | Maximum 32-bit limbs per integer |
| `--max-work N` | 1000000000 | Work budget for each library call |
| `--max-output N` | 1048576 | Maximum digits in one result |
| `--max-line N` | 1048576 | Maximum bytes in one input line |
| `--help`, `-h` | | Print usage and exit 0 |

The expression nesting depth is capped at 256. Deeper parentheses or unary
chains report `nesting-limit` instead of exhausting the native stack.

## Errors and exit status

A failing line prints nothing on stdout. It writes one diagnostic line to
stderr, and processing continues with the next line, like `bc` runtime
errors:

```text
bc: division-by-zero line=8 byte=1
```

Line numbers start at 1 and count blank lines. `byte` is the 0-based position
of the operator, function or token where the error occurred.

The error kinds are:

- `syntax-error`
- `invalid-digit` (a digit not below the input base)
- `unknown-function`
- `division-by-zero` (from `/`, `%` or a zero `modpow`/`modinv` modulus)
- `not-invertible`
- `negative-exponent`
- `invalid-exponent` (above `u32`)
- `invalid-shift` (negative or above `u64`)
- `nesting-limit`
- `limb-limit`
- `work-limit`
- `output-limit`
- `allocation-failure`

| Status | Meaning |
| ---: | --- |
| 0 | Every line succeeded |
| 1 | At least one line failed; the others were still evaluated |
| 2 | Invalid options |
| 3 | Fatal: an input line over `--max-line`, line-buffer allocation failure, or a native read/write failure |

## Verification

`tests/stdlib_bc_execution.rs` compiles the program through GPU code
generation and runs it as a native x86_64 Linux process. Its oracle,
`tests/oracles/bc_oracle.py`, generates deterministic expressions with
Python integers as the reference. It sends each radix pass through one
process and compares every stdout value and every stderr diagnostic (kind
and line number).

The checked operands straddle the Karatsuba threshold. They include zero,
negative values, all-ones and sparse limb patterns, and division by zero. On
2026-10-31 the oracle checked **9,735 values and 326 diagnostics** across
radices 10, 16, 2, 3, 7 and 36, including 378 modular inverses. The
[big integer guide](stdlib-big-integers.md#verification) lists the cases.

The test also checks precedence, comments, `quit`, base conversion,
diagnostic text and invalid options directly. The oracle needs `python3`;
the test does not use `strace`.

`tests/oracles/bc_million.py` checks seven operations on 1,000,000-digit and
500,000-digit operands against Python, and reports both times. With raised
limits, for example `--max-limbs 10000000 --max-work 18446744073709551615`, a
million-digit round trip takes about 31 s, against 0.9 s in Python. The
[guide](stdlib-big-integers.md#million-digit-oracle) has the full table.
