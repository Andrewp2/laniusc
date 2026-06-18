# Capacity And Limits

This chapter explains how compiler authors should think about capacities,
storage strides, bounded work, and user-visible limits. The short version is:
most numbers in the compiler are implementation capacities, not language
limits. A number becomes a language limit only when the compiler deliberately
documents the source construct, reports exhaustion at that construct, and tests
the diagnostic.

Use this page when changing a shader loop, a row stride, a scan shape, a
source-pack chunk size, a dispatch dimension, or an error that says a construct
is "too deep", "too large", or "unsupported".

For exact current fields, shader load sites, status codes, large structs, and
Rustdoc-visible APIs, use [Generated compiler reference](generated/reference.md).
For the underlying phase model, use [Parser and HIR](parser.md), [Resident type
checker](type-checker.md), [Source packs, artifacts, and work queues](source-packs.md),
and [GPU passes and shader artifacts](gpu-passes.md).

## Ownership Rule

A capacity is owned by the phase that allocates or validates the bounded data:

| Capacity kind | Owner | Expected behavior |
| --- | --- | --- |
| Resident buffer size | Allocating phase | Allocate enough for the current input or fail before consumer passes run. |
| Dispatch grid shape | Pass recorder or dispatch-args shader | Tile across dimensions or pages without changing language behavior. |
| Row stride | Record-family owner | Treat as storage layout, not a source-language count, unless explicitly diagnosed. |
| Search/probe guard | Shader that can exhaust | Either remove the guard through a scalable algorithm or write a status tied to source evidence. |
| Source-pack chunk size | Source-pack planner/store | Return progress and let the caller resume; do not reject valid source just because one chunk is full. |
| Public API bound | Public API layer | Explain the alternate API path in the error. |
| Language limit | Owning semantic phase | Report a stable diagnostic at the exact source construct that exceeded it. |

Do not make downstream phases compensate for an upstream capacity mistake. If
the parser underallocates HIR rows, type checking should not infer missing rows
from tokens. If a type-check table silently truncates type arguments, codegen
should not accept the truncated metadata.

## Capacity Is Not A Language Limit

The compiler uses many numbers for GPU layout and bounded work. Examples:

- `MAX_GROUPS_X = 65535` appears in many Slang shaders as a 2D dispatch tiling
  width. It is not a maximum source file size or maximum HIR row count.
- `TYPE_INSTANCE_ARG_REF_STRIDE = 4` reserves four words per type-instance
  argument-reference row. It is not a four-type-argument language limit.
- `CALL_PARAM_CACHE_STRIDE = 4` is a cached row width for call-parameter data.
  It is not the maximum number of function parameters.
- `NAME_RADIX_MAX_BYTES = 64` controls how many source bytes are inspected by a
  compacted name-key sort. It is a key-layout fact; if longer names become
  semantically ambiguous, the name owner must validate and diagnose that
  boundary deliberately.
- `HIR_VARIANT_PAYLOAD_SLOT_STRIDE = 4` is the current flat readback layout for
  enum variant payload slots. Parser readback rejects rows that claim more
  payloads than the flat slots can represent instead of accepting truncated
  data.
- `DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES = 64` and
  `DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES = 512 * 1024` bound in-memory
  source-pack operations. Larger codebases are expected to use persisted
  source-pack descriptor work queues.

When reviewing a change, ask what the number means to a user. If the answer is
"nothing, it is storage or dispatch shape", the code should scale by allocation,
tiling, paging, segmented scans, pointer jumps, or persisted chunks. If the
answer is "the language does not support this source shape yet", the owning
phase must produce a source-addressed diagnostic.

## Current User-Visible Bounds

Some bounds are intentionally user-visible today.

| Bound | Current behavior | Owner |
| --- | --- | --- |
| In-memory source-pack unit size | Public in-memory source-pack helpers reject packs that exceed the default bounded codegen unit and tell callers to use persisted descriptor work queues. | `compiler/gpu_public_api.rs`, `codegen::unit` |
| Package module/import path depth | Package/source-root replay rejects paths deeper than `PACKAGE_MODULE_PATH_SEGMENT_LIMIT` with `LNC0014` and a source label. | `compiler/source_pack/package_manifest.rs`, package lock source scan |
| Unsupported predicate argument shapes | Type checking reports `LNC0008` or `LNC0021` at the unsupported trait bound or impl argument token. | `type_checker` predicate passes and diagnostic mapping |
| Unsupported runtime-bound stdlib execution | Descriptor/runtime contracts fail closed instead of claiming executable target bytes. | `stdlib`, artifact descriptors, descriptor executor |

