// Builds only when compiled with `--features gpu-debug`.
#![cfg(feature = "gpu-debug")]

use std::cmp::min;

use wgpu::MapMode;

use crate::{
    gpu::debug::DebugBuffer,
    lexer::{
        gpu::debug::DebugOutput,
        tables::compact::load_compact_tables_from_bytes, // ⬅ add this
        tables::dfa::N_STATES, // compile-time N_STATES used by Slang shaders
    },
};

const FUNC_BLOCK_WIDTH: u32 = 128; // scan_inblock_inclusive / block_summaries
const PAIR_BLOCK_WIDTH: u32 = 256; // sum_inblock_pairs

// --------------------- small helpers ---------------------

fn ceil_div_u32(a: u32, b: u32) -> u32 {
    if a == 0 { 0 } else { 1 + (a - 1) / b }
}

/// Map a `DebugBuffer` to a Vec<u32> (little-endian). Returns `None` if missing.
fn map_u32s(device: &wgpu::Device, db: &DebugBuffer) -> Option<Vec<u32>> {
    let b = db.buffer.as_ref()?;
    let slice = b.slice(..);
    slice.map_async(MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);
    let view = slice.get_mapped_range();
    let mut out = Vec::<u32>::with_capacity(db.byte_len / 4);

    for chunk in view.chunks_exact(4) {
        let mut le = [0u8; 4];
        le.copy_from_slice(chunk);
        out.push(u32::from_le_bytes(le));
    }
    drop(view);
    b.unmap();
    Some(out)
}

fn map_first_u32(device: &wgpu::Device, db: &DebugBuffer) -> Option<u32> {
    map_u32s(device, db).and_then(|v| v.get(0).copied())
}

fn map_u8s(device: &wgpu::Device, db: &DebugBuffer) -> Option<Vec<u8>> {
    let b = db.buffer.as_ref()?;
    let slice = b.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);
    let view = slice.get_mapped_range();
    let mut out = Vec::<u8>::with_capacity(db.byte_len);
    out.extend_from_slice(&view);
    drop(view);
    b.unmap();
    Some(out)
}

/// Build CPU reference arrays by walking the DFA tables once over the CPU input.
/// Produces per-byte next-state, packed flags, prefixes, and end_excl_by_i.
fn cpu_tables_walk(
    input_bytes: &[u8],
) -> Option<(Vec<u32>, Vec<u32>, Vec<u32>, Vec<u32>, Vec<u32>)> {
    use crate::lexer::tables::{
        compact::load_compact_tables_from_bytes,
        dfa::N_STATES,
        tokens::TokenKind,
    };

    const COMPACT_BIN: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tables/lexer_tables.bin"
    ));
    let (n_states_from_file, next_emit_words, token_map) =
        load_compact_tables_from_bytes(COMPACT_BIN).ok()?;
    if n_states_from_file != N_STATES {
        return None;
    }

    let skip_kinds = [
        TokenKind::White as u32,
        TokenKind::LineComment as u32,
        TokenKind::BlockComment as u32,
        u32::MAX,
    ];
    let mut is_skip = |tk: u32| {
        tk == skip_kinds[0] || tk == skip_kinds[1] || tk == skip_kinds[2] || tk == skip_kinds[3]
    };

    let n = input_bytes.len();
    let mut f_final = vec![0u32; n];
    let mut flags = vec![0u32; n]; // bits: 0=EMIT, 1=EOF, 2=KEEP_EMIT, 3=KEEP_EOF
    let mut s_all = vec![0u32; n];
    let mut s_keep = vec![0u32; n];
    let mut end_excl_by_i = vec![0u32; n];

    let mut prev_state: u32 = 0;
    let mut acc_all: u32 = 0;
    let mut acc_keep: u32 = 0;

    for i in 0..n {
        let b = input_bytes[i] as usize;

        let idx = b * (N_STATES as usize) + (prev_state as usize);
        let word = next_emit_words[idx >> 1];
        let lane16 = if (idx & 1) == 0 {
            word & 0xFFFF
        } else {
            (word >> 16) & 0xFFFF
        };

        let emit_here = (lane16 & 0x8000) != 0;
        let next_state = (lane16 & 0x7FFF) as u32;

        let at_eof = i + 1 == n;
        let tk_emit = token_map[prev_state as usize];
        let tk_eof = token_map[next_state as usize];

        let keep_emit = !is_skip(tk_emit) && tk_emit != u32::MAX;
        let keep_eof = !is_skip(tk_eof) && tk_eof != u32::MAX;
        let eof_here = at_eof && tk_eof != u32::MAX;

        let mut f = 0u32;
        if emit_here {
            f |= 1;
        } // EMIT
        if eof_here {
            f |= 2;
        } // EOF
        if keep_emit {
            f |= 4;
        } // KEEP_EMIT
        if keep_eof {
            f |= 8;
        } // KEEP_EOF
        flags[i] = f;

        acc_all = acc_all.saturating_add((emit_here as u32) + (eof_here as u32));
        acc_keep = acc_keep
            .saturating_add(((emit_here && keep_emit) as u32) + ((eof_here && keep_eof) as u32));
        s_all[i] = acc_all;
        s_keep[i] = acc_keep;

        end_excl_by_i[i] = if at_eof && keep_eof && !(keep_emit && emit_here) {
            n as u32
        } else {
            i as u32
        };

        f_final[i] = next_state;
        prev_state = next_state;
    }

    Some((f_final, flags, s_all, s_keep, end_excl_by_i))
}

