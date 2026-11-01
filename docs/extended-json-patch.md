# JSON Pointer, JSON Patch and JSON Merge Patch

Three modules in the `extended` source root edit JSON documents:

- `ext::json_tree` holds a mutable document tree.
- `ext::json_pointer` implements [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html) pointers.
- `ext::json_patch` implements [RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html) JSON Patch and [RFC 7386](https://www.rfc-editor.org/rfc/rfc7386.html) JSON Merge Patch.

The trees are read with [`ext::json_stream`](extended-json-stream.md) and written through its `Writer`, so they follow the same strict grammar, keep exact number spellings and use the same compact output.

## Trees

```text
ext::json_tree::parse(source: [u8], start: i32, count: i32, limits: Limits) -> Result<Tree, Error>
ext::json_tree::copy(source: &Tree, limits: Limits) -> Result<Tree, Error>
ext::json_tree::default_limits() -> Limits  // depth 1024, strings 16 MiB, numbers 1 MiB, 16M nodes
Tree.write(node: i32, writer: &ext::json_stream::Writer) -> Result<i32, ext::json_stream::Error>
Tree.root() / code(node) / kind(node) / text(node) / key(node) / child(node, index) / member(node, key)
Tree.first_child(node) / next_sibling(node) / parent(node) / child_count(node) / destroy()
ext::json_tree::equal(left: &Tree, a: i32, right: &Tree, b: i32) -> bool
ext::json_tree::numbers_equal(left: Text, right: Text) -> bool
ext::json_tree::number_compare(left: Text, right: Text) -> i32   // -1, 0, 1 by value
ext::json_tree::number_is_integer(text) / number_count(text, limit) / number_digits(text)
ext::json_tree::number_is_multiple(value: Text, divisor: Text) -> bool   // divisor up to 18 digits
```

The number helpers do exact decimal arithmetic on spellings, for
[`ext::json_schema`](extended-json-schema.md).

- **Parsing:** `parse` reads one JSON text, with scalar roots allowed. An `ext::json_stream` error becomes `Parse` with the stream error kind in `cause` and its byte offset. A repeated key in one object is `DuplicateKey` at the second key's offset, because a patch can only name a member whose key is unique.
- **Nodes:** a node is an `i32` id in an arena. Kind codes are 0 null, 1 false, 2 true, 3 number, 4 string, 5 array and 6 object. `text` returns a number's spelling or a string's decoded UTF-8. `key` returns a member's key. Both borrow the tree until it changes.
- **Arena:** nodes are freed only by `destroy`. A removed or replaced value keeps its storage and still counts toward `max_nodes`.
- **Lookups:**
  - Objects with at least 8 members are indexed in a hash table keyed by (object, key), so `member` is O(1) for them. Parsing an object with 20,000 keys takes 0.1 s, against 4.5 s with linear duplicate checks.
  - Smaller objects are scanned.
  - `child(node, i)` walks i links.
  - If the index cannot grow, the tree falls back to scanning and stays correct.
- **Equality:** `equal` is the RFC 6902 test.
  - Values must have the same type: `1` never equals `"1"` or `true`.
  - Numbers compare by value over their exact decimal spelling, so `1`, `1.0`, `10e-1` and `1E0` are equal, and `-0` equals `0`. Exponents beyond ±10^15 saturate.
  - Strings compare bytewise. Arrays compare element by element in order. Objects need the same keys with equal values, in any order.

## Pointers

```text
ext::json_pointer::parse(text: Text) -> Result<Pointer, Error>
ext::json_pointer::get(tree: &Tree, pointer: &Pointer) -> Result<i32, Error>
ext::json_pointer::resolve(tree: &Tree, pointer: &Pointer, count: i32) -> Result<i32, Error>
ext::json_pointer::array_index(token: Text) -> i64     // index, -2 for "-", -1 otherwise
Pointer.count() / token(i) / equals(&other) / is_proper_prefix(&other) / destroy()
```

**Parsing:**
- The empty string is the whole document. Any other pointer starts with `/`, and `parse` returns its tokens unescaped.
- `~0` becomes `~` and `~1` becomes `/`.
- Any other `~` sequence, including a trailing `~`, is `InvalidPointer`, with `offset` set to that `~`. A missing leading `/` is `InvalidPointer` at offset 0.

**Evaluation (`get`):**

| Location | Token | Result |
| --- | --- | --- |
| Object | Key not present | `NotFound` |
| Array | `0` or `[1-9][0-9]*` (ASCII digits only), within the array | That element |
| Array | Not an index (leading zeros, `+1`, empty) | `InvalidIndex` |
| Array | `-`, or an index at or past the end | `OutOfRange` |
| Scalar | Any token | `NotFound` |

Indexes above 2^32 saturate, so they are always past the end.

## Patches

```text
ext::json_patch::apply(document: &Tree, patch: &Tree, limits: Limits) -> Result<Tree, Error>
ext::json_patch::merge(document: &Tree, patch: &Tree, limits: Limits) -> Result<Tree, Error>
```

Both functions return a new tree and never change `document`. A failed patch has no effect: the partial copy is destroyed and only the error comes back.

### JSON Patch

`apply` runs the operations in order. If `patch` is not an array, the result is `InvalidPatch` with operation -1. Otherwise, the first failure returns its kind, with `operation` set to the index of the operation that failed.

Each operation is checked in this order:

1. The operation is an object.
2. `op` is a string.
3. `op` names one of add, remove, replace, move, copy or test; otherwise the error is `UnknownOperation`.
4. `path` is a string.
5. `path` parses as a pointer.
6. For add, replace and test: `value` is present.
7. For move and copy: `from` is a string and parses as a pointer.

A failure at steps 1, 2, 4, 6 or the string part of 7 is `InvalidPatch`; a pointer that fails to parse is `InvalidPointer`. Members the RFC does not name are ignored.

| Operation | Behavior |
| --- | --- |
| `add` | Path `""` replaces the document. An object parent gets the member: a new key is appended and an existing key is replaced in place. In an array parent, `-` or the length appends and a smaller index inserts before that element. A larger index is `OutOfRange` and a non-index is `InvalidIndex`. A missing parent, or a scalar parent, is `NotFound`. |
| `remove` | The target must exist. Path `""` is `RemoveRoot`. |
| `replace` | The target must exist. Path `""` replaces the document. |
| `move` | `from` must exist. A move to the same location does nothing. A `from` that is a proper prefix of `path` is `MoveIntoChild`. Otherwise it is a remove followed by an add. |
| `copy` | `from` must exist. A deep copy is then added at `path`. |
| `test` | The target must exist and be `equal` to `value`; otherwise `TestFailed`. |

`max_nodes` counts every node created: the copy of the document, each added or replaced value, each copy, and new merge objects. Going over it is `NodeLimit`, reported for the operation whose node went over. `add` copies its value before resolving the path. `replace` resolves its target, and `copy` its `from`, before copying.

### JSON Merge Patch

`merge` is the RFC 7386 `MergePatch` algorithm:

- A patch that is not an object replaces the target.
- An object patch turns a target that is not an object into `{}`.
- A `null` member removes that key.
- Any other member is merged recursively into the existing value, or appended when the key is new.
- Existing members keep their positions.

Errors (`NodeLimit`, `AllocationFailed`) have operation -1.

## Error kinds

`ext::json_tree::ErrorKind` is shared by all three modules, and `kind_name` gives stable names. Each error is reported as follows:

| Kind | Operation | Offset |
| --- | --- | --- |
| `Parse` | -1 | Byte offset in the parsed text; `cause` holds the stream error kind |
| `DuplicateKey` | -1 | Byte offset of the second key |
| `NodeLimit` | Index of the failing patch operation, or -1 | — |
| `AllocationFailed` | Index of the failing patch operation, or -1 | — |
| `InvalidPointer` | Index of the failing patch operation, or -1 | Byte offset in the pointer text |
| `NotFound`, `InvalidIndex`, `OutOfRange` | Index of the failing patch operation, or -1 | — |
| `InvalidPatch`, `UnknownOperation`, `TestFailed`, `MoveIntoChild`, `RemoveRoot` | Index of the failing patch operation | — |
| `Output` | — | — |

`Output` is reserved for callers that map writer failures.

## Execution evidence

[`tests/fixtures/extended/json_patch/oracle.py`](../tests/fixtures/extended/json_patch/oracle.py) is a Python model of all three modules. It parses with `json` hooks that keep number spellings and reject duplicates, uses strictly typed equality with `Decimal` numbers, and reproduces the library's check order and its writer's escaping.

**Checks:**
- The model is first checked against the RFC examples, typed in by hand: RFC 6902 Appendix A.1–A.16, the RFC 6901 §5 document with its 12 pointers, and RFC 7386 Appendix A plus the §3 example.
- Then [`batch.lani`](../tests/fixtures/extended/json_patch/batch.lani), compiled with `lcc`, runs every case in one process. Its output is compared bytewise with the model.
- Each case also checks that the input document is unchanged.

**Generated cases:**
- Documents are mostly containers, and a fifth of their objects have 6–13 members, so they cross the 8-member index threshold.
- Keys include `~`, `/`, `""`, non-ASCII text and escapes.
- Numbers come in equal-valued spellings.
- Inputs are written either compact or with spaces and `\u` escapes.
- Patches use mostly existing paths, plus new members and indexes, broken escapes and malformed operations.

| Group | Cases | Agree |
| --- | --- | --- |
| RFC 6902 Appendix A | 16 | 16 |
| RFC 6901 §5 | 12 | 12 |
| RFC 7386 Appendix A and §3 | 16 | 16 |
| Error kinds and checks | 106 | 106 |
| Generated patches | 3,000 | 3,000 |
| Generated merge patches | 1,500 | 1,500 |
| Generated pointers | 1,500 | 1,500 |
| Node limits | 300 | 300 |

**Outcomes:**
- All 6,450 cases agree. They cover every error kind except `AllocationFailed` and `Output`, which these inputs cannot trigger.
- The default seed reaches each kind 6 to 1,142 times, with 2,935 successes.
- Seeds 7 and 11 with `--cases 20000` (42,000 generated cases each) also agree.

**Mutation checks:** single-line changes to the model are caught. Keeping null merge members fails the RFC self-check. Treating any index past the end as an append, or comparing numbers by spelling, causes disagreements. Dropping `MoveIntoChild` crashes the model.

```text
lcc -o batch tests/fixtures/extended/json_patch/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/json_patch/oracle.py ./batch [--seed N] [--cases N]
```
