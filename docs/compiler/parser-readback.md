# Parser Readback And HIR Validators

This chapter documents the parser readback subsystem: the code that copies
parser-owned GPU records to host memory, decodes them into vectors, and checks
parser-owned HIR invariants. It is a maintainer tool and a contract checker, not
the normal data path between compiler phases.

The hot compiler path should keep parser data resident on the GPU. If type
checking, codegen, diagnostics, or source-pack execution needs a parser fact,
that fact belongs in a resident parser buffer and in the retained wrapper for
the consuming phase. Readback is evidence that those resident records are
well-formed; it is not a substitute for publishing the record correctly.

## What This Chapter Owns

This chapter covers:

- parser staging buffers with `MAP_READ | COPY_DST` usage
- copy encoding from `ParserBuffers` into staging buffers
- host-side mapping, waiting, decoding, and unmapping
- live row-count selection and capacity checks
- parser-owned HIR validators
- resident parser readback used by debug and contract-test paths
- narrow readbacks used by source-pack and backend-facing tests

It does not cover:

- parser grammar table generation; see [Parser and HIR](parser.md)
- lexer token record layout; see [Lexer](lexer.md)
- GPU submission/readback primitives; see [GPU infrastructure](gpu.md)
- user-facing diagnostic rendering; see [Diagnostics and status](diagnostics.md)
- downstream use of retained parser buffers; see [Resident type checker](type-checker.md)
  and [Codegen and backends](codegen.md)

The primary source is
`crates/laniusc-compiler/src/parser/readback.rs`. Resident parse-result
readback lives in
`crates/laniusc-compiler/src/parser/driver/resident_tree.rs`; recorded status
and count readbacks live near the parser driver paths that create them.

## Source Map

| Source | Responsibility |
| --- | --- |
| `parser/readback.rs` | Full parser debug staging, narrow HIR staging, decoded host records, and parser-owned HIR validators. |
| `parser/driver.rs` | Chooses whether optional full readback is enabled, records parser passes, submits work, and maps the full debug result. |
| `parser/driver/resident_tree.rs` | Resident parse-result readback path that assembles `ResidentParseResult` and reuses parser-owned validators. |
| `parser/driver/recorded.rs` | Deferred parser status and semantic-HIR count readbacks used by later capacity and validation steps. |
| `parser/driver/results.rs` | Public/debug result wrappers that hold decoded parser data or deferred status readbacks. |
| `parser/buffers` | The resident source buffers copied by readback helpers. |
| `parser/hir_records` and `parser/passes/hir` | Constants that validators use to interpret HIR kinds, item kinds, type forms, statement forms, and expression forms. |

The important ownership rule is that validators live with the parser because
they prove parser-owned records. A downstream phase may rely on the result, but
the invariant itself should be checked where the parser still understands how
the row family was produced.

## Readback Surfaces

There are several parser readback surfaces. They intentionally have different
costs and scopes.

| Surface | Types | Purpose |
| --- | --- | --- |
| Full parser debug readback | `ParserReadbacks`, `DecodedParserReadbacks` | Copies broad parser streams, tree topology, semantic topology, and many HIR row families for interactive debugging. |
| Parser-owned HIR item readback | `ParserHirItemReadbacks`, `DecodedParserHirItemReadbacks` | Copies durable item/type/parameter/method/expression/statement/list records so tests can validate production parser rows without the full debug tree. |
| Function return readback | `ParserHirFunctionReturnReadbacks`, `DecodedParserHirFunctionReturnReadbacks` | Copies the narrow function-to-return-type edge and the source/type facts needed to validate it. |
| Resident tree readback | `ResidentTreeReadbacks` in `parser/driver/resident_tree.rs` | Copies resident parse-result buffers, validates them, and assembles the resident parse result returned from parser entry points. |
| Recorded status/count readbacks | Driver-owned recorded structs | Defers compact parser status or semantic-HIR counts until the caller needs capacity or status evidence. |

Use the narrowest surface that proves the invariant. Full readback is useful
when debugging tree shape or pass order. It is usually the wrong starting point
for a focused HIR row bug, because it copies many unrelated buffers and can make
the failure look like a general parser problem.

## Common Flow

The staging helpers all follow the same shape:

1. Allocate readback buffers sized from `ParserBuffers` byte sizes or planned
   row counts.