// Compare PF_EMIT and f_final vs CPU reference built from the CPU input bytes.
fn check_emit_and_state_against_cpu_input(
    input: &str,
    device: &wgpu::Device,
    dbg: &DebugOutput,
    n_input_bytes: u32,
) {
    // GPU buffers we compare against
    let flags_gpu = match map_u32s(device, &dbg.gpu.flags_packed) {
        Some(v) => v,
        None => {
            println!("[dbg] flags_packed not available for emit/state cross-check");
            return;
        }
    };
    let f_final_gpu = match map_u32s(device, &dbg.gpu.f_final) {
        Some(v) => v,
        None => {
            println!("[dbg] f_final not available for emit/state cross-check");
            return;
        }
    };

    let bytes = input.as_bytes();
    let Some((f_final_cpu, flags_cpu, _, _, _)) = cpu_tables_walk(bytes) else {
        println!("[dbg] CPU tables walk unavailable (bad tables or N_STATES mismatch)");
        return;
    };

    let n = usize::min(bytes.len(), usize::min(flags_gpu.len(), f_final_gpu.len()));
    let mut emit_gpu_total: u64 = 0;
    let mut emit_cpu_total: u64 = 0;
    let mut first_emit_mis: Option<usize> = None;
    let mut first_state_mis: Option<usize> = None;

    for i in 0..n {
        let eg = (flags_gpu[i] & 1) != 0;
        let ec = (flags_cpu[i] & 1) != 0;
        if eg {
            emit_gpu_total += 1;
        }
        if ec {
            emit_cpu_total += 1;
        }
        if eg != ec && first_emit_mis.is_none() {
            first_emit_mis = Some(i);
        }

        if f_final_gpu[i] != f_final_cpu[i] && first_state_mis.is_none() {
            first_state_mis = Some(i);
        }
    }

    println!(
        "[dbg] EMIT totals: GPU={}  CPU={}  Δ={}",
        emit_gpu_total,
        emit_cpu_total,
        (emit_cpu_total as i64 - emit_gpu_total as i64)
    );

    if let Some(i) = first_emit_mis {
        let lo = i.saturating_sub(3);
        let hi = usize::min(n, i + 4);
        println!(
            "[dbg] ✗ first EMIT mismatch at i={}. window [{}..{}):",
            i, lo, hi
        );
        for j in lo..hi {
            println!(
                "      i={:>7}  byte={:>3} '{}'  EMIT gpu={} cpu={}  f_final gpu={} cpu={}",
                j,
                bytes[j],
                bytes[j] as char,
                (flags_gpu[j] & 1) != 0,
                (flags_cpu[j] & 1) != 0,
                f_final_gpu[j],
                f_final_cpu[j]
            );
        }
    } else {
        println!(
            "[dbg] PF_EMIT matches CPU reference for first {} bytes ✓",
            n
        );
    }

    if let Some(i) = first_state_mis {
        let lo = i.saturating_sub(3);
        let hi = usize::min(n, i + 4);
        println!(
            "[dbg] ✗ first f_final mismatch at i={}. window [{}..{}):",
            i, lo, hi
        );
        for j in lo..hi {
            println!(
                "      i={:>7}  state gpu={}  cpu={}",
                j, f_final_gpu[j], f_final_cpu[j]
            );
        }
    } else {
        println!(
            "[dbg] f_final equals CPU next-state for first {} bytes ✓",
            n
        );
    }
}

