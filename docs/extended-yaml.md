# YAML 1.2 reading and writing with JSON trees

`ext::yaml` reads YAML 1.2 documents into [`ext::json_tree`](extended-json-patch.md) trees, resolving plain scalars with the YAML 1.2 core schema. It covers:

- block and flow sequences and mappings, including indentless sequences, compact nested collections and explicit `?` keys;
- plain, single-quoted and double-quoted scalars, and literal (`|`) and folded (`>`) block scalars with chomping (`-`, `+`) and indentation indicators;
- anchors and aliases, with a limit on alias expansion;
- comments, directives, `---` and `...` markers and multiple documents.

[`ext::yaml_writer`](#writing) writes trees back as block-style YAML that YAML 1.1 and 1.2 readers both read back exactly. Both modules are in the `extended` source root.

## API

```text
ext::yaml::load(source: [u8], start: i32, count: i32, limits: Limits) -> Result<ext::json_tree::Tree, Error>
ext::yaml::load_all(source: [u8], start: i32, count: i32, limits: Limits) -> Result<ext::json_tree::Tree, Error>
ext::yaml::default_limits() -> Limits   // max_depth 256, max_nodes 16,777,216, max_alias_nodes 1,000,000
ext::yaml::kind_name(kind: ErrorKind) -> Text
```

- **`load`** reads a stream that holds at most one document. An empty stream, or one with only comments, gives `null`. A second document is `MultipleDocuments`.
- **`load_all`** gives an array with one element per document, so an empty stream gives `[]`.
- **Errors:** `Error` is `{ kind, line, column, offset }`. `line` and `column` count from 0 in Unicode scalars, and `offset` is a byte offset from `start`. `kind` is one of:
  - `Syntax`
  - `InvalidCharacter`: bad UTF-8, or a character outside the YAML printable set (C0 controls other than tab, LF and CR, DEL, C1 controls other than NEL, surrogates, U+FFFE and U+FFFF)
  - `InvalidEscape`
  - `Unsupported`
  - `UnknownAlias`
  - `RecursiveAlias`: an alias to a node that is still open, such as `&a [*a]`
  - `AliasLimit`
  - `DuplicateKey`
  - `NonScalarKey`
  - `NonFinite`: `.inf` or `.nan`, which JSON cannot hold
  - `InvalidTag`: `!!str` on a collection
  - `MultipleDocuments`
  - `DepthLimit`
  - `NodeLimit`
  - `AllocationFailed`
- **Limits:**
  - `max_depth` bounds collection nesting: `[[[1]]]` needs 3.
  - `max_nodes` bounds the nodes of the result tree, including `load_all`'s document array.
  - `max_alias_nodes` bounds the nodes that alias expansion copies, summed over the stream. Each alias copies its anchored node, so a "billion laughs" document stops with `AliasLimit` after copying at most this many nodes.

## Values

| YAML | JSON |
| --- | --- |
| `null`, `Null`, `NULL`, `~`, an empty node | `null` |
| `true`, `True`, `TRUE`, `false`, `False`, `FALSE` | booleans |
| `[-+]?[0-9]+` | the integer, without a `+` or leading zeros, at any size |
| `0o[0-7]+`, `0x[0-9a-fA-F]+` | the integer in decimal |
| `[-+]?(\.[0-9]+\|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?` | the number, with its digits kept: `.5` becomes `0.5` and `1.` becomes `1` |
| `[-+]?\.(inf\|Inf\|INF)`, `\.(nan\|NaN\|NAN)` | `NonFinite` |
| any other plain scalar, and every quoted or block scalar | a string |
| sequences, mappings | arrays, objects |

- **Tags:** `!!str`, `!<tag:yaml.org,2002:str>` and the non-specific `!` make a scalar a string. Any other tag, and the `%TAG` directive, are `Unsupported`.
- **Keys:** a scalar key becomes the JSON text of its value, so `1.50: a` gives the key `"1.50"`, `null: a` gives `"null"`, and `true: a` gives `"true"`. A collection key is `NonScalarKey`, and a repeated key, compared after this conversion, is `DuplicateKey`.
- **Anchors:** an anchor name runs to a blank or a flow indicator. An anchor may be redefined, and an alias uses the most recent definition. Anchors do not carry over to the next document.
- **Directives:** `%YAML 1.x` is accepted and other major versions are `Unsupported`. Directives other than `%YAML` and `%TAG` are ignored.
- **Tabs** separate tokens within a line and may appear inside scalars. A tab in the indentation of a block-context line before a token is `Syntax`. So is a tab before the indentation column on a plain scalar's continuation line. 1.2 indents with spaces only.
- **Escapes:** double-quoted scalars take the YAML escapes: `\0 \a \b \t \n \v \f \r \e \  \" \/ \\ \N \_ \L \P`, `\xXX`, `\uXXXX`, `\UXXXXXXXX` and an escaped line break. A `\u` high surrogate followed by a `\u` low surrogate is one character. A lone surrogate, or a code point above U+10FFFF, is `InvalidEscape`.
- **Byte order mark:** a UTF-8 byte order mark at the start is skipped.

## YAML 1.1 and 1.2

PyYAML implements YAML 1.1, so a few documents read differently there. The oracle checks each of these against the expected `ext::yaml` result written by hand, and also checks that PyYAML really does read them differently:

| Document | `ext::yaml` (1.2) | PyYAML (1.1) |
| --- | --- | --- |
| `yes`, `no`, `on`, `off`, `y`, `n` | strings | booleans |
| `010` | 10 | 8 (octal) |
| `0o17` | 15 | the string `"0o17"` |
| `0b101`, `1_000`, `0x_1F` | strings | 5, 1000, 31 |
| `1:20`, `20:03:20` | strings | 80, 72200 (base 60) |
| `1e3`, `1.5e3` | numbers | strings (1.1 floats need a dot and a signed exponent) |
| `-.5`, `+.5e+1` | numbers | strings |
| `2001-12-14` | a string | a date |
| `=` | a string | an error (the 1.1 value key) |
| `<<: *base` | an ordinary key `"<<"` | a merge |
| `! 12` | the string `"12"` | 12 |
| `a:\tb`, `a: 1\t# c` | `{"a":"b"}`, `{"a":1}` | errors (tabs) |
| A tab after the indentation of an empty line in a plain scalar | accepted | an error |
| `[a?b]` | `["a?b"]` | an error |
| `&a.b x` | `"x"` | an error (the anchor name) |
| An anchor defined twice | the later one wins | an error |
| `a\n...\nb` | two documents | an error |
| `a: \x85b` (NEL) | the string `"\u0085b"` | a line break |

Policy differences that are not about the version:

| Document | `ext::yaml` | PyYAML |
| --- | --- | --- |
| `a: 1\na: 2` | `DuplicateKey` (1.2 requires unique keys) | the last value |
| `!!int 3`, `!!map {}`, `!foo x` | `Unsupported` | the tagged value, or an error for an unknown tag |
| `.inf`, `.nan` | `NonFinite` | a float |
| `&a [*a]` | `RecursiveAlias` | a recursive list |
| `"\ud83d\u0041"` | `InvalidEscape` | two characters |

## Execution evidence

[`tests/fixtures/extended/yaml/oracle.py`](../tests/fixtures/extended/yaml/oracle.py) compares [`batch.lani`](../tests/fixtures/extended/yaml/batch.lani), compiled with `lcc`, against PyYAML 6.0.1 (`yaml.safe_load_all`). Values are compared as JSON: integers exactly, floats as binary doubles, strings exactly.

| Group | Cases | Agree |
| --- | --- | --- |
| Hand-written agreement cases: YAML 1.2 chapter 2 examples and one or more per feature | 87 | 87 |
| 1.1 and 1.2 differences and policy, against hand-written expectations | 32 | 32 |
| Error kinds, each also rejected by PyYAML unless the case is a policy difference | 56 | 56 |
| Depth, node, alias-expansion and single-document limits | 12 | 12 |
| Generated documents | 3,000 | 3,000 |

**Generated documents:**
- The generator builds a value first. It then writes the value as one to three documents, mixing block and flow collections, indentless and compact sequences, every scalar style and chomping mode, anchors and aliases, comments, and `---` and `...` markers.
- It only uses scalars that 1.1 and 1.2 read the same way.
- The intended value, PyYAML and `ext::yaml` must all agree.
- In the default run, 990 documents have anchors, 215 have aliases, 540 have block scalars and 1,203 have more than one document.
- Seeds 1, 2 and 3 with `--docs 20000` also agree.

The whole oracle run, including PyYAML, takes 2 s.

## Speed

Times are end to end, including writing the JSON:

| Document | Time |
| --- | --- |
| 2.1 MB block sequence of 20,000 mappings, each with a quoted string, a flow sequence, a number and a literal block scalar | 0.58 s (PyYAML `safe_load`: 16 s) |
| 6.3 MB of the same shape with long comment lines and two-line literal blocks | 0.39 s |

Comments and literal block lines are skipped with `core::slice::memchr_from` when the source has no carriage returns. This took the second document from 0.66 s to 0.39 s and the first from 0.72 s to 0.58 s. ASCII runs inside scalars also skip the per-character line and column bookkeeping.

```text
lcc -o batch tests/fixtures/extended/yaml/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/yaml/oracle.py ./batch [--seed N] [--docs N]
```

## Writing

```text
ext::yaml_writer::write(tree: &ext::json_tree::Tree, node: i32, out: &Vec<u8>) -> Result<i32, ErrorKind>
```

`write` appends one document for `node` to `out` and returns the number of bytes written. The only error is `AllocationFailed`, which leaves a partial document in `out`. The document has no `---` marker and ends with a line feed.

**Layout:**
- Nonempty mappings and sequences are written in block style, indented by two spaces. A collection inside a sequence starts on the item's line (`- - a`, `- k: v`).
- Empty collections are written as `[]` and `{}`.
- A key longer than 200 bytes uses the explicit `? key` form, which avoids the 1024-character limit on implicit keys.

**Scalars:**
- `null`, `true` and `false` are written as these words.
- Integers keep their spelling. A float with an exponent gets a fraction and an exponent sign, so `1e3` becomes `1.0e+3`, because YAML 1.1 floats need both. Other floats keep their spelling.
- A string is written plain when no reader could take the plain form for anything else. The rules:
  - It must start with an ASCII letter, `_`, `/` or a non-ASCII character, so it is never a number, date, indicator or YAML 1.1 merge (`<<`) or value (`=`) key.
  - It must not end with a space.
  - It must not be `y`, `n`, `yes`, `no`, `on`, `off`, `true`, `false` or `null` in any case.
  - It must contain no control characters, no `: ` or final `:`, and no ` #`.
  - It must contain no C1 control, line or paragraph separator, byte order mark, U+FFFE or U+FFFF. YAML 1.1 treats NEL, U+2028 and U+2029 as line breaks.
- A string with line feeds that meets the same character rules, and whose first line is nonempty and does not start with a space, becomes a literal block scalar. Its chomping indicator matches its trailing line feeds: `|-` for none, `|` for one, `|+` for more.
- Every other string is double-quoted. Inside the quotes, `"`, `\`, tab, line feed, carriage return and NUL use their short escapes. Other C0 controls, DEL and C1 controls use `\xXX`, and the separators and noncharacters use `\uXXXX`.

The plain rules are conservative. Of the 125 short strings in the oracle's list, 11 are quoted even though PyYAML would read them plain:
- `y` and `N`, which other 1.1 readers take as booleans;
- `1e3`, `1.5e3` and `0o17`, which are numbers in 1.2;
- `-x`, `?x` and `:x`, which start with an indicator character;
- three strings holding U+2028, U+2029 or U+FEFF.

### Writer evidence

[`tests/fixtures/extended/writers/oracle.py`](../tests/fixtures/extended/writers/oracle.py) generates trees and runs them through [`batch.lani`](../tests/fixtures/extended/writers/batch.lani). The batch parses each tree with `ext::json_tree`, writes it, and reads the output back with `ext::yaml::load`.

**Checks:**
- PyYAML 6.0.1 `yaml.safe_load` of the output must equal the tree. Integers must match exactly and floats as doubles.
- `ext::yaml` must read the output back to the same tree, with numbers compared as exact decimals.

**Generated trees:**
- Trees nest up to four levels.
- Strings are drawn from 125 hand-picked hard cases and combinations of them: 1.1 and 1.2 keywords and numbers, indicators, quotes, escapes, every control class, separators, multi-line text with each trailing-newline count, and keys longer than 1024 bytes.
- Numbers cover each JSON spelling: `-0`, exponents with and without a sign, big integers, and values that overflow and underflow.

| Group | Trees | Agree |
| --- | --- | --- |
| Hand-written trees | 20 | 20 |
| Generated trees | 3,000 | 3,000 |
| Generated root strings | 300 | 300 |

- The outputs hold 3,751 double-quoted scalars and 706 literal blocks.
- Seeds 1 and 2 with `--trees 15000` also agree.
- A 3.2 MB JSON array of 20,000 records is written as YAML and read back in 1.7 s.

```text
lcc -o batch tests/fixtures/extended/writers/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/writers/oracle.py ./batch [--seed N] [--trees N]
```
