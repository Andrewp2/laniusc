# YAML 1.2 reading into JSON trees

`ext::yaml` reads YAML 1.2 documents into [`ext::json_tree`](extended-json-patch.md) trees, resolving plain scalars with the YAML 1.2 core schema. It covers:

- block and flow sequences and mappings, including indentless sequences, compact nested collections and explicit `?` keys;
- plain, single-quoted and double-quoted scalars, and literal (`|`) and folded (`>`) block scalars with chomping (`-`, `+`) and indentation indicators;
- anchors and aliases, with a limit on alias expansion;
- comments, directives, `---` and `...` markers and multiple documents.

It reads only; there is no YAML writer. The module is in the `extended` source root.

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

A 2.1 MB block sequence of 20,000 mappings, each with a quoted string, a flow sequence, a number and a literal block scalar, loads in 1.0 s end to end, including writing the JSON. PyYAML's `safe_load` takes 16 s on the same document.

```text
lcc -o batch tests/fixtures/extended/yaml/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/yaml/oracle.py ./batch [--seed N] [--docs N]
```
