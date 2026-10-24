# Checked integer expression calculator

`sample_programs/library/expr_calc.lani` is a native stdin calculator written in
Lanius. It consumes `ext::parse` for checked UTF8 cursor scanning, const generic
`core::vec` for bounded value and operator stacks, `core::format` for typed
runtime formatting, `ext::cli` for options, and the existing checked integer
arithmetic, owned byte vector, and descriptor I/O modules. The execution test
compiles this source to an x86_64 Linux executable through GPU code generation;
Python is used only as an independent test oracle.

Each LF or CRLF record contains one expression. EOF can terminate the final
record. Empty records and records containing only space, tab, vertical tab, or
form feed are ignored. These four ASCII whitespace characters can also separate
tokens. A carriage return is accepted only immediately before a terminating LF;
Unicode whitespace, NUL, identifiers, hexadecimal prefixes, separators, decimal
points, and exponent syntax are rejected. Every record must be valid UTF8, even
when an earlier byte would already make its expression invalid.

```text
1 + 2 * 3                  => 7
(1 + 2) * 3                => 9
-7 / 3                     => -2
-7 % 3                     => -1
-(10 - 3) * +(+2)           => -14
-9223372036854775808         => -9223372036854775808
```

The grammar is:

```text
expression = product { ("+" | "-") product }
product    = unary { ("*" | "/" | "%") unary }
unary      = ("+" | "-") unary | primary
primary    = decimal | "(" expression ")"
decimal    = ASCII_DIGIT { ASCII_DIGIT }
```

Parentheses group expressions, unary signs bind most tightly and associate to
the right, multiplication/division/remainder share the next precedence level,
and addition/subtraction share the lowest level. Binary operations associate to
the left. Adjacent values or parentheses require an explicit operator.

Every intermediate value must fit signed 64 bits. Decimal magnitudes through
9223372036854775807 are accepted; the magnitude 9223372036854775808 is accepted
only directly under the innermost unary minus, with optional whitespace between
the sign and digits. This rule admits the minimum signed value without first
creating an unrepresentable positive integer. For example, `+-9223372036854775808`
succeeds, while `-+9223372036854775808`, `--9223372036854775808`, and
`-(9223372036854775808)` fail. Leading zeroes are permitted.

Division truncates toward zero. Remainder has the dividend's sign when nonzero,
and `A = (A / B) * B + (A % B)`. Both division and remainder reject a zero
divisor and the signed minimum divided by -1. Addition, subtraction,
multiplication, and unary minus reject overflow. Unary plus preserves its value.

The parser uses iterative operator and value stacks; nesting and unary chains
do not recurse. Each operator records its original byte offset for diagnostics.
Stack push errors are handled explicitly. Checked addition, subtraction and
multiplication come from `core::i64`. Division and remainder check exceptional operands before native
integer operations.

## Options and limits

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/expr_calc.lani -o target/stdlib-work/expr-calc
printf '1+2*3\n-(5+6)\n' | target/stdlib-work/expr-calc --max-stack=64
```

| Option | Default | Meaning |
| --- | ---: | --- |
| `--max-input N` | 1048576 | Total bytes read from stdin, including CR and LF |
| `--max-line N` | 65536 | Bytes in one record before LF, including any trailing CR |
| `--max-output N` | 1048576 | Total staged result bytes, including newlines |
| `--max-stack N` | 256 | Maximum live entries in each operator and value stack |
| `--max-work N` | 1000000 | Cursor work budget and evaluation action budget per record |
| `--help`, `-h` | | Print usage |

Options take unsigned decimal values using `--name N` or `--name=N`; the last
repetition wins. Sizes accept 0 through 2147483647, stack capacity accepts 0
through 256, and work accepts 0 through 18446744073709551615. Native argument
capture permits 32 option tokens totaling 8192 bytes. The input expressions come
from stdin and do not use this argument storage.

The cursor's work budget includes UTF8 validation and token operations, following
`ext::parse` accounting. A separate evaluation budget charges one action for
each non-whitespace token and each operator reduction. Both start fresh for each
record. Input scanning and formatting are bounded by the byte limits; the fixed
result and diagnostic format strings use the formatter's default work budget.
The work option is not a native instruction counter. The program retains one
reusable record buffer and the full staged result buffer; vector growth can
reserve spare capacity. Limits constrain logical sizes rather than exact total
process memory.

All results remain staged until EOF and every record has succeeded. A late
syntax, arithmetic, limit, allocation, or read failure emits no stdout, including
answers from earlier records. Each record is fully validated before its result
is added to staging. Only the final stdout write can expose partial output if a
native write fails after transferring a prefix. Every error releases the input,
output, and argument owners before attempting its allocation-free stderr
message.

## Diagnostics

| Status | Meaning |
| ---: | --- |
| 0 | All records succeeded, or help was written |
| 2 | Invalid arguments, malformed expression, unmatched parentheses, or invalid UTF8 |
| 3 | Input, line, output, or stack capacity limit |
| 4 | Work limit |
| 5 | Allocation failure |
| 6 | Read, write, or diagnostic write failure |
| 7 | Arithmetic overflow or division by zero |

```text
expr_calc: division-by-zero line=3 byte=5
```

Line numbers start at 1. Byte offsets start at 0 within the original record;
UTF8 errors identify the start of the malformed sequence. Syntax errors point
to the unexpected token or to the record's end if an operand is missing.
Unmatched opening parentheses point to their opening byte. Arithmetic errors
point to their operator; literal range errors point to the first digit. Resource
errors identify the input or operation being processed. Command-line errors use
line 0; their byte field is an option-value offset when available. If writing the
diagnostic fails, the final status is 6.

## Verification

`tests/extended_expr_calc_execution.rs` executes the real native sample. A fixed
seed generates expression trees with mixed signs, parentheses, precedence,
integer extremes, division, and remainder. An independent Python recursive
parser checks the same signed-64 intermediate-value contract, using
`fractions.Fraction` for exact truncating division. The suite checks grammar and
binary malformed input, original byte/line diagnostics, all configured limits,
option boundaries, minimum-value lexing, LF/CRLF/EOF, and whole-input output
staging after late failure.

Linux `strace` tests deny every observed allocation in turn and check that every
successful mapping is unmapped exactly once. They inject read/write failures,
interrupted operations, zero-progress writes, a short write, and a stderr
failure. A 5000-expression mixed batch reports native elapsed time after compile
has completed, including process startup. One run on 2026-10-23 processed 83,801 input bytes and 41,417 output bytes
in 132 ms. This is an observation, not a throughput guarantee. The tests require
`python3` and `strace`. The evidence covers x86_64 Linux native execution; GPU
code generation does not establish GPU kernel execution.