2. Encode `copy_buffer_to_buffer` commands from resident parser buffers into
   staging buffers.
3. Submit the parser encoder, optionally wrapped in validation scopes at the
   driver boundary.
4. Request maps with `map_readback_for_progress` so long waits can report which
   readback is pending.
5. Wait through `wait_for_map_progress`.
6. Decode fixed-width words with parser/GPU readback helpers.
7. Determine the live row length and reject counts that exceed capacity.
8. Decode packed records into per-field vectors when needed.
9. Run parser-owned validators.
10. Unmap every buffer after its bytes have been copied into host vectors.

The decoders deliberately use simple host data structures. They are not the
runtime representation of parser state; they are a temporary inspection format
for assertions, tests, and debug output.

## Buffer Families

Parser readback groups buffers by the invariant they help prove.

| Family | Example records | What it proves |
| --- | --- | --- |
| Status | `ll1_status`, projected status readbacks | Whether parsing accepted, where it failed, and how many rows were published. |
| LL/action streams | LL emit stream, token positions, action headers | Whether grammar expansion produced the expected structural stream. |
| Concrete tree topology | `node_kind`, `parent`, `first_child`, `next_sibling`, `subtree_end` | Whether parse-tree rows form bounded parent/child/sibling ranges. |
| Semantic HIR topology | `hir_kind`, semantic dense nodes, semantic parent/child/sibling/depth/index | Whether semantic HIR projection is dense, ordered, and tree-shaped. |
| Source addresses | `hir_token_pos`, `hir_token_end`, `hir_node_file_id`, item/type file ids | Whether parser rows can map back to source spans and source-pack files. |
| Item/type records | item kind/name/namespace/visibility, type form/value/length/path leaf | Whether declared language constructs publish coherent typed HIR rows. |
| List relations | type args, params, call args, array elements, match arms, struct fields | Whether owner/start/count/next/ordinal records describe bounded lists. |
| Expression and statement rows | expression records, statement records, nearest context rows | Whether expression/statement wrappers and context relations point at valid owners. |
| Aggregate rows | enum variants, match payloads, struct declarations, struct literals | Whether aggregate members are owned by the right declaration or expression rows. |

When adding a row family, prefer following an existing family instead of
inventing a new readback shape. Most parser-owned relations are variations on
owner rows, list links, ordinal/rank rows, and source-addressable node ids.

## Live Length And Capacity

Readback must not trust GPU-published counts blindly. `active_tree_readback_len`
chooses the requested live row count from one of two sources:

- status word 5 when the buffer set says tree count comes from parser status
- the planned total emit count when the status count is not the authoritative
  source for that readback path

`bounded_readback_len` then compares the requested row count with the allocated
capacity. If the parser published more rows than the readback buffer can hold,
the host returns an error like:

```text
parser <label> published <requested> rows, exceeding readback capacity <capacity>
```

This is fail-closed behavior. A truncated decode would make later validators
inspect a prefix and possibly report a misleading relation error. The capacity
error points at the violated readback bound before any partial interpretation
happens.

Capacity errors are not user-facing language diagnostics. They mean either the
host planned the wrong capacity, the GPU pass wrote the wrong count, or the
readback path chose the wrong live-length source. Fix the capacity/count
contract before investigating later HIR validators. See
[Capacity and limits](capacity-and-limits.md) for the distinction between
internal capacity failures and source-language limits.

## Decoding Rules

Most buffers are decoded as `u32` vectors with one word per tree row. A few
record families are packed into wider per-row records and then split into
field-specific vectors:

- parameter records publish owner function, ordinal, name token, and record
  node fields
- expression records publish expression form, left operand, right operand, and
  value token fields
- statement records publish statement kind and up to three operand fields
- enum variant payload slots use `HIR_VARIANT_PAYLOAD_SLOT_STRIDE`

The decoded structs expose field vectors because validators often compare the
same row across multiple families. This is intentionally verbose. It keeps
validation code explicit about which row family owns each fact and avoids
encoding parser semantics in opaque host structs that only exist for debug
paths.

Use `INVALID`/`u32::MAX` consistently for absent rows. A validator should treat
absence as meaningful only if the row kind permits absence. For example, a row
with no type record is fine when it is not a type node, but a concrete type node
without a concrete type record is malformed.

## Validator Families

