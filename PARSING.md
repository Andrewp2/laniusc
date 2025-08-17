Awesome—here’s a clean, GPU-first outline of the **major parser passes** we should build (keeping everything LLP(1,1) and table-driven). I’ll note inputs/outputs and where each pass fits with the Slang/Rust you already have.

# Parser pipeline (major passes)

1. **Retagging (lexer-adjacent, already in repo)**

   * Already done

2. **Pair → Header (LLP headers)**

   * **Why**: for each adjacent token pair `(prev, this)`, look up **stack changes** and **emits** (lengths + tags) with a table; fully parallel per pair.
   * **Input → Output**: token\_kinds, action\_table → `headers[i] = { push_len, emit_len, pop_tag, pop_count }`.
   * **Files**: ✅ already in repo — `shaders/parser/llp_pairs.slang`, host in `src/parser/gpu/passes/llp_pairs.rs`.
   * **Theory**: This is step (1) in the paper’s method.&#x20;

3. **Prefix scans for var-len packing (sizes → offsets)**

   * **Why**: compute **exclusive offsets** over `push_len` and `emit_len` so we can scatter variable-length pieces without atomics.
   * **Input → Output**: `push_len[]`, `emit_len[]` → `push_off[]`, `emit_off[]`, totals.
   * **Files**: Reuse existing scan machinery from the lexer passes; or add a tiny generic scan wrapper in `parser::gpu`.
   * **Theory**: Step (2): “string packing” starts with scans to get offsets.&#x20;

4. **Pack var-len streams (scatter)**

   * **Why**: write the actual **push stream** (with tags) and **emit stream** into dense buffers at the offsets from (3).
   * **Input → Output**: headers + offsets (+ small per-pair dictionaries) → `push_stream[]`, `emit_stream[]`.
   * **Files**: scaffold exists — `shaders/parser/pack_varlen.slang`, host in `src/parser/gpu/passes/pack_varlen.rs`.
   * **Theory**: This completes the paper’s “parallel string packing” step.&#x20;

5. **Bracket-match & validation**

   * **Why**: validate that pushes/pops balance globally **and** by **type**; also produce the pairing indices we’ll reuse.
   * **Input → Output**: `push_stream[]` / `pop_stream[]` (implicitly in headers) → validity bit, first error (if any), `match_of_close[]` (or `match_of_open[]`).
   * **Files**: new Slang kernel (e.g., `shaders/parser/brackets_match.slang`) + host pass.
   * **Theory**: paper uses a **previous-smaller-or-equal** structure to do bracket matching in $O(\log n)$ parallel time. &#x20;
     It’s step (3) in their outline.&#x20;

6. **Left-parse (rule sequence) stitch**

   * **Why**: concatenate per-pair **emits** into the final **left-most derivation** (rule id sequence); same packing trick as (4).
   * **Input → Output**: `emit_stream[]` (+ pair order) → `left_parse_rules[]`.
   * **Files**: small Slang kernel (e.g., `shaders/parser/emit_stitch.slang`) that is essentially another pack/concatenate.
   * **Theory**: “Map pairs → portions of parse; concatenate to a left-most parse.”&#x20;

7. **Parse-tree build (inverted tree arrays)**

   * **Why**: convert the left-parse into an **inverted tree** representation: `node_kind[]`, `parent[]` (GPU-friendly).
   * **Input → Output**: `left_parse_rules[]` (+ bracket matches) → `node_kind[]`, `parent[]` (and optional `first_child[]` / `next_sibling[]`).
   * **Files**: new Slang kernel (e.g., `shaders/parser/tree_build.slang`) + host pass.
   * **Theory**: The paper recommends the inverted representation for uniform, compact GPU storage; they show how to compute parents and use common tree subroutines. &#x20;

8. **Common tree ops (utility passes)**

   * **Why**: shared building blocks used by later stages and mitigations (semantic passes, compaction, root finding).
   * **Examples**: **Tree compactification** (mark-and-compact), **find roots**, **reparenting** helpers.
   * **Theory**: described as standard GPU tree utilities. &#x20;

---

## Where this matches the paper (at a glance)

* The 3 core ideas—**pair→actions**, **parallel packing**, **parallel bracket matching**—are the backbone; then **concatenate emits** and **build the tree**. That’s exactly how they get LLP parsing to $O(\log n)$ parallel depth with table-driven data. &#x20;

---

## What we already have vs. what’s next

* ✅ **Implemented**: (1) Retagging; (2) Pair→Header; host readback via staging buffer.
* 🔜 **Short next steps**: (3) GPU scans (reuse lexer scans), (4) finish `pack_varlen`, (5) add `brackets_match`, (6) emit stitch, (7) tree build, (8) utilities.

If you want, I can sketch the buffer shapes we’ll standardize for (4)–(7) so the Slang kernels line up cleanly with `encase` on the Rust side.