// Compare prefix arrays and end_excl_by_i to CPU oracles built from input.
fn check_prefixes_and_excl_against_cpu_input(
    input: &str,
    device: &wgpu::Device,
    dbg: &DebugOutput,
) {
    let Some((_, _, s_all_cpu, s_keep_cpu, excl_cpu)) = cpu_tables_walk(input.as_bytes()) else {
        println!("[dbg] CPU tables walk unavailable (bad tables or N_STATES mismatch)");
        return;
    };

    let s_all_gpu = map_u32s(device, &dbg.gpu.s_all_final);
    let s_keep_gpu = map_u32s(device, &dbg.gpu.s_keep_final);
    let excl_gpu = map_u32s(device, &dbg.gpu.end_excl_by_i);

    if let (Some(ga), Some(ka)) = (s_all_gpu.as_ref(), Some(&s_all_cpu)) {
        let n = usize::min(ga.len(), ka.len());
        if let Some(i) = (0..n).find(|&i| ga[i] != ka[i]) {
            println!(
                "[dbg] ✗ s_all mismatch at i={} (gpu={} cpu={})",
                i, ga[i], ka[i]
            );
        } else {
            println!("[dbg] s_all matches CPU reference ✓ ({} entries)", n);
        }
    }

    if let (Some(gk), Some(kk)) = (s_keep_gpu.as_ref(), Some(&s_keep_cpu)) {
        let n = usize::min(gk.len(), kk.len());
        if let Some(i) = (0..n).find(|&i| gk[i] != kk[i]) {
            println!(
                "[dbg] ✗ s_keep mismatch at i={} (gpu={} cpu={})",
                i, gk[i], kk[i]
            );
        } else {
            println!("[dbg] s_keep matches CPU reference ✓ ({} entries)", n);
        }
    }

    if let (Some(ge), Some(ke)) = (excl_gpu.as_ref(), Some(&excl_cpu)) {
        let n = usize::min(ge.len(), ke.len());
        if let Some(i) = (0..n).find(|&i| ge[i] != ke[i]) {
            println!(
                "[dbg] ✗ end_excl_by_i mismatch at i={} (gpu={} cpu={})",
                i, ge[i], ke[i]
            );
        } else {
            println!(
                "[dbg] end_excl_by_i matches CPU reference ✓ ({} entries)",
                n
            );
        }
    }
}

fn check_monotonic_increasing_within_bounds(label: &str, v: &[u32], max_ok: u32) {
    if v.is_empty() {
        println!("[dbg] {label}: empty (len=0)");
        return;
    }
    if v[0] > max_ok {
        println!(
            "[dbg] {label}: ✗ BAD at 0 (curr={}, max_ok={})",
            v[0], max_ok
        );
        return;
    }
    for i in 1..v.len() {
        if v[i] <= v[i - 1] || v[i] > max_ok {
            println!(
                "[dbg] {label}: ✗ BAD at {i} (prev={}, curr={}, len={}, max_ok={})",
                v[i - 1],
                v[i],
                v.len(),
                max_ok
            );
            return;
        }
    }
    println!(
        "[dbg] {label}: strictly increasing & ≤ {max_ok} ✓ OK (len={})",
        v.len()
    );
}

fn check_all_less_than(label: &str, v: &[u32], bound: u32) {
    let bad = v.iter().position(|&x| x >= bound);
    if let Some(i) = bad {
        println!(
            "[dbg] {label}: ✗ value {} at index {} is ≥ bound {} (len={})",
            v[i],
            i,
            bound,
            v.len()
        );
    } else {
        println!(
            "[dbg] {label}: all values < {} ✓ OK (len={})",
            bound,
            v.len()
        );
    }
}

// Treat a flat [nb * N_STATES] function table as f[i][s] = vec[i*N_STATES + s].
fn compose_row(prev: &[u32], _nb: u32, i: u32, stride: u32, s: u32) -> u32 {
    let idx_a = ((i - stride) * (N_STATES as u32) + s) as usize;
    let a = prev[idx_a];
    let idx_ba = (i * (N_STATES as u32) + a) as usize;
    prev[idx_ba]
}

fn check_capacity_and_density(device: &wgpu::Device, dbg: &DebugOutput, n_input_bytes: u32) {
    let s_all_last = map_u32s(device, &dbg.gpu.s_all_final).and_then(|v| v.last().copied());
    let s_keep_last = map_u32s(device, &dbg.gpu.s_keep_final).and_then(|v| v.last().copied());

    // 🤖 How many u32 slots did we allocate for compaction outputs?
    let cap_kept = (dbg.gpu.end_positions.byte_len / 4) as u32;
    let cap_all = (dbg.gpu.end_positions_all.byte_len / 4) as u32;

    if let Some(k) = s_keep_last {
        if k == cap_kept && k > 0 {
            println!(
                "[dbg] ✗ kept_count ({}) == end_positions[KEPT] capacity ({}). Likely hit cap.",
                k, cap_kept
            );
        }
        // 🤖 sanity: density too low usually means EMIT underflow
        let dens = (k as f64) / (n_input_bytes as f64);
        if dens < 1.0 / 4096.0 {
            println!(
                "[dbg] ⚠ kept density is very low ({:.6} per byte). Flags/emit may be underflowing.",
                dens
            );
        }
    } else {
        println!("[dbg] s_keep_final not available for density/capacity check");
    }

    if let Some(a) = s_all_last {
        if a == cap_all && a > 0 {
            println!(
                "[dbg] ✗ all_count ({}) == end_positions_all[ALL] capacity ({}). Likely hit cap.",
                a, cap_all
            );
        }
        let dens = (a as f64) / (n_input_bytes as f64);
        if dens < 1.0 / 2048.0 {
            println!(
                "[dbg] ⚠ all density is very low ({:.6} per byte). PF_EMIT / PF_EOF may be wrong.",
                dens
            );
        }
    } else {
        println!("[dbg] s_all_final not available for density/capacity check");
    }
}