These are allowed because they are explicit and diagnostic-backed. They should
still be viewed as work to remove when the implementation can represent the
larger or richer source shape without sacrificing diagnostics.

## Preferred Escape Routes

When a source construct can reasonably be large, prefer an algorithm that avoids
the limit entirely.

| Problem shape | Preferred route |
| --- | --- |
| Ordered rows owned by one parent | Link/rank/scatter rows and validate source-order ordinals. |
| Parameter or argument matching | Use owner-local rows, sorted keys, pointer jumps, or segmented scans rather than bounded local arrays. |
| Nested parent/owner propagation | Use logarithmic pointer-jump passes sized from row count. |
| Prefix totals and compacted outputs | Use block-local scans, block summaries, and apply-prefix passes. |
| Large source packs | Use persisted metadata, artifact shards, work queues, and resumable chunks. |
| Large dispatches | Use generated dispatch arguments and 2D grid tiling. |
| Large fan-in link work | Use hierarchical link leaf/reduce groups and sidecar pages. |

The parser parameter path is the model to copy. Parameter rows are represented
as parser-owned records with owner function, ordinal, name token, record node,
and optional type edge. The tests include a 257-parameter function to prove the
row/rank path crosses a local scan boundary. That is more useful than a small
"reasonable code" limit because it proves the data structure scales past the
first GPU block.

## Loop Exhaustion

Shader loops are allowed only when their bound is a proven implementation bound
or when exhaustion is surfaced as a source-addressed failure.

| Loop shape | Requirement |
| --- | --- |
| Fixed workgroup scan loop | Bound by workgroup size or scan slots; no user diagnostic needed. |
| Pointer-jump loop planned from row count | Host planner computes enough steps for the live capacity. |
| Binary/range search loop | If not guaranteed by sorted-table invariants, exhaustion must write status identifying the row or token being resolved. |
| Guard loop over syntax children | Prefer replacing it with parser-owned relation rows. If retained, exhaustion must reject at the source span that required the missing relation. |
| Probe loop over hash/key table | The table owner must prove load factor and insertion capacity, or report table exhaustion with an owning source label. |

Silent loop exhaustion is worse than a hard error. It leaves behind partial
metadata that later phases may treat as authoritative. If a shader cannot prove
completion, it should write a status word before any consumer relies on the
rows.

The status should point to the construct that forced the exhausted search, not
to an internal row when a better source span exists. For example:

- an exhausted parameter match should label the call argument or parameter list
- an exhausted type-argument search should label the generic argument or owner
  path
- an exhausted module path lookup should label the module or import path
- an exhausted predicate shape should label the trait bound or impl header

When the only available evidence is an internal row, improve the producer to
publish file id and token span before adding a generic diagnostic.

## Parser Capacities

Parser tree capacity is derived from the production emit stream. The conservative
projection multiplies adjacent token pairs by the maximum production emit width
in the parse tables, then normalizes to at least one row. Some compiler paths
read exact projected capacity before allocating full tree/HIR buffers.

The parser contract is:

1. Size tree/HIR buffers before recording consumers.
2. Carry token file ids and token spans into every source-addressable HIR row.
3. Validate live row counts before readback validators inspect per-row data.
4. Reject malformed list records before later phases consume partial rows.

Parser readback deliberately fails closed when a published live count exceeds
readback capacity:

```text
parser <label> published <requested> rows, exceeding readback capacity <capacity>
```

That error is a host validation failure, not a user language diagnostic. It
means one of the following is wrong:

- capacity planning selected too few rows
- a GPU pass wrote the wrong count
- readback chose the wrong live-count source

The fix is to repair capacity/count ownership, not to inspect a prefix of rows
and continue.

## Type-Checker Capacities

The type checker receives live counts in `TypeCheckParams` and may reuse larger
resident buffers through its cache key. Capacity reuse is one-directional:
larger cached state may serve a smaller source, but a smaller cached state must
be rebuilt before larger dispatches record.

Important type-check constants are storage or planning facts unless a separate
diagnostic says otherwise:

