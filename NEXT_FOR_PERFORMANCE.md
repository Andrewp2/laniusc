sleep well 😴 — here’s a punch-list I’d hit to make the GPU path competitive on big inputs, **no code**, just concrete changes and why they’ll move the needle. I’m ordering by expected impact.

---

## Big wins first

1. **Kill the O(n·log n) global passes in the sum scans.**
   Right now both `scan_sum_inclusive_step` passes do \~log₂(n) full-array ping-pong rounds (twice: `ALL` + `KEPT`). That’s the bulk of your 70 ms on 1e6 bytes.
   **Change:** switch those two scans to the same **two-level scan** you already use for DFA state:

   * do a per-block **inclusive scan** of seeds into shared memory,
   * write one **block total** per workgroup,
   * scan block totals, then
   * apply the carry in a single downsweep.
     That brings each sum from \~20 full sweeps to \~2, and you do it once for both channels (see next point). Touch global memory \~an order of magnitude less.

2. **Scan BOTH seed streams in one pass.**
   You currently run identical pipelines for `ALL` and `KEPT`.
   **Change:** scan a 2-lane value (e.g., `uint2`) or two side-by-side buffers **in a single kernel** and write both finals. One dispatch, one set of reads/writes.

3. **Stop shipping 4 bytes per input byte.**
   `in_bytes` is a `StructuredBuffer<uint>` filled from a `Vec<u32>`; every shader masks `& 0xFF`. That is **4× unnecessary bandwidth**.
   **Change:** upload the source as bytes (ByteAddressBuffer or an 8-bit element view) and either

   * read bytes directly, or
   * read `uint4` and unpack 16 chars per thread (see #5).
     This alone slashes global traffic on the hot kernels.

4. **Halve (or better) the state/flag traffic.**
   Most of your large arrays are `u32` where `u16`/`u8`/bits will do:

   * DFA state indices fit in **u16** (`N_STATES = 32`). Make `f_final`, block vectors, etc., u16.
   * `end_flags`, `filtered_flags`, `s_all_seed`, `s_keep_seed` are 0/1/2 ⇒ **u8** (or even bit-packed).
   * `tok_types` already packs two kinds in 32 bits; keep that or go to two u16s.
   * `next_emit` low-15/high-1 → **u16** storage.
     Less than half the bytes moved = a very noticeable speedup.

5. **Process K>1 bytes per thread (chunk & precompose).**
   The in-block vector scan currently loads one δ₍b₎ vector per lane (32 loads) and does 8 Hillis–Steele rounds over 256 lanes.
   **Change:** have each lane precompose **K consecutive bytes** locally (compose K δ₍b₎ vectors in registers), then participate in the block scan with **one** vector. With K=4 or 8 you cut:

   * table row loads by \~K,
   * sync rounds by \~log₂(K) (because the array you scan shrinks to n/K).
     Implementation stays the same conceptually; lanes simply represent “chunks” instead of single bytes.

6. **Fuse compaction + token build.**
   You run `compact_boundaries[ALL]`, `compact_boundaries[KEPT]`, then `build_tokens`.
   **Change:** write final `(kind,start,len)` **directly** in the KEPT compactor once you have `s_keep_final` and access to `s_all_final` (or the previous-ALL index you already compute). This drops an entire pass and one readback of `end_positions_all`.

---

## Low-risk constant-factor wins

7. **Reuse static tables across calls.**
   In `GpuLexer::lex` you rebuild `StreamingDfa`, pack `next_emit`, and upload `token_map` **every call**. With a fixed grammar, make these **persistent GPU buffers** (they’re small) created in `GpuLexer::new()`.

8. **Prefer constant/read-only memory for tiny tables.**
   `next_emit` (≈32 KiB) and `token_map` (≤128 B) are perfect for uniform/constant memory on many drivers; they get better caching than generic storage.

9. **Tune occupancy vs. shared usage.**
   `func[WORKGROUP_SIZE][N_STATES]` uses \~32 KiB shared per block, which can limit residency to 1 block/SM.
   **Change:** try **`WORKGROUP_SIZE=128`** to enable a second resident block and hide memory latency, or add 1 element of padding to the inner dimension (`N_STATES+1`) to reduce bank conflicts.

10. **Use push constants for per-round params.**
    The scan passes rebuild a tiny uniform buffer every round (`ScanParams`). Push constants avoid per-round buffer churn and binding, especially on Vulkan/DX12.

11. **Single submission until readback.**
    You already reduced submissions to 2. You can often **merge to one** submit (encode all passes, then a single read of `token_count` and `tokens_out`). It trims some driver overhead.

12. **Make `ALL` truly cheap.**
    If you keep the “ALL boundaries” stream, don’t compact it. Instead, during KEPT compaction compute each kept token’s **previous ALL end index** (you already produce `all_index_compact`) and also write the **previous end position** (derive from `end_excl_by_i` or a tiny block-local scratch). Then `build_tokens` no longer needs `end_positions_all`.

---

## Bigger architectural levers (measure & pick one)

13. **Function-ID merge-table path (the “paper way”) when it fits.**
    You already have `scan_merge.slang` and the table builder. For this grammar, measure `m` (distinct unary functions). If **m is in the low thousands**, a u16 **m×m** merge table is tens of MiB and often worth it: the DFA evaluation becomes **one map + O(log n) scans of u16 IDs** (no 32-vector traffic). Keep both backends and pick at runtime by `m` and available memory.

14. **Subgroup (wave) intrinsics inside a block.**
    Replace the Hillis–Steele in-block scan with subgroup shuffles/ballots. It removes most barriers and shared-memory traffic and maps well to 32-/64-lane waves. Slang exposes HLSL-style Wave ops on D3D12 and SPIR-V subgroup ops on Vulkan; gate it behind a feature bit.

---

## Why these help (quick diagnosis)

* The current DFA state path is **O(n·N\_STATES)** in shared-mem work and does **two full in-block scans** (first for block summaries, then re-running in `apply_block_prefix_downsweep`), plus two **O(n·log n)** global sum scans. On 1 MiB that’s a lot of traffic and barriers.
* The CPU beats you simply because it’s **linear**, cache-friendly, and touches far fewer bytes.

Cutting the two sum scans to **2 passes**, dropping input from **4 B → 1 B**, shrinking state/flag types, and doing **K-byte chunking** will drastically reduce memory traffic and dispatch count; that’s where the big wins are.

---

## A quick action plan (what I’d do first)

1. Convert `scan_sum_*` to the block-scan + downsweep pattern and scan both lanes together.
2. Change `in_bytes` to bytes (or `uint4`) and adjust the readers.
3. Down-cast types (`u16`/`u8`) for states/flags/tables.
4. Try K-byte chunking per lane (start with K=4).
5. Re-measure per-pass timings (timestamps) to confirm the scans stopped dominating.
6. If still bandwidth-bound, evaluate the **merge-table** backend for this grammar and pick dynamically.

If you want, I can turn any subset of these into a precise checklist touching the exact files (`buffers.rs`, `scan_sum_inclusive_*`, `scan_inblock_inclusive.slang`, `apply_block_prefix_downsweep.slang`, `GpuLexer::new/lex`, etc.) when you’re back.