// --------------------- detailed checks ---------------------

/// Validate flags vs. s_* finals (per-element deltas) and EOF-exclusive-ends.
// --------------------- detailed checks ---------------------

/// Validate flags vs. s_* finals (per-element deltas) and EOF-exclusive-ends.
fn check_flags_vs_prefix_and_excl(device: &wgpu::Device, dbg: &DebugOutput, n_input_bytes: u32) {
    let flags = match map_u32s(device, &dbg.gpu.flags_packed) {
        Some(v) => v,
        None => {
            println!("[dbg] flags_packed not available");
            return;
        }
    };

    let s_all = match map_u32s(device, &dbg.gpu.s_all_final) {
        Some(v) => v,
        None => {
            println!("[dbg] s_all_final not available");
            return;
        }
    };
    let s_keep = match map_u32s(device, &dbg.gpu.s_keep_final) {
        Some(v) => v,
        None => {
            println!("[dbg] s_keep_final not available");
            return;
        }
    };

    if (s_all.len() as u32) != n_input_bytes
        || (s_keep.len() as u32) != n_input_bytes
        || (flags.len() as u32) != n_input_bytes
    {
        println!(
            "[dbg] flags/prefix size mismatch: flags={} s_all={} s_keep={} n={}",
            flags.len(),
            s_all.len(),
            s_keep.len(),
            n_input_bytes
        );
        // 🤖 continue with min so we still get signal
    }

    let n = min(
        n_input_bytes as usize,
        min(flags.len(), min(s_all.len(), s_keep.len())),
    );

    // ---- histogram of flag usage + density ----
    // 🤖 This tells us instantly whether EMIT is suspiciously rare
    let mut cnt_emit: u64 = 0;
    let mut cnt_eof: u64 = 0;
    let mut cnt_kemit: u64 = 0;
    let mut cnt_keof: u64 = 0;

    // Also check: if EMIT is set, tok_types.low16 must not be 0xFFFF
    let mut emit_kind_mismatch: u64 = 0;
    let types_opt = map_u32s(device, &dbg.gpu.tok_types);

    let mut ok = true;
    for i in 0..n {
        let f = flags[i];
        let emit = (f & 1) != 0;
        let eof = (f & 2) != 0;
        let keep_emit = (f & 4) != 0;
        let keep_eof = (f & 8) != 0;

        if emit {
            cnt_emit += 1;
        }
        if eof {
            cnt_eof += 1;
        }
        if keep_emit {
            cnt_kemit += 1;
        }
        if keep_eof {
            cnt_keof += 1;
        }

        let prev_all = if i == 0 { 0 } else { s_all[i - 1] };
        let prev_keep = if i == 0 { 0 } else { s_keep[i - 1] };

        let delta_all = s_all[i].saturating_sub(prev_all);
        let delta_keep = s_keep[i].saturating_sub(prev_keep);

        let expect_all = (emit as u32) + (eof as u32); // ∈ {0,1,2}
        let expect_keep = (emit && keep_emit) as u32 + (eof && keep_eof) as u32; // ∈ {0,1}

        if delta_all != expect_all {
            println!(
                "[dbg] ✗ s_all delta mismatch at i={} (got {}, expect {} from flags {:b})",
                i, delta_all, expect_all, f
            );
            ok = false;
            break;
        }
        if delta_keep != expect_keep {
            println!(
                "[dbg] ✗ s_keep delta mismatch at i={} (got {}, expect {} from flags {:b})",
                i, delta_keep, expect_keep, f
            );
            ok = false;
            break;
        }

        // ---- EMIT => kind(low16) must exist (not 0xFFFF) ----
        // 🤖 If this fires often, next_emit emit-bit or token_map packing is wrong
        if emit && keep_emit {
            if let Some(ref types) = types_opt {
                if i < types.len() {
                    let t = types[i] & 0xFFFF;
                    if t == 0xFFFF {
                        emit_kind_mismatch += 1;
                    }
                }
            }
        }
    }
    if ok {
        println!(
            "[dbg] flags vs. s_all/s_keep deltas ✓ OK for first {} bytes",
            n
        );
    }

    // ---- print histogram & density ----
    let nkb = (n_input_bytes as f64) / 1024.0;
    println!(
        "[dbg] flags histogram: EMIT={} ({:.2}/KB)  EOF={} ({:.4}/KB)  KEEP_EMIT={}  KEEP_EOF={}",
        cnt_emit,
        (cnt_emit as f64) / nkb,
        cnt_eof,
        (cnt_eof as f64) / nkb,
        cnt_kemit,
        cnt_keof
    );
    if emit_kind_mismatch > 0 {
        println!(
            "[dbg] ✗ EMIT set but tok_types.low16==0xFFFF for {} positions",
            emit_kind_mismatch
        );
    } else {
        println!("[dbg] EMIT ⇒ kind(low16) check ✓ OK");
    }

    // EOF-exclusive-end correctness for finalize pass:
    // end_excl_by_i[i] == n when (at_eof && keep_eof && (!keep_emit || !emit_here)), else == i.
    if let Some(end_excl) = map_u32s(device, &dbg.gpu.end_excl_by_i) {
        let mut ok2 = true;
        for i in 0..n {
            let f = flags[i];
            let emit = (f & 1) != 0;
            let keep_emit = (f & 4) != 0;
            let keep_eof = (f & 8) != 0;
            let at_eof = ((i as u32) + 1 == n_input_bytes);

            let expect = if at_eof && keep_eof && (!keep_emit || !emit) {
                n_input_bytes
            } else {
                i as u32
            };
            if end_excl[i] != expect {
                println!(
                    "[dbg] ✗ end_excl_by_i mismatch at i={} (got {}, expect {})",
                    i, end_excl[i], expect
                );
                ok2 = false;
                break;
            }
        }
        if ok2 {
            println!("[dbg] end_excl_by_i vs. flags ✓ OK");
        }
    } else {
        println!("[dbg] end_excl_by_i not available");
    }
}