Validators check invariants that normal diagnostics and downstream consumers
cannot cheaply prove. The main validator groups are:

| Validator group | Representative functions | Contract |
| --- | --- | --- |
| Semantic tree | `validate_hir_semantic_tree_records` | Semantic projection is dense, ordered, bounded, and connected according to parser-owned HIR kind rows. |
| Source addresses | `validate_hir_source_address_records` | HIR rows that need source labels have non-empty spans and usable file ids. |
| Items and types | `validate_hir_item_records`, `validate_hir_type_records_with_node_kinds`, `validate_hir_type_alias_target_records`, `validate_hir_function_return_records` | Item/type rows agree with node kinds, item kinds, namespaces, names, visibility, target nodes, and return-type edges. |
| Methods and parameters | `validate_hir_parameter_records`, `validate_hir_method_records` | Function/method parameter rows are owned, ordered, source-addressable, and anchored after the method/function name when relevant. |
| Type arguments | `validate_hir_type_argument_records` | Type-argument owner counts, starts, and next links describe bounded argument chains under valid path/type owners. |
| Expressions and statements | `validate_hir_expression_records`, `validate_hir_expression_result_root_records`, `validate_hir_statement_records`, `validate_hir_const_item_statement_records`, `validate_hir_context_relation_records` | Expression/statement forms and context relations point to valid owners and result roots. |
| Calls and arrays | `validate_hir_call_argument_records`, `validate_hir_array_literal_records` | Call/array owner counts, argument/element ordinals, and next chains describe complete bounded lists. |
| Matches and members | `validate_hir_match_records`, `validate_hir_member_records` | Match arms/payloads and member expressions are owned by the expected expression rows and source tokens. |
| Structs and enums | `validate_hir_struct_declaration_field_records`, `validate_hir_struct_literal_field_records`, `validate_hir_enum_variant_records` | Aggregate declaration/literal members have valid owners, ordinals, payload rows, and source/type anchors. |
| Item paths | `validate_hir_item_path_records` | Module/import/path item rows publish anchored source spans and path node relations. |

A validator should report the row family and row id that first violates the
contract. When the bad row also has a source span, the diagnostic path should be
improved at the parser or phase boundary that owns that span rather than by
loosening the readback validator.

## Invariant Patterns

Most parser readback failures fall into one of these patterns:

| Pattern | Meaning |
| --- | --- |
| Published row outside capacity | A GPU count, owner row, or next link points beyond the live readback rows. |
| Orphan relation row | A list/member/context row is populated but no valid owner row claims it. |
| Incomplete owner list | An owner claims `n` children, arguments, arms, or fields, but fewer rows publish matching ownership. |
| Broken next chain | A start/count chain skips, loops, crosses owners, or points outside the live rows. |
| Bad ordinal/rank | Rows under one owner publish duplicate, sparse, or out-of-range ordinals. |
| Kind mismatch | A row publishes an item/type/expression/statement record incompatible with its HIR or parse-node kind. |
| Source span mismatch | A child/source record falls outside the owning construct or has an empty/unaddressable span. |
| File-id mismatch | Related rows claim incompatible source-pack file ids where the relation must stay inside one file. |
| Wrong context relation | Nearest statement/block/control/loop/function rows point at an invalid kind or skip the expected owner boundary. |

These are parser bugs even when the user-visible compile appears to succeed.
The compiler may later survive because a downstream phase ignores the malformed
row, but that does not make the parser record valid.

## Relationship To The Hot Path

Readback should not be required for successful compilation. Normal compilation
should flow through resident buffers:

```text
lexer buffers -> parser buffers -> retained parser wrappers -> type checker/codegen
```

Readback follows a separate debug path:

```text
parser buffers -> staging copies -> host vectors -> validators/debug output
```

Do not make downstream phases consume `DecodedParserReadbacks` or any decoded
readback struct. If a downstream phase needs a new parser fact:

1. add or extend the resident parser buffer that owns the fact
2. write the fact during the parser pass that already owns the source relation
3. retain it in `OwnedTypecheckParserBuffers`, `OwnedX86ParserBuffers`, or the
   appropriate phase wrapper
4. add readback validation to prove the resident row is well-formed

This keeps readback as a verifier instead of turning it into a hidden host-side
transport layer.

## Source Packs And File Identity

