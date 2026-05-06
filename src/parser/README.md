# GPU Parsing — Brackets & Tree (current plan and next steps)

This document explains the **current** GPU strategy for bracket matching and tree construction, how it fits the **WebGPU constraints** we care about (≤10 buffers per pass, modest buffer sizes, no push constants), and what we plan to do **next**.

The code lives under `shaders/parser/*` and is driven by `src/parser/gpu/*`. The demo entry point is `src/bin/parse_demo.rs`.

---

## Design goals (tl;dr)

* **Work-efficient & parallel:** ☑️ O(n) work and large-grid throughput; only O(#blocks) small scans.
* **WebGPU-friendly:** ☑️ ≤10 buffers per pass, no push constants, fixed threadgroups (256).
* **Deterministic pairing:** ☑️ Typed pairing invariant, involutive match map.
* **Good fallbacks:** ☑️ Single-thread “truth” kernels exist for debugging and bring-up.
* **Composable:** ☑️ Reuse the three-phase scan pattern from the lexer.

---

## Input model

From generated pair headers we pack two streams (see `pack_varlen.slang`):

* `out_sc`: **stack-change codes** (u32). *Odd* = push, *even* = pop. Upper bits carry a **typed ID** for the bracket kind (e.g., `(` vs `[`).
* `out_emit`: **production IDs** from the witness-projected LLP pair table. For the checked fixture programs it matches the exact LL(1) production stream and is the stream used for tree construction.

These are produced by:

* `llp_pairs.slang`  → headers per adjacent token pair
* `pack_varlen.slang` → densely packs `out_sc` and `out_emit`

The runtime also runs the block-local seeded LL(1) passes and flattens their
per-block emits into the canonical LL(1) production stream. Those passes provide
exact acceptance/error reporting while the LLP summary-composition path is still
being built.

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
  └─ 07  pair+validate      → match_for_index[], (AND) valid
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

* **07** `brackets_07_pair_and_validate.slang`
  **Pair by (layer, rank)** and write `match_for_index` bi-directionally. If `typed_check != 1`, type IDs are ignored; otherwise, a mismatched open/close type **ANDs** `valid` to 0.

> **Equivalence to PSE:** For properly nested sequences, the `r`-th pop at depth `d` pairs with the `r`-th push at layer `d` (rank-by-layer). This is precisely the predecessor-on-equal-depth selection PSE would find, but without building a min-tree. If we ever need the explicit predecessor structure (e.g., for incremental edits), we can add a min-tree build as an alternative path.

### Complexity & buffers

* **Work:** O(n).
* **Span:** O(log blockSize) per block scan + O(#blocks) small scans + O(1) per event elsewhere.
* **Per-pass bindings:** 6–9, under the “≤10 buffers” policy.
* **Memory:** `n_layers ≤ #pushes ≤ len(out_sc)`. We allocate per-layer arrays with that upper bound (conservative but simple).

### Validity & diagnostics

We expose `{ final_depth, min_depth, valid }`. Pairing still runs even if invalid to provide best-effort matches and help pinpoint the first violation with downstream checks. Typed pairing is optional (`typed_check`).

---

# Part B — Tree construction

Goal: build an **inverted tree** from `emit_stream`:

* `node_kind[i] = emit_stream[i]`
* `parent[i]    = parent index (or 0xFFFFFFFF for root)`

We maintain arity per production in `prod_arity`.

The current tree path is the **tiled stack** builder:

1. **TB1 — local (empty seed):** run the simple stack inside each block; write its **end-stack summary** (`[nodeIndex, remainingChildren]` list).
   *Parents are not final yet* if they cross the block boundary.

2. **TB2 — stitch seeds:** compute each block’s **start-stack** by composing the end-stacks of preceding blocks. This is a tiny pass over **blocks** (not tokens), so it’s cheap.

3. **TB3 — local (seeded):** rerun the same local kernel for each block but **seed** the stack with its start-stack; now every node’s parent is resolved locally; write `parent[]`.

**Why this shape?**
It keeps the easy-to-reason-about sequential logic, but parallelizes across blocks. It scales with SM count, uses very little memory, and avoids per-node binary search. It’s also robust: TB1/TB3 are the same small kernel, which simplifies testing.

> We can cap the per-block summary depth and still be correct for well-formed input; in worst-case nested input, the summary depth may equal block size. For now, we provision conservatively and can optimize later.

---

## Pipeline order (end-to-end)

```
tokens ──► llp_pairs ──► pack_varlen
                       │
                       ├─► BRACKETS (01..07) → { match_for_index[], final_depth, min_depth, valid }
                       │
                       └─► TREE
                           └─ TB1_local → TB2_stitch → TB3_seeded
```

Driver code lives in `src/parser/gpu/driver.rs`, buffers in `src/parser/gpu/buffers.rs`, and pass wrappers in `src/parser/gpu/passes/*`. The driver seeds cursors (`cur_*`) by copying from offsets to keep bindings low.

---

## WebGPU constraints checklist

* **≤10 buffers per pass:** All parser passes stay within 6–9 bindings.
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

We keep the single-thread kernels to cross-check during bring-up and tests.

---

## Performance notes

* **Scans are king.** We reuse the lexer’s 3-stage scan pattern. Most time is spent in 01 (dense scan) and 06 (atomics).
* **Atomics scale well** because each layer has relatively few hits; contention is typically minimal on real world inputs.
* **Layer bound:** worst-case `n_layers ≤ pushes ≤ len(out_sc)`. We can tighten allocation later by sampling block maxima.
* **CPU/gpu overlap:** The driver minimizes bind-group churn via a shared cache, and we do seed copies via `copy_buffer_to_buffer` instead of extra shader bindings.

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

1. **Replace witness-projected LLP tables with real LLP summary composition.**

   * The current pair table is conflict-free for the generated witness set and exact on the fixture programs.
   * The next parser milestone is the paper-style deterministic LLP table/reduction, not adding more ad hoc witnesses.

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
* `brackets_07_pair_and_validate.slang`
Tree:

* Parent recovery: `tree_parent_parallel.slang`

Host driver:

* `src/parser/gpu/buffers.rs`
* `src/parser/gpu/passes/*`
* `src/parser/gpu/driver.rs`

---

## FAQ

**Why not a single giant kernel?**
Because WebGPU resource limits, lack of push constants, and better cache behavior with smaller, composable passes. Scans + reductions are the GPU’s sweet spot.