/// Validate per-round function block scan (nb * N_STATES per round).
fn check_func_scan_rounds(device: &wgpu::Device, dbg: &DebugOutput, n_input_bytes: u32) {
    let nb = ceil_div_u32(n_input_bytes, FUNC_BLOCK_WIDTH);

    if dbg.gpu.func_scan_rounds.is_empty() {
        println!("[dbg] func_scan_rounds: (none captured) — skipping");
        return;
    }

    // Map all rounds
    let mut rounds: Vec<Vec<u32>> = Vec::new();
    for (r, db) in dbg.gpu.func_scan_rounds.iter().enumerate() {
        if let Some(v) = map_u32s(device, db) {
            let expect = (nb as usize) * (N_STATES as usize);
            if v.len() != expect {
                println!(
                    "[dbg] func_scan_rounds[{r}]: ✗ size {} != nb*N_STATES {}",
                    v.len(),
                    expect
                );
            } else {
                println!("[dbg] func_scan_rounds[{r}]: len={} ✓", v.len());
            }
            check_all_less_than(
                &format!("func_scan_rounds[{r}] values"),
                &v,
                N_STATES.try_into().unwrap(),
            );
            rounds.push(v);
        } else {
            println!("[dbg] func_scan_rounds[{r}] not available");
        }
    }

    // Composition property across rounds:
    // for r>=1:
    //   - i < 2^r: row must equal previous round's row (copy-through)
    //   - i >= 2^r: new[i] = prev[i] ∘ prev[i - 2^r]
    for r in 1..rounds.len() {
        let prev = &rounds[r - 1];
        let curr = &rounds[r];
        let stride = 1u32 << r;

        for i in 0..nb {
            for s in 0..N_STATES {
                let idx: usize = (i * (N_STATES as u32) + s as u32) as usize;
                if i < stride {
                    if curr[idx] != prev[idx] {
                        println!(
                            "[dbg] ✗ func round[{r}]: copy-through mismatch at block {}, state {} (curr={}, prev={})",
                            i, s, curr[idx], prev[idx]
                        );
                        return;
                    }
                } else {
                    let expect = compose_row(prev, nb, i, stride, s as u32);
                    if curr[idx] != expect {
                        println!(
                            "[dbg] ✗ func round[{r}]: composition mismatch at block {}, state {} (got={}, expect={})",
                            i, s, curr[idx], expect
                        );
                        return;
                    }
                }
            }
        }
    }
    println!("[dbg] func_scan_rounds composition ✓ OK");

    // Final equality to block_prefix (last writer copied by host)
    if let Some(bp) = map_u32s(device, &dbg.gpu.block_prefix) {
        if let Some(last) = rounds.last() {
            if bp == *last {
                println!("[dbg] block_prefix == func_scan_rounds[last] ✓ OK");
            } else {
                println!(
                    "[dbg] ✗ block_prefix != func_scan_rounds[last] (size {} vs {})",
                    bp.len(),
                    last.len()
                );
            }
        }
    } else {
        println!("[dbg] block_prefix not available to compare against func_scan_rounds");
    }
}

