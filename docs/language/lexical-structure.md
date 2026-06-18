# Lanius Lexical Structure

This chapter describes the source tokens accepted by the current
`unstable-alpha` lexer. It is the language-facing companion to
`lexer::tables::dfa`, `lexer::tables::tokens`, and the test CPU lexer oracle.
Use [Syntax reference](syntax.md) for grammar forms built from these tokens.
Use [Literals and operators](literals-and-operators.md) for the user-facing
semantic and backend boundaries for literal tokens and operator spellings.

Lexical recognition is not a full language support claim. Parser retags,
semantic records, diagnostics, type checking, and backend lowering decide
whether a token sequence is accepted as a supported program.

## Source Text

The lexer reads source as bytes. Token spans are byte offsets and byte lengths,
not character indices.

The current identifier and keyword frontier is ASCII. Identifier starts are
`A` through `Z`, `a` through `z`, and `_`. Later identifier bytes can also be
`0` through `9`.

Non-ASCII source bytes can appear inside string and char token bodies. The
lexer does not document non-ASCII identifiers in the current slice.

## Whitespace

Whitespace tokens are recognized and skipped before parsing. The current
whitespace bytes are:

- space
- tab
- carriage return
- line feed

Whitespace separates tokens when two adjacent token bodies would otherwise be
read as one token.

## Comments

Line comments start with `//` and continue until a line feed.

```lanius
// This is a line comment.
```

Block comments start with `/*` and end at the first following `*/`.

```lanius
/* This is a block comment. */
```

Block comments are not documented as nested. Comments are skipped before the
parser consumes tokens, but skipped comment boundaries still matter to the
lexer because later token spans use byte offsets in the original source.

## Identifiers

An identifier starts with an ASCII letter or `_`, followed by zero or more
ASCII letters, ASCII digits, or `_`.

```text
value
_scratch
value2
VALUE_NAME
```

The lexer first recognizes keyword-shaped text through the identifier path and
then retags exact keyword bytes as keyword tokens. A keyword is not an ordinary
identifier in grammar positions that expect an identifier token.

## Keywords

The current keyword set is:

```text
break const continue else enum extern false fn for if impl import in let match
module pub return self struct trait true type where while
```

The language does not currently document contextual keyword reuse. If a source
form needs to use one of these spellings as a name, check the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md) and the
owning grammar/parser tests before treating it as supported.

## Integer Literals

The lexer recognizes these integer literal families:

| Family | Examples |
| --- | --- |
| Decimal | `0`, `1`, `123`, `1_000` |
| Hexadecimal | `0xFF`, `0Xff`, `0xCAFE_BABE` |
| Binary | `0b1010`, `0B1010_0101` |
| Octal | `0o755`, `0O7_5_5` |

Underscores separate digits inside numeric bodies. They are not documented as
valid leading or trailing characters for a literal family.

Numeric type selection is a later semantic question. The lexer classifies the
source span as an integer token; type checking decides whether the literal fits
the expected type.

## Float Literals

The lexer recognizes decimal float spellings with a dot or exponent:

```text
1.0
1.
.5
1e3
1E-3
1.5e+2
```

Underscores can separate digits in the fractional or exponent digit runs:

```text
1_000.25
1.25_00
1e1_0
```

The lexer treats range frontiers specially so range expressions are not stolen
by float tokenization. For example, `1..end` is tokenized as an integer, a
range token, and an identifier rather than as a float followed by a dot.

## String Literals

String literals are double-quoted:

```lanius
"hello"
"escaped \" quote"
```

Inside a string token, a backslash escapes the following byte. A line feed ends
the token unsuccessfully rather than becoming part of a normal string body.

The lexer recognizes string token boundaries only. Escape meaning, string
storage, allocation, and runtime behavior are later language/runtime questions.

## Char Literals

Char literals are single-quoted:

```lanius
'x'
'\n'
```

Inside a char token, a backslash escapes the following byte. A line feed ends
the token unsuccessfully.

The lexer does not by itself document Unicode scalar validation or exactly-one
character semantics. Later phases own the meaning of the char token payload.

## Punctuation And Operators

The source lexer recognizes these punctuation and operator spellings before
parser-context retags:

```text
( ) [ ] { }
, ; : ? .
+ - * / % ^ ~ ! & |
= == != < > <= >= <> << >> && ||
-> => .. ++ --
+= -= *= /= %= ^= &= |= <<= >>=
```

The parser grammar documents which of these spellings are valid source
expressions or item syntax. For example, the lexer recognizes `++` and `--`
tokens, but [Syntax reference](syntax.md) does not document increment or
decrement expressions as part of the current expression grammar.

## Ranges

The lexer recognizes `..` as a range token. The parser and token-front-end
context recognize inclusive ranges with the source spelling `..=`.

Examples:

```lanius
0..10
0..=10
..end
```

The exact range expression forms are documented in
[Syntax reference](syntax.md#for-ranges). Execution support belongs to the
generated language slice and backend evidence.

## Parser-Context Retags

Many token names in `TokenKind` are not direct source spellings. They are
parser-context retags used to keep the GPU parser and HIR passes explicit about
roles such as:

- call, group, array, and index delimiters
- parameter-list delimiters
- type positions
- declaration-name positions
- path generic arguments
- field separators
- statement semicolons
- trait and impl method boundaries

Do not infer a source token spelling from every `TokenKind` variant. The
language-facing spelling is owned by this chapter and
[Syntax reference](syntax.md); the internal token namespace is documented in
[Lexer](../compiler/lexer.md) and
[Grammar and generated tables](../compiler/grammar-and-tables.md).

## Invalid Tokens

If the byte stream reaches the lexer reject state or ends inside an unfinished
token, lexing fails before parser structure exists. Later compiler layers should
turn that failure into a stable diagnostic with a useful source span whenever
the failure reaches a user-facing compile path.

Examples of lexical forms that are not documented as valid:

- unterminated block comments
- unterminated strings
- unterminated char literals
- numeric prefixes without required digits, such as `0x`
- identifiers that start with a digit
- non-ASCII identifiers

## Update Rule

Update this chapter when the lexer DFA, token namespace, keyword retags,
numeric frontier handling, comment handling, string/char handling, or
parser-context retag boundary changes in a way users could observe. Update
[Syntax reference](syntax.md) when the grammar changes, and update the
generated slice when support evidence changes.
