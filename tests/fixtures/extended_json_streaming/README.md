# Borrowed JSON encoding: direct contracts and ordered-AST model

These fixtures exercise the canonical `core::io::Read` implementation of
`ext::json::Encoding`, exact admitted length, cursor copies and the owned
`encode` convenience. Expected wire bytes preserve object order, duplicate
keys and the original number spelling. JSON parsing/reserialization is not
used as the model reference or as its transport.

## Direct contracts

`contracts.lani` constructs a document containing duplicate keys, unchanged
`1.2300E+05`, seven control escapes, quote/backslash/slash, two- and four-byte
UTF-8 and nested empty/nonempty containers. Its expected 108-byte wire is a
literal byte array. Every initial cut from zero through 108 is checked on
native and packed destinations. Copies made at that point drain independently
with one-byte and seven-byte reads, including cuts inside escapes and UTF-8.

The fixture compares every destination cell and remaining byte count, rejects
negative/overflowing logical ranges before and after EOF, checks a zero count
at i32::MAX, and repeats EOF reads. It also composes the encoder through a
generic Read helper, Take/Chain/read_exact and canonical copy into SliceWriter.
Owned encoding matches the same literal bytes. Exact output-cap admission,
one-byte-short rejection and NoRoot precedence are checked without changing
the document beneath live cursors.

The direct native selector passed one test in **6.92 seconds**, with a separate
Rust build of **1.68 seconds**:

```text
extended_json_streaming_execution::json_encoding_exact_wire_boundaries_copies_limits_and_read_compositions_execute
```

Receipt: `target/stdlib-work/stream-encoding-json-direct.log`.
The executed fixture SHA-256 is
`cb986232ca93254e5b4ca34c7af5ede104a52296bfba1f7716a92c21f1ad435a`.
The driver at that invocation was `c550cc1c`; the later model selector adds a
second test without changing the direct fixture.

## Independent model

`oracle.py` describes semantic trees with explicit ordered object-member
lists. Number nodes retain lexical bytes. Its wire reference recursively
joins structure and uses a declarative byte substitution table for strings:
control bytes become lowercase `\u00xx`, quote/backslash are escaped, and all
other valid UTF-8 bytes pass through. It does not reproduce the production
link traversal or incremental escape state.

`model.lani` builds those documents through public `add_*` methods from
binary preorder records. Temporary key/value owners are destroyed after the
document copies them. The document remains stable and live while its readers
exist. The producer compares with the reference through observations rather
than receiving expected output bytes.

Seed `0x150a0261110` fixes 150 semantic trees:

- Null, both booleans and ten raw number spellings, including negative zero,
  trailing zeros, large magnitudes and differently spelled exponents.
- All 43 strings of zero through two scalars over `a`, NUL, quote, backslash,
  `é` and `😀`, plus all 32 individual control bytes.
- Eight structural/Unicode profiles covering duplicate order, keys requiring
  escaping, empty containers, all UTF-8 widths and noncharacters.
- Five long strings around 1,024-byte collector boundaries, one 80-level
  alternating object/array tree, and 48 seeded trees of depth at most four.

Each tree runs with exact, larger and one-byte-short output caps on both actual
destination layouts, whose observed strides are compared (`-8` native bytes,
`+1` packed bytes). Another 72 cases exercise every initial cut of six compact
wires. Six empty-document cases check NoRoot, including zero output cap.
This gives **978 cases: 672 admitted and 306 rejected**.

Admitted cases cover **24,774 read calls**, **8,857 cursor copies**, **3,360
invalid requests**, **3,155 zero requests** and **7,056 positive-request EOF
observations**. The sum of admitted wire lengths is **32,940 bytes**; it is not
the total output traffic, because copies and owned encoding repeat bytes.

The complete comparison includes all three initial preflight/owned results,
error offsets, both readers' remaining counts after each action, actual stride,
all 64 destination cells per action and final public queries for every node.
Those queries cover kinds, sibling/child links, counts, Boolean values, raw
numbers, string bytes and object keys. Owned encoding is compared again after
traversal. Stream positions are modeled as offsets into the independent wire,
so cursor copies do not share the production machine's representation.

## Bounds, controls and acceptance

One native process handles the complete raw-binary batch. Per-case limits are
128 nodes, 16,384 bytes of AST records, 48 action records, 4,096 expected wire
bytes and 64 destination cells. The producer uses 4,096-byte output staging.
The child process has a 75-second bound inside a 90-second oracle harness.
Strict exit status, stderr, exact full output and the fixed summary are
required; neither JSON transport nor aggregate hashes replace observations.

Host-only controls pass and reject 16 deliberate output corruptions, covering
admission metadata, exact number/member bytes, per-read framing/progress,
remaining counts, destination guards, final wire bytes and truncated/extra
output. Literal expected escaping and duplicate-number wire checks exercise
the reference itself. These controls are separate from library execution.
The model native selector passed one test in **7.48 seconds**, with a separate
Rust build of **1.97 seconds**:

```text
extended_json_streaming_execution::json_encoding_matches_ordered_ast_wire_reads_copies_and_document_snapshots
```

Receipt: `target/stdlib-work/stream-encoding-json-model.log`. It confirms all
978 cases and the exact read/copy/error/EOF counts listed above, including the
32,940-byte sum of admitted wire lengths and seed `0x150a0261110`.

The accepted model source identities are:

| File | SHA-256 |
| --- | --- |
| `model.lani` | `0f88afc752348fd9a30ec774a0cfd7e8f5cf0e3f73b1c8ce553818d559bce3f5` |
| `oracle.py` | `81b632ad834bbbef3794642c327de2336eda2512a530175d6b08df1e8d956f90` |
| `tests/extended_json_streaming_execution.rs` | `4d1ede2a4444d54158203683b8de28177b9a6a75f69e7168155f06a18d73698c` |

The tested target is native Linux x86_64 CPU output from the GPU
compiler. Compiler GPU use does not establish user-program device execution.
This finite corpus is not a proof or a memory/lifetime checker. The contract
requires stable immutable valid documents and disjoint destination storage;
the model does not mutate or destroy documents while readers remain in use.
Forged trees, reentrancy and allocation-failure campaigns are outside this
fixture; separate resource tests address selected allocation/cleanup paths.