/// Validate per-round pair scan (uint2 per block) and equivalence to block_prefix_pair.
fn check_pair_scan_rounds(device: &wgpu::Device, dbg: &DebugOutput, n_input_bytes: u32) {
    let nb = ceil_div_u32(n_input_bytes, PAIR_BLOCK_WIDTH);

    if dbg.gpu.pair_scan_rounds.is_empty() {
        println!("[dbg] pair_scan_rounds: (none captured) — skipping");
        return;
    }

    // Map each round as flat u32s (len = nb * 2).
    let mut rounds: Vec<Vec<u32>> = Vec::new();
    for (r, db) in dbg.gpu.pair_scan_rounds.iter().enumerate() {
        if let Some(v) = map_u32s(device, db) {
            let expect = (nb as usize) * 2;
            if v.len() != expect {
                println!(
                    "[dbg] pair_scan_rounds[{r}]: ✗ size {} != nb*2 {}",
                    v.len(),
                    expect
                );
            } else {
                println!("[dbg] pair_scan_rounds[{r}]: len={} ✓", v.len());
            }
            rounds.push(v);
        } else {
            println!("[dbg] pair_scan_rounds[{r}] not available");
        }
    }

    // Across rounds: i < 2^r => copy-through; i >= 2^r => add(prev[i], prev[i - 2^r])
    for r in 1..rounds.len() {
        let prev = &rounds[r - 1];
        let curr = &rounds[r];
        let stride = 1u32 << r;

        for i in 0..nb {
            let ix = (2 * i) as usize;
            if i < stride {
                if curr[ix] != prev[ix] || curr[ix + 1] != prev[ix + 1] {
                    println!(
                        "[dbg] ✗ pair round[{r}]: copy-through mismatch at block {} (curr={:?}, prev={:?})",
                        i,
                        &curr[ix..ix + 2],
                        &prev[ix..ix + 2]
                    );
                    return;
                }
            } else {
                let a_ix = (2 * (i - stride)) as usize;
                let expect_x = prev[ix].saturating_add(prev[a_ix]);
                let expect_y = prev[ix + 1].saturating_add(prev[a_ix + 1]);
                if curr[ix] != expect_x || curr[ix + 1] != expect_y {
                    println!(
                        "[dbg] ✗ pair round[{r}]: add mismatch at block {} (got=({},{}) expect=({},{}) )",
                        i,
                        curr[ix],
                        curr[ix + 1],
                        expect_x,
                        expect_y
                    );
                    return;
                }
            }
        }
    }
    println!("[dbg] pair_scan_rounds composition ✓ OK");

    // Map once and reuse for both checks below
    let bp = map_u32s(device, &dbg.gpu.block_prefix_pair);

    // Final equality to block_prefix_pair (host copy)
    if let Some(bp) = bp.as_ref() {
        if let Some(last) = rounds.last() {
            if bp.as_slice() == last.as_slice() {
                println!("[dbg] block_prefix_pair == pair_scan_rounds[last] ✓ OK");
            } else {
                println!(
                    "[dbg] ✗ block_prefix_pair != pair_scan_rounds[last] (size {} vs {})",
                    bp.len(),
                    last.len()
                );
            }
        }
    } else {
        println!("[dbg] block_prefix_pair not available to compare against pair_scan_rounds");
    }

    // Cross-check: block_prefix_pair[block] equals s_* at end of block.
    if let (Some(bp), Some(s_all), Some(s_keep)) = (
        bp.as_ref(),
        map_u32s(device, &dbg.gpu.s_all_final),
        map_u32s(device, &dbg.gpu.s_keep_final),
    ) {
        let count_blocks = nb as usize;
        let mut ok = true;
        for b in 0..count_blocks {
            let last_idx =
                min(n_input_bytes, (b as u32 + 1) * PAIR_BLOCK_WIDTH).saturating_sub(1) as usize;
            if last_idx >= s_all.len() || last_idx >= s_keep.len() {
                println!(
                    "[dbg] pair cross-check: last_idx {} out of range (s_all={}, s_keep={})",
                    last_idx,
                    s_all.len(),
                    s_keep.len()
                );
                ok = false;
                break;
            }
            let bp_x = bp[2 * b];
            let bp_y = bp[2 * b + 1];
            if bp_x != s_all[last_idx] || bp_y != s_keep[last_idx] {
                println!(
                    "[dbg] ✗ block_prefix_pair[{}] mismatch: got ({}, {}), expect ({}, {})",
                    b, bp_x, bp_y, s_all[last_idx], s_keep[last_idx]
                );
                ok = false;
                break;
            }
        }
        if ok {
            println!("[dbg] block_prefix_pair matches s_* at block ends ✓ OK");
        }
    } else {
        println!(
            "[dbg] s_all_final / s_keep_final not available for block_prefix_pair cross-check"
        );
    }
}

