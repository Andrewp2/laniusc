# Table-driven Pratt parsing

`ext::pratt` parses operator expressions by binding power. The caller declares
token kinds in a table and passes a slice of tokens. The parser writes postfix
(reverse Polish) events to fixed-capacity storage. It allocates nothing while
parsing, never recurses natively, and needs no function values: the caller's
evaluator, tree builder or code generator consumes the events.

It complements [`ext::parse`](extended-parse.md) cursors and
[`ext::lexer`](extended-lexer.md) tokens. Precedence, associativity, prefix,
postfix, grouping and calls come from data, not from a hand-written precedence
loop like the one in `expr_calc.lani`.

The design follows Pratt's top-down operator precedence, in the binding-power
formulation of
[matklad's "Simple but Powerful Pratt Parsing"](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html).
The recursion is replaced by an explicit operator stack.

## API

```lani
let t = ext::pratt::table(KINDS).unwrap();       // kinds 0..KINDS-1, all unassigned
t.atom(INT); t.infix(ADD, 9, 10); t.prefix(SUB, 13); t.infix(POW, 15, 14);
t.group(OPEN, CLOSE); t.call(OPEN, CLOSE, COMMA, 17);
let p = ext::pratt::parser(4096).unwrap();       // fixed token capacity
let count = p.parse(t.borrow(), tokens.as_view()).unwrap();
// p.event(i): Event { role, kind, token, arity } for i in 0..count
p.destroy(); t.destroy();
```

| API | Contract |
| --- | --- |
| `table(kinds) -> Result<Table, Error>` | Allocate one unassigned spec per kind; kinds is 1..65536. |
| `Table.atom(kind)` | Complete operand, such as a number or name. |
| `Table.prefix(kind, right)` | Prefix operator. Its operand continues while later left powers exceed `right`. |
| `Table.infix(kind, left, right)` | Binary operator. `left < right` associates left, `left > right` associates right. |
| `Table.postfix(kind, left)` | Postfix operator, such as `!`. |
| `Table.group(open, close)` | Parentheses in operand position. They emit no event. |
| `Table.call(open, close, separator, left)` | Call or index in operator position: callee, then each argument, then one `CALL` event. `f()` has arity 0. |
| `Table.kind_count()`, `destroy()` | Inspect and release the table. |
| `parser(capacity) -> Result<Parser, Error>` | Reserve event and stack storage for `capacity` tokens (0..16777216). |
| `Parser.parse(&Table, View<Token>) -> Result<i32, Error>` | Parse one complete expression; return the event count. |
| `Parser.event_count()`, `event(i)`, `events()` | Read the last successful parse. |
| `Parser.capacity()`, `destroy()` | Inspect and release scratch; a destroyed parser has capacity 0. |

Powers are 1 through 1,000,000. The table methods return the kind on success.
`Token { kind, start, end }` is caller data: the parser reads only `kind`, and
events refer back to tokens by index. `Event.role` is `ATOM`, `PREFIX`,
`INFIX`, `POSTFIX` or `CALL`, with `arity` 0, 1, 2, 1 or the argument count.
For `CALL`, `token` is the opening token. The events are in postorder, so an
evaluator pops `arity` values (plus the callee for `CALL`) and pushes one
result.

A kind can have at most one operand-position role (atom, prefix or group
opening) and at most one operator-position role (infix, postfix, call opening,
separator or closing). That lets `-` be both prefix and infix, and `(` both a
group and a call. Any other combination returns `Conflict(kind)` and leaves the
table unchanged. One closing kind can serve several groups and calls.

## Parsing rule

The parser alternates between expecting an operand and expecting an operator.
Before an infix, postfix or call token with left power `L` is pushed, every
pending prefix or infix operator whose right power `R` satisfies `R >= L` is
emitted. A group or call frame stops this. With matklad's convention of
distinct powers (`(1,2)` for left-associative `+`, `(15,14)` for
right-associative `**`), this matches the recursive formulation exactly. On
equal powers, the earlier operator wins.

A separator emits pending operators back to the nearest call. Outside a call
it is `MisplacedSeparator`. A closing token emits pending operators, then must
match the nearest group or call. A trailing separator, as in `f(1,)`, is
`ExpectedOperand`.

| Error | Meaning (token index unless noted) |
| --- | --- |
| `InvalidKind(kind)`, `InvalidPower(power)`, `Conflict(kind)` | Table construction. |
| `AllocationFailed` | `table` or `parser` allocation; partial owners are released. |
| `Bounds` | Invalid parser capacity or token view metadata. |
| `WorkspaceTooSmall` | More tokens than the capacity, or a destroyed parser. |
| `UnknownToken(i)` | Token kind outside the table. |
| `ExpectedOperand(i)`, `ExpectedOperator(i)` | Token has no role in the current position. |
| `UnexpectedEnd(n)` | Input ended where an operand was required; `n` is the token count. |
| `Unmatched(i)` | Closing token without a matching opener of that kind. |
| `Unclosed(i)` | Input ended inside the group or call opened at token `i`. |
| `MisplacedSeparator(i)` | Separator outside a call. |

After an error, no events remain, and the parser can be reused.

## Cost and ownership

Each token is examined once. It causes at most one push and at most one event.
Parsing is therefore O(n) time over a fixed workspace of two vectors sized to
the capacity, with no allocation or native recursion. Copying a `Table` or
`Parser` aliases its storage. Destroy the one active owner; repeated
destruction is harmless. Fields are public only because the language lacks
opaque fields.

## Sample: Python-precedence calculator

`sample_programs/library/pratt_calc.lani` reads stdin lines. It tokenizes each
line with five `ext::lexer` rules and parses with a table that encodes
Python's grammar:

```text
|  <  ^  <  &  <  << >>  <  + -  <  * // %  <  unary - + ~  <  **  <  call
```

`**` has left power 15 and right power 14, around unary minus at 13. As in
Python, `-2**2` is `-(2**2)`, `2**-1` parses, and `2**3**2` is `2**(3**2)`.
The program evaluates the events in checked i64. `//` and `%` floor.
`abs(x)`, `min(a, b, ...)` and `max(a, b, ...)` are calls. Each line prints
either a decimal value or `error N`, where N is:

| N | Class |
| ---: | --- |
| 1 | syntax (lexing or parsing) |
| 2 | overflow, including literals outside i64 |
| 3 | division or modulo by zero |
| 4 | negative exponent or shift count |
| 5 | function name used as a value, or a call on a non-function |
| 6 | wrong argument count |
| 7 | more than 4,096 tokens on a line |

```sh
printf '1+2*3\n-2**2\n2**3**2\nmax(1,7,3)+abs(-4)\n7//-2\n1//0\n' | pratt-calc
```

```text
7
-4
512
11
-4
error 3
```

## Verification

`tests/fixtures/extended/pratt_oracle/contracts.lani` checks table conflicts
and invalid powers. It also checks the exact event order for associativity,
prefix and postfix powers, empty and nested calls, the token index of every
error kind, reuse after errors, and the capacity and destroyed-parser
rejections.

`tests/fixtures/extended/pratt_oracle/oracle.py` compares `pratt_calc` with
CPython on seeded generated lines. The tree shape comes from CPython's own
parser (`ast.parse(line, mode="eval")`), never from `ext::pratt`'s table. A
small evaluator over that tree applies the same i64, floor and error rules, in
postorder. There are two families of lines:

- 20,000 well-formed expressions over every operator, nesting up to six deep,
  with random spacing, parentheses, calls (8% of them with the wrong arity)
  and literals near the i64 limits;
- 5,000 lines of random token soup. Most are syntax errors on both sides. Soup
  with `,` directly before `)` is expected to be a syntax error, because
  CPython accepts that trailing comma and this table does not. Tuple syntax
  such as `()` is also a syntax error before any evaluation.

`tests/extended_pratt_execution.rs` runs both. Results on native Linux x86_64
with CPython 3.12.3 are under Receipts below.

## Receipts

These receipts are for `extended/ext/pratt.lani` SHA256 `111858be...`,
`pratt_calc.lani` SHA256 `febeead3...` and oracle SHA256 `e7ebe75c...`. The
executables were built with the prebuilt `target/release/laniusc`, rebuilt with the resident
`target/claude-work/bin/lcc` (same results), and ran on
native Linux x86_64. Log: `target/claude-work/s3/pratt-receipt.log`.

| Seed | Well-formed | Token soup | Wall time |
| ---: | ---: | ---: | ---: |
| 20261031 | 20,000/20,000 | 5,000/5,000 | 8.35 s |
| 1 | 20,000/20,000 | 5,000/5,000 | 8.66 s |
| 2 | 20,000/20,000 | 5,000/5,000 | 9.18 s |
| 3 | 20,000/20,000 | 5,000/5,000 | 7.38 s |
| 4 | 20,000/20,000 | 5,000/5,000 | 7.14 s |
| Total | 100,000/100,000 | 25,000/25,000 | |

For the default seed, 14,938 well-formed lines yield values. The rest are
4,091 overflows, 307 zero divisors, 365 domain errors and 299 arity errors.
The soup lines are 4,745 syntax errors, 136 name errors, 118 values and 1 zero
divisor. The contract fixture exits 0.

Two oracle mistakes were fixed during bring-up, with no change to the Lanius
code:

- `ast.parse` rejects leading blanks, which `eval` strips.
- A `()` tuple must be a syntax error before evaluation. Without that check,
  the oracle reported an arity error from an earlier `abs()` instead.

Lexing dominates the sample's cost. `ext::lexer` probes every rule's regex at
each position. With one rule per operator (18 rules), 0.9 MB of expressions
took 15.6 s of user time. Folding the operators into five rules cut that to
5.0 s. The Pratt parse itself is linear and allocation-free. These are local
observations on a loaded laptop, not throughput claims. The Cargo test file
was not built for these receipts.
