# GPU Parsing — Brackets & Tree (current plan and next steps)

This document explains the **current** GPU strategy for bracket matching and tree construction, how it fits the **WebGPU constraints** we care about (modest buffers, reflected bind groups, no push constants), and what we plan to do **next**.

The code lives under `shaders/parser/*` and is driven by `src/parser/*`. The demo entry point is `src/bin/parse_demo.rs`.

---

## Design goals (tl;dr)

* **Work-efficient & parallel:** ☑️ O(n) work and large-grid throughput; only O(#blocks) small scans.
* **WebGPU-friendly:** ☑️ no push constants, fixed threadgroups (256),
  and reflected bind groups checked against device limits.
* **Deterministic pairing:** ☑️ Typed pairing invariant, involutive match map.
* **Test oracles only:** ☑️ Any host-side sequential checks must be explicitly
  named as test CPU oracles and must not be called by the compiler pipeline.
* **Composable:** ☑️ Reuse the three-phase scan pattern from the lexer.

---

## Input model

The resident compiler path starts from lexer token rows and computes
parser-local token facts before the tree/HIR passes run:

* delimiter depths, brace owners, statement/header context, and matched
  delimiter pairs are produced by token-local kernels plus scan/apply passes;
* `tokens_to_kinds.slang` consumes those token facts to publish semantic token
  kinds for parser table consumers;
* the active adjacent-pair path publishes pair headers, prefix-packed stack
  changes, and candidate production IDs for the stream that feeds tree/HIR
  construction.

From generated pair headers the resident path packs two streams (see
`pack_varlen.slang`):

* `out_sc`: **stack-change codes** (u32). *Odd* = push, *even* = pop. Upper bits carry a **typed ID** for the bracket kind (e.g., `(` vs `[`).
* `out_emit`: **candidate production IDs** from the LLP pair table.

These are produced by:

* `llp_pairs.slang`  → headers per adjacent token pair
* `pack_varlen.slang` → densely packs `out_sc` and `out_emit`

The removed block-local LL(1) replay path is no longer part of production
dispatch. The resident compiler keeps `tree_stream_uses_ll1` false for the live
path and fails closed if that legacy stream is selected.

---

# Part A — Brackets (parallel)

We compute global depths, bucket events by depth **layer**, and pair by `(layer, rank)`. This yields the same pairing as a predecessor-on-depth (PSE) approach for properly nested streams, with fewer buffers and passes.

### Pipeline overview

```
out_sc
  │
  ├─ 01  scan in-block      → exscan_inblock, block_sum, block_minpref
  ├─ 02  scan block prefix  → block_prefix, [final_depth, min_depth], valid
  ├─ 03  apply prefix       → depth_exscan, layer[i] (push → d+1, pop → d)
  ├─ 04  histogram layers   → hist_push[l], hist_pop[l]
  ├─ 05  scan histograms    → off_push[l], off_pop[l], (AND) valid
  ├─ (seed) copy offsets    → cur_push := off_push, cur_pop := off_pop
  ├─ 06  scatter by layer   → pushes_by_layer[], pops_by_layer[]
  └─ PSE pair+validate      → match_for_index[], (AND) valid
```

### Passes (files)

* **01** `brackets_01_scan_inblock.slang`
  Per-workgroup exclusive scan of `+1 / -1` (push/pop), producing `exscan_inblock` and block summaries (`block_sum`, `block_minpref`). 256-thread groups; mirrors the lexer’s scan shape.

* **02** `brackets_02_scan_block_prefix.slang`
  Prefix the block sums to get `block_prefix`, and compute `[final_depth, min_depth]` and an initial `valid` flag (`final==0 && min>=0`).

* **03** `brackets_03_apply_prefix.slang`
  Adds `block_prefix` to get the **global exclusive depth** at each event. Writes `layer[i]`:

  * push at depth `d` is on **layer `d+1`**
  * pop at depth `d` is on **layer `d`**
    We offset by `-min_depth` so layers are non-negative even for pathological inputs.

* **04** `brackets_04_histogram_layers.slang`
  Counting histograms by layer for pushes and pops.

* **05** `brackets_05_scan_histograms.slang`
  Scans histograms to get per-layer **offsets** (`off_push`, `off_pop`) and **ANDs** the `valid` flag if counts differ for a layer.

* **seed** (driver)
  `cur_* := off_*` via `copy_buffer_to_buffer` (keeps bindings low).

* **06** `brackets_06_scatter_by_layer.slang`
  Scatters indices of pushes and pops into `pushes_by_layer` / `pops_by_layer` using atomics and the seeded `cur_*` cursors.

* **PSE pair** `brackets_pse_04_pair_by_layer.slang`
  Pair by the predecessor-on-equal-depth relation and write
  `match_for_index` bi-directionally. If `typed_check != 1`, type IDs are
  ignored; otherwise, a mismatched open/close type **ANDs** `valid` to 0.

> **Equivalence to PSE:** For properly nested sequences, the `r`-th pop at depth `d` pairs with the `r`-th push at layer `d` (rank-by-layer). This is precisely the predecessor-on-equal-depth selection PSE would find, but without building a min-tree. If we ever need the explicit predecessor structure (e.g., for incremental edits), we can add a min-tree build as an alternative path.

### Complexity & buffers

* **Work:** O(n).
* **Span:** O(log blockSize) per block scan + O(#blocks) small scans + O(1) per event elsewhere.
* **Per-pass bindings:** the bracket stream passes stay in the 6-9-binding
  range; resident token/HIR passes are validated against reflection and device
  limits.
* **Memory:** `n_layers ≤ #pushes ≤ len(out_sc)`. We allocate per-layer arrays with that upper bound (conservative but simple).

### Validity & diagnostics

We expose `{ final_depth, min_depth, valid }`. Pairing still runs even if invalid to provide best-effort matches and help pinpoint the first violation with downstream checks. Typed pairing is optional (`typed_check`).

---

# Part B — Tree construction

Goal: build an **inverted tree** from `emit_stream`:

* `node_kind[i] = emit_stream[i]`
* `parent[i]    = parent index (or 0xFFFFFFFF for root)`

We maintain arity per production in `prod_arity`.

The current tree path consumes the active pair emit stream:

1. **Prefix local:** count emitted tree nodes per block, publish node kinds, and
   write block summaries from `out_emit`.

2. **Prefix scan/apply:** scan block summaries, apply global offsets, and build
   the max-tree helper used by parent recovery.

3. **Parent recovery:** recover `parent[]` with one independent thread per
   emitted production, then scatter spans, sibling links, and HIR records from
   parser-owned tree rows.

**Why this shape?**
It keeps the compiler on the active-pair production stream, avoids the removed
block-local LL(1) replay kernels, and makes tree/HIR consumers depend on
prefix-published records instead of source walks.

The old tiled LL(1) stack replay design is intentionally not dispatched by the
resident compiler path.

---

## Pipeline order (end-to-end)

```
lexer token rows
  └─ token fact passes:
       impl/trait/header context local -> scan -> apply
       delimiter depths/owners local -> scan -> apply
       statement/match/where context local -> scan -> apply
       delimiter match depth -> min-tree/PSE pair
  └─ tokens_to_kinds + tokens_to_identifier_kinds
  └─ active pair stream:
       adjacent token pairs -> prefix offsets -> packed stack/prod streams
  └─ tree/HIR:
       prefix count -> scan -> apply -> max-tree
       parent/span/prev-sibling scatter
       hir_nodes
       semantic-HIR compact prefix -> scan -> scatter
       semantic parent/depth/child-index pointer jumps
       HIR record clears
       type, type-arg, enum, item, return, parameter, method, expression,
       call, array, match, struct, and context-relation record passes
```

The order is intentionally fact-table first, consumer second: relation passes
materialize token-local, tree-local, and semantic-HIR facts before downstream HIR
records use them. For example, parameter links are pointer-jumped before method
rows read parameter records, function-signature owners are pointer-jumped before
return-type and method-signature status rows, and nearest statement/block/control
or loop context rows are scattered before later type/codegen consumers run.

Driver code lives in `src/parser/driver.rs` and
`src/parser/driver/token_frontend.rs`; buffers live in `src/parser/buffers.rs`;
pass wrappers live in `src/parser/passes/*`. The driver seeds cursors (`cur_*`)
by copying from offsets to keep bindings low.

---

## WebGPU constraints checklist

* **Binding counts:** The original bracket/tree passes stay in the small
  6-9-binding range. Newer resident token/HIR relation passes use reflected
  bind groups and must stay within the active device limits instead of the old
  fixed 10-buffer budget.
* **No push constants:** Uniforms are small constant buffers (via `encase`).
* **Resource count:** We reuse buffers across passes; staging/readback is gated by `LANIUS_READBACK`.

---

## Correctness invariants

Brackets:

* `valid` iff `final_depth == 0` and `min_depth >= 0` and (if typed) every pair’s type matches.
* `match_for_index` is **involutive**: `match[match[i]] == i`.
* Pair order is stable per layer: `(layer, rank)` matches push and pop of the same rank.

Tree:

* Exactly one root (`parent[0] = 0xFFFFFFFF` and others resolve).
* For node `j` with arity `k > 0`, exactly `k` direct children appear consecutively after `j`.
* Parent indices form a forest of one tree.

HIR records:

* Expression rows publish scalar literal forms for integer, float, string,
  char, and boolean leaves with a value token inside the expression span.
  Readback rejects literal forms on non-literal HIR rows and name forms on
  non-name/non-path HIR rows.
* Composite type rows publish parser-owned operand type edges: reference,
  slice, and array records only publish a value node when it is another HIR type
  row, and array records only publish a length token for parser-owned array
  length rows. Readback validates path/value edges, path leaves, file ids, and
  array length anchors before type-argument, statement, or function-return
  consumers run.
* Generic type-argument rows publish parser-owned first/count/next chains.
  Readback rejects owner counts that exceed the flat row set, non-type owners
  or arguments, non-path type owners, argument rows without concrete type
  records, duplicate argument ownership, orphan next links, and chains that do
  not terminate at the published count.
* Enum variant tuple payload rows use a fixed four-slot flat layout. Readback
  rejects payload counts beyond that stride instead of silently trusting a
  truncated scatter record.
* Call argument rows are linked and ranked by parser-owned flat records.
  Readback rejects argument counts that cannot fit the packed owner/ordinal
  representation, or owner rows whose argument ordinals are missing,
  duplicated, not rooted at ordinal zero, or out of source order. Argument end
  tokens reuse the parser-owned HIR span end instead of reconstructing a
  boundary from sibling or subtree shape, and readback rejects malformed
  argument end anchors, cross-file callee/argument edges, or callee/argument
  rows that escape the owning call-expression span before type checking
  consumes the records.
* Array literal element rows publish parser-owned owner, ordinal, and next-link
  records. Readback rejects owner rows whose element count, first element,
  back-links, zero-based ordinals, next chain, or source-pack file ids
  disagree.
* Struct declaration field rows publish parser-owned owner, ordinal, and type
  edges as one field record. Readback rejects orphan field ordinals or type
  edges before downstream type collection consumes stale row metadata.
* Match expression rows publish parser-owned scrutinee, arm-chain, arm-pattern,
  result-expression, and payload-pattern records. Readback rejects arm or
  payload pattern edges that do not land on name/literal pattern HIR rows, and
  rejects scrutinee/arm, pattern/result, and arm-chain ordering violations,
  plus tuple-payload ordinal rows whose zero-based order disagrees with source
  order inside the owning match expression or arm.
* Struct literal rows publish a parser-owned head path/name node plus field
  rows with owner, first/count, next-link, and value-expression records.
  Readback rejects owner rows whose head node, head/first-field source order,
  field count, first field, back-links, field-row HIR kind, value edges, or
  next chain disagree. Struct-literal field records must stay on grammar-only
  field rows rather than expression/type rows, so downstream type checking
  consumes the parser-owned field table instead of rediscovering field
  boundaries from source spelling. A semantic-row pointer-jump pass also
  publishes nearest statement, block, control, loop, and function context rows
  for semantic HIR nodes, so contextual aggregate, loop-control, and body-shape
  consumers do not need to walk ancestors in their own shader. Statement rows
  with parser-owned statement records publish themselves as their
  nearest-statement relation,
  block rows publish themselves as their nearest-block relation, and readback
  rejects rows that omit those self-context records. Readback also rejects
  context chains where the nearest-function relation does not contain the
  published statement/block/control/loop relation, or where the nearest-loop
  relation does not contain the published enclosing control relation.
  Specialized call/array/struct context rows cannot stand in for a missing
  generic nearest-statement row.
* Item rows publish a known item kind on the matching parser-owned HIR row kind.
  Readback rejects unknown item kinds and owner-kind mismatches before later
  stages consume item metadata.
* Item/type public rows are source-addressed before later record consumers run:
  readback rejects item/type records without non-empty spans or file ids, file
  ids that disagree with the HIR node, or rows that move backward in the flat
  `(file_id, token_start)` stream. Resident parser readback uses the
  GPU-published HIR node file-id column for these checks rather than a
  synthetic single-file placeholder.
* Live tree/HIR readback lengths are fail-closed: the host rejects a published
  active row count that exceeds the allocated readback buffer instead of
  clipping the stream.
* Expression rows publish parser-owned expression forms, child-expression
  edges, and literal/name value-token anchors. Readback rejects records on
  non-expression rows, unknown forms, malformed operands, cross-file child
  edges, self edges, and value tokens outside the expression span before later
  stages can fall back to source spelling.
* Expression-result root rows publish the canonical parser-owned result
  expression for each wrapper/direct expression relation. Resident readback
  rejects roots on non-expression rows, roots that are not source-addressable
  expression rows in the same file, roots that escape the owner expression
  span, and roots that are not canonical after pointer jumping, so type and
  backend consumers do not need bounded expression-wrapper walks.
* Member expression rows publish parser-owned receiver rows plus receiver and
  member-name token anchors. Readback rejects receivers that leave the member
  expression span, cross file ids, extend past the member-name token, or carry
  unordered token anchors before downstream method/field lookup consumes the
  records.

* `let` rows publish `{ kind, declaration name token, initializer expression node, declared type node }`.
  Statement records are published only from non-empty owner spans, and
  declaration or binding tokens must stay inside those spans. Readback rejects
  concrete statement HIR rows that publish no matching statement record, so
  later passes never need to rediscover missing statement metadata from token
  neighborhoods. Local declaration rows also publish parser-owned scope-end
  tokens, with readback rejecting missing or malformed scope boundaries before
  visibility consumers can fall back to token-local block walks. Return rows
  publish a value-token anchor only when it stays inside the returned
  expression span, so diagnostics and type checks do not recover value
  locations from neighboring source tokens.
* Top-level `const` declarations publish value-namespace item metadata plus
  statement-slot records `{ kind, declaration name token, value expression
  node, declared type node }`, so type checking and constant-value projection
  can consume parser-owned rows rather than source text. Readback rejects const
  item rows unless the item metadata and statement record share the same
  parser-owned name-token anchor.
* Type-alias declarations publish one parser-owned target type edge from the
  type-alias item row. Readback rejects alias rows without a concrete in-table
  type target, stale target edges on non-alias rows, cross-file or out-of-span
  targets, shared target rows, and targets that do not follow the alias name
  token before type checking resolves alias identities.
* Trait declarations publish type-namespace item metadata with parser-owned
  declaration/name tokens and visibility. The item record is emitted only from
  the trait's HIR item row, so trait collection does not need source-text or
  method-body shape rediscovery.
* Function, extern-function, and impl-method function rows publish parser-owned
  return-type edges when the grammar owns an explicit return type. Top-level
  function owners also carry item metadata; impl-method owners remain method
  rows and do not synthesize top-level item records. Readback rejects return
  edges from non-function rows, edges to non-type rows, cross-file edges,
  shared return-type rows, and return-type spans that escape the owning
  function/method span.
* Method declaration rows publish parser-owned owner, name, first-parameter,
  receiver-mode, visibility, and impl receiver-type records. Readback rejects
  impl receiver-type rows whose owner is not source-addressable or whose type
  span escapes the owning impl span, so downstream method collection does not
  need to rediscover the receiver from parser-local child scans. Method rows
  that publish a first-parameter token must also publish a receiver/first
  parameter mode, and explicit first parameters must already point at a
  parser-owned parameter type row before predicate consumers compare
  signatures.
* Parser/HIR readback cross-checks parser-owned function/method token anchors
  against ownership: declaration/name, receiver/first-parameter, and
  return/type anchors must belong to the published function or method owner
  and remain inside that owner's HIR span. Specialized call/array/struct
  context rows are accepted only when their owner/span relation agrees with the
  generic nearest-statement/block/function context chain.
* Function parameter rows publish `{ owner function node, ordinal, token
  anchor, parameter node }` plus an explicit type edge when the grammar owns
  one directly. Named parameters and `self: T` receivers point at parser-owned
  type HIR rows; plain `self` and `&self` do not synthesize type edges. The
  ordinal is zero-based source order within the owning function/method row, so
  method collection and type checking consume receiver/value parameters from
  the flat parameter table instead of reconstructing parameter lists from
  token neighborhoods. Readback rejects parameter rows without function owners,
  non-contiguous per-function ordinals, cross-file owner/type edges, and type
  edges that escape the parameter span.
* Module and path-import item rows publish a parser-owned path node in addition
  to token spans. Resolver passes can use that row as the module/import path
  anchor instead of reclassifying source text or scanning token neighborhoods.
  Readback rejects import rows that do not publish a supported parser-owned
  target record, and rejects shared path-node anchors across module/import
  owners. Quoted/string imports remain fail-closed until represented by a real
  record pipeline.
* `break` and `continue` rows publish explicit control-flow kinds with empty operands.
* `for` rows publish `{ kind, binding token, iterable path node, body block node }`.
  The iterable edge must point at a parser-owned path row, and the body edge is
  published only when the sibling is a parser-owned block, so downstream scope
  builders can keep the loop binding limited to the body span. Syntax validation
  checks the `for` header directly and does not run a separate backward token
  walk over the iterator expression to rediscover the header.
* `if` rows publish `{ kind, condition expression node, then block node,
  optional else block node }`. Readback rejects a then edge unless it lands on
  a parser-owned block row; the else edge is present only for an explicit
  `else` statement, never for a following standalone block statement. The two
  block edges must be distinct, and an else block must not begin before the
  then block has ended.
* `return`, `while`, and assignment rows keep their existing node/token
  operands; token positions are metadata, while child expressions and bodies
  are HIR/tree node references. Readback rejects while body edges that start
  before the parser-owned condition span ends.

We keep the single-thread kernels to cross-check during bring-up and tests.

---

## Performance notes

* **Scans are king.** We reuse the lexer’s 3-stage scan pattern. Most time is spent in 01 (dense scan) and 06 (atomics).
* **Atomics scale well** because each layer has relatively few hits; contention is typically minimal on real world inputs.
* **Layer bound:** worst-case `n_layers ≤ pushes ≤ len(out_sc)`. We can tighten allocation later by sampling block maxima.
* **Host/GPU overlap:** The driver minimizes bind-group churn via a shared cache, and we do seed copies via `copy_buffer_to_buffer` instead of extra shader bindings.

---

## Testing & debugging

* `parse_demo` prints bracket validity and a tree header.
* Set `LANIUS_READBACK=1` (default) to pull buffers back for inspection.
* Timing: `LANIUS_GPU_TIMING=1` prints pass-level timings (hidden on tiny passes).
* We snapshot key buffers to a debug struct when `gpu-debug` is enabled.

Recommended unit cases:

* **Balanced:** deeply nested mixed `()`/`[]`.
* **Typed mismatch:** e.g., `([)]`.
* **Early underflow:** starts with a pop.
* **Large flat:** many siblings to stress histograms and scatter.
* **Tree arity extremes:** all leaves vs chain of unary nodes.

---

## What’s next

1. **Make the grammar conflict-free for real LLP summary composition.**

   * `parse_gen_tables` now computes Pareas-style LLP item sets and rejects the current grammar instead of emitting conflicting tables.
   * Its conflict output is grouped by competing production/gamma pairs so grammar work can be prioritized by source of ambiguity rather than by repeated token-pair rows.
   * Current dominant ambiguity classes are:
     * remaining declaration subcontexts such as type-alias assignment versus const assignment;
     * context-specific list commas in match arms, patterns, type arguments, and enum fields;
     * brace-context ambiguity for match arms, impl methods, trait methods, and ordinary blocks;
     * generic angle brackets versus comparisons, prefix/postfix `Inc`/`Dec`, enum tuple payloads versus calls, and type-reference ampersands versus bitwise ampersands.
   * File-level statements were removed from the generated grammar path, and `else` now follows Pareas's shape: it parses as its own statement for a later fixup pass instead of being encoded as a dangling-else grammar branch.
   * The grammar now consumes semantic `PrefixMinus`/`InfixMinus`, `GroupLParen`/`CallLParen`, `ArrayLBracket`/`IndexLBracket`, function-parameter delimiters, declaration assignment, bound/type colons, member identifiers, and the first argument/array/parameter comma variants where those contexts are already separated.
   * The next parser milestone is to remove those PSLS conflicts, then route tree/HIR construction to the paper-style deterministic LLP table/reduction.

2. **Route full parser-stack summaries through runtime validation.**

   * `sc_projection` is conflict-free in table metadata, but runtime bracket validation still reads a delimiter-safe stream.
   * Add a dedicated parser-stack summary stream so delimiter matching and parser-stack composition do not share one interpretation.

3. **Optional PSE (min-tree) experiment for brackets.**

   * Add `min_tree` build (level-by-level) + “predecessor query” pairing pass.
   * Benchmark vs rank-by-layer; keep the faster default.
   * This can help if we later do **incremental** matching on edited windows.

4. **Memory tightening for layers.**

   * Replace global `n_layers = pushes + 2` with a two-pass bound:

     * pass A: block-local max depth
     * pass B: prefix → global max depth
       Then allocate layer arrays to exactly `maxDepth+2`.

5. **Better diagnostics.**

   * First error index, error kind (underflow, leftover, typed mismatch).
   * Layer-aware mismatch reporting.

6. **Streaming / chunked inputs.**

   * Process `out_sc` in tiles; stitch depth bases across tiles (identical to block scans).
   * Enables truly huge inputs without large transient buffers.

7. **Table compaction & cache.**

   * Compress action tables; reduce `tables_blob` footprint.
   * Persist GPU-side tables across parses when possible.

---

## File index (key shaders)

Brackets:

* `brackets_01_scan_inblock.slang`
* `brackets_02_scan_block_prefix.slang`
* `brackets_03_apply_prefix.slang`
* `brackets_04_histogram_layers.slang`
* `brackets_05_scan_histograms.slang`
* `brackets_06_scatter_by_layer.slang`
* `brackets_pse_04_pair_by_layer.slang`
Tree:

* Active pair stream: adjacent token-pair extraction, prefix packing, and
  `pack_varlen.slang`.
* Legacy LL(1) replay: removed from production dispatch; the live parser gate
  keeps `tree_stream_uses_ll1` false and fails closed if that path is selected.
* Parent recovery: `tree_parent_parallel.slang`
* HIR relation materialization: `hir_semantic_*`,
  `hir_context_relations_*`, and the `hir_*_fields`/`hir_*_scatter` passes

Resident readback validates context relations against parser-owned statement
records before downstream consumers use them, so malformed local context walks
fail closed at the parser boundary.

Method signature flags are parser-owned method records, not general function
records. The `hir_method_signature_status` pass publishes generic/where bits
only for trait methods and impl functions; free functions keep using the
function/type pipeline without leaking into the method table.

Host driver:

* `src/parser/buffers.rs`
* `src/parser/passes/*`
* `src/parser/driver.rs`

---

## FAQ

**Why not a single giant kernel?**
Because WebGPU resource limits, lack of push constants, and better cache behavior with smaller, composable passes. Scans + reductions are the GPU’s sweet spot.
