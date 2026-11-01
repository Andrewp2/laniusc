# TOML writing from JSON trees

`ext::toml_writer` writes an [`ext::json_tree`](extended-json-patch.md) object as a TOML 1.0 document. It keeps every number spelling exactly as the tree holds it. The module is in the `extended` source root. [`ext::toml`](extended-toml.md) is the reader.

## API

```text
ext::toml_writer::write(tree: &ext::json_tree::Tree, node: i32, out: &Vec<u8>) -> Result<i32, Error>
ext::toml_writer::kind_name(kind: ErrorKind) -> Text
```

- **Output:** `write` appends the document for the object at `node` to `out` and returns the number of bytes written.
- **Errors:** `Error` is `{ kind, node }`, where `node` is the tree node that cannot be written. On an error `out` may hold a partial document. `kind` is one of:
  - `NotTable`: the root is not an object.
  - `NullValue`: TOML has no null.
  - `IntegerRange`: an integer outside the signed 64-bit range, which TOML requires readers to reject.
  - `AllocationFailed`

## Layout

| Tree value | TOML |
| --- | --- |
| an object member of a table | a `[table]` section with a dotted header path |
| a nonempty array whose elements are all objects, as a member of a table | one `[[array of tables]]` section per element |
| an object anywhere else (in an array, or inside an inline value) | an inline table `{ k = v, ... }` |
| other arrays | inline arrays `[a, b]`, which may mix types (TOML 1.0) |
| strings | basic strings |
| numbers | the tree's spelling |
| booleans | `true`, `false` |

- **Order:** each table writes its key/value pairs first, then its sub-tables and arrays of tables, each in member order. TOML requires this, so members of mixed tables do not keep their order.
- **Headers:** every table gets its own header, including empty ones, so `{"a":{}}` writes `[a]`. Under `[[a]]`, a sub-table of the element is written as `[a.b]`, and TOML attaches it to the last element.
- **Keys:** keys made only of `A-Za-z0-9_-` are bare. Other keys, including the empty key, are basic strings, so `a.b` is written as `"a.b"`, not as a dotted key.
- **Strings:** `"`, `\`, line feed, carriage return, backspace and form feed use their short escapes. Other control characters and DEL use `\u00XX`. Tab and all other characters, C1 controls included, are written as they are.
- **Numbers:** JSON number spellings are valid TOML (`-0`, `1e3`, `1E-07`, `-0.0`), so they are written unchanged. Integers are checked against the signed 64-bit range by comparing their digits.

## Execution evidence

[`tests/fixtures/extended/writers/oracle.py`](../tests/fixtures/extended/writers/oracle.py) runs generated trees through [`batch.lani`](../tests/fixtures/extended/writers/batch.lani). The batch parses each tree with `ext::json_tree` and writes it with this module.

**Checks:** Python's `tomllib.loads` of the output must equal the tree.
- Floats are read with `parse_float=str`, so their spelling must match the tree's byte for byte.
- Integers must match exactly.
- Objects compare as mappings, because of the order rule above.

**Generated trees:**
- Each tree is a root table nesting up to four levels.
- Arrays of tables appear at every level, with nested arrays of tables and sub-tables of their elements.
- Mixed arrays hold inline tables, and empty tables, arrays and keys appear.
- Keys need quoting (dots, spaces, quotes, Unicode).
- Strings come from the same hard cases as the YAML writer.
- Floats cover each JSON spelling, including `1e400` and `5e-324`.
- Integers include both i64 bounds.

| Group | Cases | Agree |
| --- | --- | --- |
| Hand-written trees | 14 | 14 |
| Generated trees | 3,000 | 3,000 |
| Errors: `NotTable`, `NullValue` (at four depths), `IntegerRange` | 11 | 11 |

- Seeds 1 and 2 with `--trees 15000` also agree.
- A 3.0 MB JSON object holding an array of 20,000 records is parsed and written as `[[items]]` tables in 0.55 s.

```text
lcc -o batch tests/fixtures/extended/writers/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/writers/oracle.py ./batch [--seed N] [--trees N]
```