/// Validate compacted arrays and tokens_out assembly.
fn check_compaction_and_tokens(device: &wgpu::Device, dbg: &DebugOutput, n_input_bytes: u32) {
    let kept_count = map_first_u32(device, &dbg.gpu.token_count);
    let all_count = map_first_u32(device, &dbg.gpu.token_count_all);

    let ends_kept = map_u32s(device, &dbg.gpu.end_positions);
    let ends_all = map_u32s(device, &dbg.gpu.end_positions_all);

    if let (Some(v), Some(kc)) = (ends_kept.as_ref(), kept_count) {
        if v.len() < kc as usize {
            println!(
                "[dbg] ✗ end_positions[KEPT] shorter than token_count ({} < {})",
                v.len(),
                kc
            );
        } else {
            check_monotonic_increasing_within_bounds(
                "end_positions[KEPT]",
                &v[..kc as usize],
                n_input_bytes,
            );
        }
    } else {
        println!("[dbg] end_positions[KEPT] or token_count not available");
    }

    if let (Some(v), Some(ac)) = (ends_all.as_ref(), all_count) {
        if v.len() < ac as usize {
            println!(
                "[dbg] ✗ end_positions_all[ALL] shorter than token_count_all ({} < {})",
                v.len(),
                ac
            );
        } else {
            check_monotonic_increasing_within_bounds(
                "end_positions_all[ALL]",
                &v[..ac as usize],
                n_input_bytes,
            );
        }
    } else {
        println!("[dbg] end_positions_all[ALL] or token_count_all not available");
    }

    // all_index_compact should be strictly increasing in [1..=all_count]
    if let (Some(aic), Some(ac)) = (map_u32s(device, &dbg.gpu.all_index_compact), all_count) {
        if let Some(kc) = kept_count {
            let upto = min(kc as usize, aic.len());
            let mut ok = true;
            let mut prev = 0u32;
            for i in 0..upto {
                let v = aic[i];
                if v == 0 || v > ac {
                    println!(
                        "[dbg] ✗ all_index_compact[{}] out of range: {} (all_count={})",
                        i, v, ac
                    );
                    ok = false;
                    break;
                }
                if i > 0 && v <= prev {
                    println!(
                        "[dbg] ✗ all_index_compact not strictly increasing at {} (prev={}, curr={})",
                        i, prev, v
                    );
                    ok = false;
                    break;
                }
                prev = v;
            }
            if ok {
                println!(
                    "[dbg] all_index_compact: strictly increasing in 1..=all_count ✓ OK (len={})",
                    upto
                );
            }
        } else {
            println!("[dbg] token_count not available for all_index_compact check");
        }
    } else {
        println!("[dbg] all_index_compact or token_count_all not available");
    }

    // tokens_out correctness vs. (end_positions, types_compact, end_positions_all, all_index_compact)
    if let (Some(kc), Some(ends_k), Some(types_k), Some(aic), Some(ends_all_vec), Some(tokens)) = (
        kept_count,
        ends_kept,
        map_u32s(device, &dbg.gpu.types_compact),
        map_u32s(device, &dbg.gpu.all_index_compact),
        ends_all,
        map_u32s(device, &dbg.gpu.tokens_out),
    ) {
        let upto = min(
            kc as usize,
            min(
                ends_k.len(),
                min(types_k.len(), min(aic.len(), tokens.len() / 3)),
            ),
        );
        let mut ok = true;
        for k in 0..upto {
            let end_excl = ends_k[k];
            let all_idx = aic[k]; // 1-based
            let all_zero = if all_idx == 0 { 0 } else { all_idx - 1 };
            let start = if all_zero == 0 {
                0
            } else {
                ends_all_vec[(all_zero - 1) as usize]
            };

            let rec_kind = tokens[3 * k + 0];
            let rec_start = tokens[3 * k + 1];
            let rec_len = tokens[3 * k + 2];

            let expect_len = end_excl.saturating_sub(start);
            if rec_start != start || rec_len != expect_len {
                println!(
                    "[dbg] ✗ tokens_out[{}] mismatch: got (kind={}, start={}, len={}), expect start={}, len={} (end_excl={}, all_idx={})",
                    k, rec_kind, rec_start, rec_len, start, expect_len, end_excl, all_idx
                );
                ok = false;
                break;
            }
            if end_excl > n_input_bytes {
                println!(
                    "[dbg] ✗ tokens_out[{}] end_excl {} > n={}",
                    k, end_excl, n_input_bytes
                );
                ok = false;
                break;
            }
            if rec_len == 0 {
                println!("[dbg] ✗ tokens_out[{}] zero-length token (start==end)", k);
                ok = false;
                break;
            }
        }
        if ok {
            println!(
                "[dbg] tokens_out fields vs. compaction inputs ✓ OK ({} tokens checked)",
                upto
            );
        }
    } else {
        println!("[dbg] tokens_out or required compaction inputs not available");
    }
}