Source-pack support makes parser source identity stricter. Parser rows that can
be reported to users must preserve file ids as well as token spans. Readback
validators check that item/type/source-address records do not silently lose
source-pack identity.

When adding a parser row that can be used in diagnostics or source-pack
artifacts, ask:

- Does the row need a file id, or can it only be interpreted relative to another
  source-addressed owner?
- Does the row ever point across files? If yes, which relation makes that
  cross-file edge legitimate?
- Which retained wrapper carries the file id after parser buffers are released?
- Which validator proves the row can be mapped back to source?

Do not recover missing file identity in a downstream diagnostic renderer. The
parser owns the source row and should publish enough data for later phases to
label it without guessing.

## Failure Handling

Parser readback validators return maintainer-facing `anyhow` errors. They are
not stable language diagnostics and should not be rendered as if the user's
program is wrong. A readback failure means the compiler's internal parser
contract was violated.

When investigating a failure:

1. Read the readback label first; it usually names the surface and buffer
   family, such as `parser.hir_item_readback` or `parser.resident_tree`.
2. Read the row id in the error as a HIR/parser row, not as a byte offset or
   source token.
3. Use `hir_token_pos`, `hir_token_end`, and file-id rows to map the row back to
   source when those rows are valid.
4. Identify the parser pass that writes the first malformed row.
5. Add the smallest focused test that reproduces the invariant violation.

If the failure is a capacity error, inspect capacity planning and count
publication before inspecting HIR relation validators. If the failure is an
orphan or broken-chain error, inspect the owner/link/rank pass family before
the scatter or downstream consumer.

## Adding A Readback Or Validator

Use this checklist for parser readback changes:

1. Choose the narrowest readback surface that can prove the contract.
2. Copy only durable parser buffers. Avoid copying debug-only navigation arrays
   into source-pack or backend-facing readbacks unless the contract actually
   depends on them.
3. Decide the live length source before decoding. Use the parser status count
   only when that readback path declares it authoritative.
4. Reject live counts that exceed capacity before reading per-row data.
5. Decode packed records into named fields before validation.
6. Validate parser-owned facts at the row-family boundary that produces them.
7. Keep error messages specific: include the family, row id, related row id,
   and capacity/count when applicable.
8. Add small unit tests for the validator. Prefer direct vector fixtures over
   full parser inputs when the invariant can be proven that way.
9. Add one integration or source-pack contract test only when GPU pass order or
   source identity must be exercised end to end.
10. Update `docs/compiler/generated/reference.md` if the change adds or removes
    large buffer-carrier structs, public operation entry points, or generated
    inventory inputs.

Do not add compatibility readback fields for old row layouts unless another
human maintainer actually needs to keep consuming that old layout. Unneeded
aliases make the validator look like it is preserving a real external contract
when it is only preserving stale complexity.

## Test Evidence

For readback-only code changes, start with focused validator tests:

```bash
cargo test -p laniusc-compiler readback
```

For a parser change that affects generated inventories or documented buffer
carriers, also run:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

For a bug that only appears after GPU execution, use the smallest source text or
source-pack slice that reaches the bad row. Keep broad readback and timing flags
off until the first failing boundary is known. Then use:

```bash
LANIUS_READBACK=1 <focused command>
LANIUS_GPU_PIPELINE_PROGRESS=1 <focused command>
```

Use timing or benchmark artifacts only for performance claims. Readback exists
to prove row correctness, not to prove that a parser change is fast.

## Common Mistakes

| Mistake | Better approach |
| --- | --- |
| Adding a decoded field because it is convenient for a downstream phase | Add a resident parser buffer and retain it at the phase boundary. |
| Copying the full parser debug surface for one row-family invariant | Add or use a narrow HIR readback. |
| Letting validators inspect rows past the live count | Bound the readback length first and fail closed on capacity mismatch. |
| Treating readback errors as user syntax/type errors | Fix the compiler invariant or map a real parser status into a proper diagnostic. |
| Validating downstream interpretation in parser readback | Validate only parser-owned facts; downstream contracts belong to the consuming phase. |
| Adding broad fixture programs for simple broken-list cases | Test the validator directly with the smallest vector fixture that expresses the broken contract. |
| Hiding missing source/file identity in diagnostics | Publish and retain the source/file id at the parser boundary. |

The readback subsystem is valuable because it is strict. Keep it strict, small
for focused paths, and separate from normal compilation.