| Constant | Meaning |
| --- | --- |
| `TYPE_INSTANCE_ARG_REF_STRIDE` | Words reserved per type-instance argument-reference row. |
| `CALL_PARAM_CACHE_STRIDE` | Words reserved per cached call-parameter row. |
| `GENERIC_CLAIM_CAPACITY_MULTIPLIER` | Scratch multiplier for generic claim validation relative to call rows. |
| `NAME_RADIX_BUCKETS` | Byte-wise radix bucket count plus end-of-name bucket. |
| `NAME_RADIX_MAX_BYTES` | Name-key byte passes for compacted name sorting. |

If a type-check pass needs a bounded table, the table owner must either prove
the bound from live counts or diagnose exhaustion. The diagnostic path should
use type-check status mapping so the user sees the source construct that caused
the relation to be unrepresentable.

The predicate tests are the current example of a deliberate unsupported shape:
reference, nested, generic, or second trait arguments are rejected with stable
diagnostics that label the trait bound or impl argument. That is acceptable
while the GPU predicate row shape does not represent those arguments. It should
not be copied as a pattern for storage limits that can be removed.

## Source-Pack Bounds

Source-pack bounds are usually chunking and resumability contracts. They should
not reject valid projects merely because one operation would be too large.

| Bound kind | Expected behavior |
| --- | --- |
| Metadata chunk item limit | Write a bounded amount of metadata and return progress. |
| Artifact preparation item limit | Advance the persisted preparation state machine and resume later. |
| Work-queue ready-item limit | Inspect a bounded ready frontier and return a progress snapshot. |
| Work-item claim lease | Record ownership and expiry without changing the graph. |
| Link fan-in page size | Spill or group inputs through hierarchical link pages. |

The in-memory source-pack helpers are the exception. They are intentionally
bounded because they do not create persisted progress records. Their errors must
continue to name the persisted work-queue route for larger codebases.

## Adding Or Changing A Limit

Use this checklist before adding any new capacity, guard, stride, or "too many"
error:

1. Name the source construct, record family, or store record being bounded.
2. Decide whether the bound is semantic, storage, dispatch, chunking, or public
   API ergonomics.
3. If it is storage or dispatch, first try to remove it through scans, paging,
   2D dispatch, pointer jumps, sorted ranges, or persisted chunks.
4. If it is semantic or temporarily unsupported, add a status path and diagnostic
   at the owning phase before downstream consumers observe partial data.
5. Make the diagnostic source-addressable. A row number alone is not enough for
   user-facing exhaustion.
6. Add the smallest source test that trips the exact boundary.
7. Add a positive test just above the old accidental limit when the work removes
   a restriction.
8. Document the bound here only if future compiler authors need to preserve or
   intentionally remove it.

Avoid compatibility fallbacks for old limits unless another human being needs
an existing artifact or workflow to keep working. A hidden fallback makes the
code look deliberately constrained even when the real goal was to remove the
constraint.

## Evidence

Use the narrowest proof that matches the claim:

| Claim | Useful evidence |
| --- | --- |
| A capacity is only storage layout | Source comments or docs plus tests proving source constructs can exceed the old local boundary. |
| A parser list relation scales | Parser HIR tests over a generated source that crosses a scan/block boundary, plus readback validators. |
| A semantic unsupported shape is diagnosed | Focused type-check test asserting stable code, source line, column, and help text when useful. |
| A public API bound routes users correctly | Public API or CLI test asserting the error names the alternate persisted route. |
| A source-pack chunk resumes | Store/progress test showing repeated bounded steps reach the same prepared state. |
| A shader-loop change is safe | `tools/shader_loop_audit.sh` plus focused behavior tests for the owning pass family. |
| Generated inventories changed | `tools/compiler_inventory.py --output docs/compiler/generated/reference.md` and `--check`. |

Keep test inputs small. If a test needs a large generated source only to cross a
block boundary, generate the minimum count that crosses that boundary and state
which boundary it crosses in the test name.

## Common Mistakes

- Treating a row stride as a language limit.
- Treating `MAX_GROUPS_X` as an input-size cap instead of a dispatch tiling
  dimension.
- Returning a generic backend failure when the frontend phase knows the source
  construct that exceeded a bound.
- Letting a shader guard loop fall through with default rows.
- Inspecting only a readback prefix after a live count exceeds capacity.
- Increasing a loop bound to make one test pass instead of replacing the loop
  with a scalable relation.
- Adding a broad compatibility default for persisted records when no existing
  human workflow needs old stores to keep loading.