/// Trivial range checks for some raw buffers we also capture.
fn check_simple_ranges(device: &wgpu::Device, dbg: &DebugOutput) {
    if let Some(v) = map_u32s(device, &dbg.gpu.block_summaries) {
        check_all_less_than("block_summaries (values)", &v, N_STATES.try_into().unwrap());
    } else {
        println!("[dbg] block_summaries not available");
    }

    if let Some(v) = map_u32s(device, &dbg.gpu.f_final) {
        check_all_less_than("f_final (states)", &v, N_STATES.try_into().unwrap());
    } else {
        println!("[dbg] f_final not available");
    }

    // tok_types low16 must be 0xFFFF when KEEP_EMIT=0; high16 must be 0xFFFF when KEEP_EOF=0.
    // We can't fully validate kind IDs without the token map, but we can enforce this mask rule.
    if let (Some(types), Some(flags)) = (
        map_u32s(device, &dbg.gpu.tok_types),
        map_u32s(device, &dbg.gpu.flags_packed),
    ) {
        let n = min(types.len(), flags.len());
        let mut ok = true;
        for i in 0..n {
            let t = types[i];
            let lo = t & 0xFFFF;
            let hi = (t >> 16) & 0xFFFF;
            let f = flags[i];
            let keep_emit = (f & 4) != 0;
            let keep_eof = (f & 8) != 0;
            if !keep_emit && lo != 0xFFFF {
                println!(
                    "[dbg] ✗ tok_types[{}].emit != 0xFFFF when KEEP_EMIT=0 (got {:04x})",
                    i, lo
                );
                ok = false;
                break;
            }
            if !keep_eof && hi != 0xFFFF {
                println!(
                    "[dbg] ✗ tok_types[{}].eof  != 0xFFFF when KEEP_EOF=0 (got {:04x})",
                    i, hi
                );
                ok = false;
                break;
            }
        }
        if ok {
            println!(
                "[dbg] tok_types masking vs. KEEP_* flags ✓ OK ({} entries)",
                n
            );
        }
    } else {
        println!("[dbg] tok_types / flags_packed not available for mask check");
    }
}

// --------------------- public entrypoint ---------------------

/// Read back a suite of debug buffers and run expanded sanity checks.
/// Also keeps the original high-level comparisons for counts and monotonic ends.
pub(crate) fn run_debug_sanity_checks(
    device: &wgpu::Device,
    input: &str,
    dbg: &DebugOutput,
    n_input_bytes: u32,
) {
    // --- original top-level checks: counts vs finals ---
    let kept_count = map_first_u32(device, &dbg.gpu.token_count);
    let all_count = map_first_u32(device, &dbg.gpu.token_count_all);

    let s_keep = map_u32s(device, &dbg.gpu.s_keep_final);
    let s_all = map_u32s(device, &dbg.gpu.s_all_final);

    let s_keep_last = s_keep.as_ref().and_then(|v| v.last().copied());
    let s_all_last = s_all.as_ref().and_then(|v| v.last().copied());

    match (kept_count, s_keep_last) {
        (Some(kc), Some(last)) => {
            println!(
                "[dbg] kept_count={kc}  s_keep_final[last]={last}  {}",
                if kc == last { "✓ OK" } else { "✗ MISMATCH" }
            );
        }
        _ => println!("[dbg] kept_count / s_keep_final not available"),
    }
    match (all_count, s_all_last) {
        (Some(ac), Some(last)) => {
            println!(
                "[dbg] all_count={ac}  s_all_final[last]={last}  {}",
                if ac == last { "✓ OK" } else { "✗ MISMATCH" }
            );
        }
        _ => println!("[dbg] all_count / s_all_final not available"),
    }

    // --- original monotonicity on compacted ends ---
    let ends_kept = map_u32s(device, &dbg.gpu.end_positions);
    let ends_all = map_u32s(device, &dbg.gpu.end_positions_all);

    if let (Some(ek), Some(kc)) = (ends_kept, kept_count) {
        let upto = kc.min(ek.len() as u32) as usize;
        check_monotonic_increasing_within_bounds("end_positions[KEPT]", &ek[..upto], n_input_bytes);
    } else {
        println!("[dbg] end_positions[KEPT] not available");
    }

    if let (Some(ea), Some(ac)) = (ends_all, all_count) {
        let upto = ac.min(ea.len() as u32) as usize;
        check_monotonic_increasing_within_bounds(
            "end_positions_all[ALL]",
            &ea[..upto],
            n_input_bytes,
        );
    } else {
        println!("[dbg] end_positions_all[ALL] not available");
    }

    check_emit_and_state_against_cpu_input(input, device, dbg, n_input_bytes);
    check_prefixes_and_excl_against_cpu_input(input, device, dbg);

    // --- existing deeper checks (relations/invariants) ---
    check_flags_vs_prefix_and_excl(device, dbg, n_input_bytes);
    check_func_scan_rounds(device, dbg, n_input_bytes);
    check_pair_scan_rounds(device, dbg, n_input_bytes);
    check_compaction_and_tokens(device, dbg, n_input_bytes);
    check_simple_ranges(device, dbg);
    check_capacity_and_density(device, dbg, n_input_bytes);
}
