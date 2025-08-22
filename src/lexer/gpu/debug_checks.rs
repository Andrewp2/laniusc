// TODO: This entire file needs to be rewritten to match the new shaders/buffers/everything.
#![cfg(feature = "gpu-debug")]

use std::cmp::min;

use wgpu::MapMode;

use crate::{
    gpu::debug::DebugBuffer,
    lexer::{
        gpu::debug::DebugOutput,
        tables::{compact::load_compact_tables_from_bytes, dfa::N_STATES, tokens::TokenKind},
    },
};

// ==== constants matching shader block widths ====
const FUNC_BLOCK_WIDTH: u32 = 128; // dfa_01 / dfa_02 family
const PAIR_BLOCK_WIDTH: u32 = 256; // pair_01 / pair_02 / pair_03

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

// ---------- load compact tables once ----------
struct CompactTables {
    next_emit_words: Vec<u32>, // packed u16 lanes: low15 = next, high1 = emit
    token_map: Vec<u32>,       // per-state token kind or u32::MAX
}
fn load_tables_or_none() -> Option<CompactTables> {
    const COMPACT_BIN: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tables/lexer_tables.bin"
    ));
    let (n_states_from_file, next_emit_words, token_map) =
        load_compact_tables_from_bytes(COMPACT_BIN).ok()?;
    if n_states_from_file != N_STATES {
        return None;
    }
    Some(CompactTables {
        next_emit_words,
        token_map,
    })
}

// ---------- CPU oracles used by the per-shader checks ----------

/// Per-byte DFA walk yielding arrays needed by multiple checks.
/// Returns:
/// - f_final[i]  : next-state after processing byte i
/// - flags[i]    : packed bits { EMIT=1<<0, EOF=1<<1, KEEP_EMIT=1<<2, KEEP_EOF=1<<3 }
/// - s_all[i]    : inclusive ALL count
/// - s_keep[i]   : inclusive KEPT count
/// - end_excl_by_i[i] : per-i exclusive end for single-kept boundary
/// - tok_types[i]: (eof_kind16<<16)|emit_kind16 where non-kept lanes are 0xFFFF
struct CpuWalk {
    f_final: Vec<u32>,
    flags: Vec<u32>,
    s_all: Vec<u32>,
    s_keep: Vec<u32>,
    end_excl_by_i: Vec<u32>,
    tok_types_packed: Vec<u32>,
}
fn cpu_tables_walk(input_bytes: &[u8], tbl: &CompactTables) -> CpuWalk {
    // skip set matches shaders + driver
    let skip_kinds = [
        TokenKind::White as u32,
        TokenKind::LineComment as u32,
        TokenKind::BlockComment as u32,
        u32::MAX,
    ];
    let is_skip = |tk: u32| {
        tk == skip_kinds[0] || tk == skip_kinds[1] || tk == skip_kinds[2] || tk == skip_kinds[3]
    };

    let n = input_bytes.len();
    let mut f_final = vec![0u32; n];
    let mut flags = vec![0u32; n];
    let mut s_all = vec![0u32; n];
    let mut s_keep = vec![0u32; n];
    let mut end_excl_by_i = vec![0u32; n];
    let mut tok_types = vec![0u32; n];

    let mut prev_state: u32 = 0;
    let mut acc_all: u32 = 0;
    let mut acc_keep: u32 = 0;

    for i in 0..n {
        let b = input_bytes[i] as usize;
        let idx = b * (N_STATES as usize) + (prev_state as usize);
        let word = tbl.next_emit_words[idx >> 1];
        let lane16 = if (idx & 1) == 0 {
            word & 0xFFFF
        } else {
            (word >> 16) & 0xFFFF
        };
        let emit_here = (lane16 & 0x8000) != 0;
        let next_state = (lane16 & 0x7FFF) as u32;

        let at_eof = i + 1 == n;
        let tk_emit = tbl.token_map[prev_state as usize];
        let tk_eof = tbl.token_map[next_state as usize];

        let valid_emit = tk_emit != u32::MAX;
        let valid_eof = tk_eof != u32::MAX;

        let keep_emit = valid_emit && !is_skip(tk_emit);
        let keep_eof = valid_eof && !is_skip(tk_eof);

        let eof_here = at_eof && valid_eof;

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

        // tok_types (masked kinds for kept)
        let emit16 = if keep_emit && valid_emit {
            (tk_emit & 0xFFFF) as u32
        } else {
            0xFFFF
        };
        let eof16 = if keep_eof && valid_eof {
            (tk_eof & 0xFFFF) as u32
        } else {
            0xFFFF
        };
        tok_types[i] = (eof16 << 16) | emit16;

        // single-kept end exclusive rule (mirrors shader)
        end_excl_by_i[i] = if at_eof && keep_eof && !(keep_emit && emit_here) {
            n as u32
        } else {
            // EMIT boundary closes at i+1 (exclusive)
            (i as u32) + 1
        };

        f_final[i] = next_state;
        prev_state = next_state;
    }

    CpuWalk {
        f_final,
        flags,
        s_all,
        s_keep,
        end_excl_by_i,
        tok_types_packed: tok_types,
    }
}

/// Build per-block function summaries (δ for the block), length = nb * N_STATES.
/// Composition order matches the shaders (apply earlier byte first, later byte last).
fn cpu_block_summaries(input_bytes: &[u8], tbl: &CompactTables) -> Vec<u32> {
    let nb = ceil_div_u32(input_bytes.len() as u32, FUNC_BLOCK_WIDTH);
    let mut out = vec![0u32; (nb as usize) * (N_STATES as usize)];

    // Helper: for a byte b, δ_b[s] = next state (ignore emit bit).
    let mut delta_row = vec![0u32; N_STATES as usize];

    for block in 0..nb {
        let base = (block * FUNC_BLOCK_WIDTH) as usize;
        let count = min(
            FUNC_BLOCK_WIDTH as usize,
            input_bytes.len().saturating_sub(base),
        );

        // Start with identity f(s)=s
        let mut f: Vec<u32> = (0..N_STATES as u32).collect();

        for off in 0..count {
            let b = input_bytes[base + off] as usize;
            // fill δ_b into delta_row
            for s in 0..(N_STATES as usize) {
                let idx = b * (N_STATES as usize) + s;
                let word = tbl.next_emit_words[idx >> 1];
                let lane16 = if (idx & 1) == 0 {
                    word & 0x7FFF
                } else {
                    (word >> 16) & 0x7FFF
                };
                delta_row[s] = lane16 as u32;
            }
            // compose: f' = δ_b ∘ f
            for s in 0..(N_STATES as usize) {
                let a = f[s] as usize;
                f[s] = delta_row[a];
            }
        }

        // write the row for this block
        let dst = &mut out
            [(block as usize) * (N_STATES as usize)..(block as usize + 1) * (N_STATES as usize)];
        dst.copy_from_slice(&f[..]);
    }
    out
}

/// Compose two function vectors h = b ∘ a  (all arrays are N_STATES long).
fn compose_funcs(a: &[u32], b: &[u32]) -> Vec<u32> {
    debug_assert_eq!(a.len(), b.len());
    let mut h = vec![0u32; a.len()];
    for s in 0..a.len() {
        h[s] = b[a[s] as usize];
    }
    h
}

/// Expected ALL compaction (positions only), in order.
/// Two entries (i, n) are emitted if both EMIT and EOF are counted at the same i.
fn expected_all_compaction(flags: &[u32], s_all: &[u32], n: u32) -> Vec<u32> {
    let mut out = Vec::new();
    let mut prev = 0u32;
    for i in 0..s_all.len() {
        let curr = s_all[i];
        let delta = curr.saturating_sub(prev);
        let f = flags[i];
        if delta == 0 {
            // nothing
        } else if delta == 1 {
            // decide which one it was
            if (f & 1) != 0 {
                out.push(i as u32);
            } else {
                out.push(n);
            }
        } else {
            // both: EMIT then EOF
            out.push(i as u32);
            out.push(n);
        }
        prev = curr;
    }
    out
}

/// Expected KEPT compaction (end_positions, all_index_compact, kinds PRE-RETAG).
/// We also need end_excl_by_i and tok_types packed (for picking kind).
struct KeptCompactionExpect {
    end_positions: Vec<u32>,
    all_index_1based: Vec<u32>,
    kinds_pre_retag: Vec<u32>,
}
fn expected_kept_compaction(
    flags: &[u32],
    s_all: &[u32],
    s_keep: &[u32],
    end_excl_by_i: &[u32],
    tok_types_packed: &[u32],
    n: u32,
) -> KeptCompactionExpect {
    let mut ends = Vec::new();
    let mut all_idx = Vec::new();
    let mut kinds = Vec::new();

    let mut prev_keep = 0u32;
    for i in 0..s_keep.len() {
        let curr_keep = s_keep[i];
        let delta_keep = curr_keep.saturating_sub(prev_keep);
        if delta_keep == 0 {
            prev_keep = curr_keep;
            continue;
        }

        let f = flags[i];
        let all_curr = s_all[i];
        let prev_all = if i == 0 { 0 } else { s_all[i - 1] };
        let delta_all = all_curr.saturating_sub(prev_all);

        let emit16 = tok_types_packed[i] & 0xFFFF;
        let eof16 = (tok_types_packed[i] >> 16) & 0xFFFF;
        let is_last = ((i as u32) + 1) == n;

        if delta_keep == 2 {
            // two kept boundaries at this i: EMIT then EOF
            ends.push(i as u32); // EMIT closes to i
            ends.push(n); // EOF closes to n

            let kind0 = if emit16 != 0xFFFF { emit16 } else { eof16 };
            let kind1 = if eof16 != 0xFFFF { eof16 } else { emit16 };
            kinds.push(kind0);
            kinds.push(kind1);

            all_idx.push(all_curr - 1); // j-1
            all_idx.push(all_curr); // j
        } else {
            // single kept boundary: derive end_excl and kind selection
            let end_excl = end_excl_by_i[i];
            ends.push(end_excl);

            let kind = if is_last {
                if eof16 != 0xFFFF { eof16 } else { emit16 }
            } else {
                if emit16 != 0xFFFF { emit16 } else { eof16 }
            };
            kinds.push(kind);

            // which ALL boundary did we keep?
            let mut all_for_kept = all_curr;
            if is_last && delta_all == 2 {
                // decide j-1 vs j based on which kept
                let kept_emit = (f & 1) != 0 && (f & 4) != 0;
                if kept_emit {
                    all_for_kept = all_curr - 1;
                }
            }
            all_idx.push(all_for_kept);
        }

        prev_keep = curr_keep;
    }

    KeptCompactionExpect {
        end_positions: ends,
        all_index_1based: all_idx,
        kinds_pre_retag: kinds,
    }
}

fn retag_on_cpu(kinds_pre: &[TokenKind]) -> Vec<TokenKind> {
    use TokenKind::*;
    let mut out = kinds_pre.to_vec();
    for i in 0..out.len() {
        match out[i] {
            LParen => {
                let prev = if i == 0 { None } else { Some(out[i - 1]) };
                out[i] = if prev.map(is_primary_end).unwrap_or(false) {
                    CallLParen
                } else {
                    GroupLParen
                };
            }
            LBracket => {
                let prev = if i == 0 { None } else { Some(out[i - 1]) };
                out[i] = if prev.map(is_primary_end).unwrap_or(false) {
                    IndexLBracket
                } else {
                    ArrayLBracket
                };
            }
            _ => {}
        }
    }
    out
}

// ---------- conversions ----------
fn kind16_to_enum(x: u32) -> Option<TokenKind> {
    if x == 0xFFFF {
        None
    } else {
        Some(unsafe { std::mem::transmute::<u32, TokenKind>(x) })
    }
}

// --------------------- per-shader checks ---------------------

fn check_01_dfa_01_scan_inblock(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(gpu_bs) = map_u32s(device, &dbg.gpu.block_summaries) else {
        println!("[dbg][1/11] dfa_01_scan_inblock: (no readback) — skipped");
        return;
    };
    let cpu_bs = cpu_block_summaries(input.as_bytes(), tbl);
    if gpu_bs == cpu_bs {
        println!("[dbg][1/11] dfa_01_scan_inblock: per-block function summaries ✓");
    } else {
        println!(
            "[dbg][1/11] dfa_01_scan_inblock: ✗ summaries mismatch (sizes: gpu={} cpu={})",
            gpu_bs.len(),
            cpu_bs.len()
        );
    }
}

fn check_02_dfa_02_scan_block_summaries(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(bp_gpu) = map_u32s(device, &dbg.gpu.block_prefix) else {
        println!("[dbg][2/11] dfa_02_scan_block_summaries: (no block_prefix) — skipped");
        return;
    };
    let bs = cpu_block_summaries(input.as_bytes(), tbl);
    let nb = ceil_div_u32(input.len() as u32, FUNC_BLOCK_WIDTH) as usize;
    let mut acc: Vec<u32> = (0..N_STATES as u32).collect();
    let mut ok = true;

    for i in 0..nb {
        let row = &bs[i * (N_STATES as usize)..(i + 1) * (N_STATES as usize)];
        acc = compose_funcs(&acc, row);
        let bp_row = &bp_gpu[i * (N_STATES as usize)..(i + 1) * (N_STATES as usize)];
        if acc != bp_row {
            println!(
                "[dbg][2/11] dfa_02_scan_block_summaries: ✗ mismatch at block {} (first few gpu={:?} cpu={:?})",
                i,
                &bp_row[..min(8, bp_row.len())],
                &acc[..min(8, acc.len())]
            );
            ok = false;
            break;
        }
    }
    if ok {
        println!("[dbg][2/11] dfa_02_scan_block_summaries: block_prefix (inclusive scan) ✓");
    }
}

fn check_03_dfa_03_apply_block_prefix(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(f_final_gpu) = map_u32s(device, &dbg.gpu.f_final) else {
        println!("[dbg][3/11] dfa_03_apply_block_prefix: (no f_final) — skipped");
        return;
    };
    let walk = cpu_tables_walk(input.as_bytes(), tbl);
    let upto = min(walk.f_final.len(), f_final_gpu.len());
    if walk.f_final[..upto] == f_final_gpu[..upto] {
        println!("[dbg][3/11] dfa_03_apply_block_prefix: f_final equals CPU DFA walk ✓");
    } else {
        if let Some(i) = (0..upto).find(|&i| walk.f_final[i] != f_final_gpu[i]) {
            println!(
                "[dbg][3/11] dfa_03_apply_block_prefix: ✗ first mismatch at i={} (gpu={} cpu={})",
                i, f_final_gpu[i], walk.f_final[i]
            );
        } else {
            println!(
                "[dbg][3/11] dfa_03_apply_block_prefix: ✗ size mismatch gpu={} cpu={}",
                f_final_gpu.len(),
                walk.f_final.len()
            );
        }
    }
}

fn check_04_boundary_finalize_and_seed(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(flags_gpu) = map_u32s(device, &dbg.gpu.flags_packed) else {
        println!("[dbg][4/11] boundary_finalize_and_seed: (no flags_packed) — skipped");
        return;
    };
    let Some(tok_types_gpu) = map_u32s(device, &dbg.gpu.tok_types) else {
        println!("[dbg][4/11] boundary_finalize_and_seed: (no tok_types) — skipped");
        return;
    };
    let Some(excl_gpu) = map_u32s(device, &dbg.gpu.end_excl_by_i) else {
        println!("[dbg][4/11] boundary_finalize_and_seed: (no end_excl_by_i) — skipped");
        return;
    };
    let walk = cpu_tables_walk(input.as_bytes(), tbl);
    let n = min(flags_gpu.len(), walk.flags.len());

    // flags exact
    if flags_gpu[..n] != walk.flags[..n] {
        if let Some(i) = (0..n).find(|&i| flags_gpu[i] != walk.flags[i]) {
            println!(
                "[dbg][4/11] boundary_finalize_and_seed: ✗ flags mismatch at i={} (gpu={:b} cpu={:b})",
                i, flags_gpu[i], walk.flags[i]
            );
        } else {
            println!("[dbg][4/11] boundary_finalize_and_seed: ✗ flags size mismatch");
        }
        return;
    }

    // tok_types (masked kinds)
    let m = min(tok_types_gpu.len(), walk.tok_types_packed.len());
    if tok_types_gpu[..m] != walk.tok_types_packed[..m] {
        if let Some(i) = (0..m).find(|&i| tok_types_gpu[i] != walk.tok_types_packed[i]) {
            let g_lo = tok_types_gpu[i] & 0xFFFF;
            let g_hi = (tok_types_gpu[i] >> 16) & 0xFFFF;
            let c_lo = walk.tok_types_packed[i] & 0xFFFF;
            let c_hi = (walk.tok_types_packed[i] >> 16) & 0xFFFF;
            println!(
                "[dbg][4/11] boundary_finalize_and_seed: ✗ tok_types mismatch at i={} (gpu:emit={:#06x} eof={:#06x}, cpu:emit={:#06x} eof={:#06x})",
                i, g_lo, g_hi, c_lo, c_hi
            );
        } else {
            println!("[dbg][4/11] boundary_finalize_and_seed: ✗ tok_types size mismatch");
        }
        return;
    }

    // end_excl_by_i
    let k = min(excl_gpu.len(), walk.end_excl_by_i.len());
    if excl_gpu[..k] != walk.end_excl_by_i[..k] {
        if let Some(i) = (0..k).find(|&i| excl_gpu[i] != walk.end_excl_by_i[i]) {
            println!(
                "[dbg][4/11] boundary_finalize_and_seed: ✗ end_excl_by_i mismatch at i={} (gpu={} cpu={})",
                i, excl_gpu[i], walk.end_excl_by_i[i]
            );
        } else {
            println!("[dbg][4/11] boundary_finalize_and_seed: ✗ end_excl_by_i size mismatch");
        }
        return;
    }

    println!("[dbg][4/11] boundary_finalize_and_seed: flags, tok_types, end_excl_by_i ✓");
}

fn check_05_pair_01_sum_inblock(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(block_pair_gpu) = map_u32s(device, &dbg.gpu.block_totals_pair) else {
        println!("[dbg][5/11] pair_01_sum_inblock: (no block_totals_pair) — skipped");
        return;
    };
    let walk = cpu_tables_walk(input.as_bytes(), tbl);
    let nb = ceil_div_u32(input.len() as u32, PAIR_BLOCK_WIDTH) as usize;

    let mut expect = Vec::<u32>::with_capacity(nb * 2);
    for b in 0..nb {
        let base = b * (PAIR_BLOCK_WIDTH as usize);
        let count = std::cmp::min(
            PAIR_BLOCK_WIDTH as usize,
            walk.flags.len().saturating_sub(base),
        );
        let mut blk_all = 0u32;
        let mut blk_keep = 0u32;
        for i in 0..count {
            let f = walk.flags[base + i];
            let emit = (f & 1) != 0;
            let eof = (f & 2) != 0;
            let kemit = (f & 4) != 0;
            let keof = (f & 8) != 0;
            blk_all += (emit as u32) + (eof as u32);
            blk_keep += ((emit && kemit) as u32) + ((eof && keof) as u32);
        }
        // Compare raw per-block totals, not cumulative
        expect.push(blk_all);
        expect.push(blk_keep);
    }

    if block_pair_gpu[..expect.len()] == expect[..] {
        println!("[dbg][5/11] pair_01_sum_inblock: per-block (ALL,KEPT) totals ✓");
    } else {
        println!(
            "[dbg][5/11] pair_01_sum_inblock: ✗ mismatch (gpu len={} cpu len={})",
            block_pair_gpu.len(),
            expect.len()
        );
    }
}

fn check_06_pair_02_scan_block_totals(device: &wgpu::Device, dbg: &DebugOutput, input: &str) {
    let Some(bp_pair_gpu) = map_u32s(device, &dbg.gpu.block_prefix_pair) else {
        println!("[dbg][6/11] pair_02_scan_block_totals: (no block_prefix_pair) — skipped");
        return;
    };
    let Some(bt_pair_gpu) = map_u32s(device, &dbg.gpu.block_totals_pair) else {
        println!("[dbg][6/11] pair_02_scan_block_totals: (no block_totals_pair) — skipped");
        return;
    };
    let nb = ceil_div_u32(input.len() as u32, PAIR_BLOCK_WIDTH) as usize;

    let mut expect = Vec::<u32>::with_capacity(nb * 2);
    let mut acc_x = 0u32;
    let mut acc_y = 0u32;
    for i in 0..nb {
        let ix = 2 * i;
        acc_x = acc_x.saturating_add(bt_pair_gpu[ix]);
        acc_y = acc_y.saturating_add(bt_pair_gpu[ix + 1]);
        expect.push(acc_x);
        expect.push(acc_y);
    }

    if bp_pair_gpu[..expect.len()] == expect[..] {
        println!("[dbg][6/11] pair_02_scan_block_totals: block_prefix_pair (inclusive add) ✓");
    } else {
        println!("[dbg][6/11] pair_02_scan_block_totals: ✗ mismatch");
    }
}

fn check_07_pair_03_apply_block_prefix(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(s_all_gpu) = map_u32s(device, &dbg.gpu.s_all_final) else {
        println!("[dbg][7/11] pair_03_apply_block_prefix: (no s_all_final) — skipped");
        return;
    };
    let Some(s_keep_gpu) = map_u32s(device, &dbg.gpu.s_keep_final) else {
        println!("[dbg][7/11] pair_03_apply_block_prefix: (no s_keep_final) — skipped");
        return;
    };
    let walk = cpu_tables_walk(input.as_bytes(), tbl);

    let n = min(s_all_gpu.len(), walk.s_all.len());
    let m = min(s_keep_gpu.len(), walk.s_keep.len());

    let ok_all = s_all_gpu[..n] == walk.s_all[..n];
    let ok_keep = s_keep_gpu[..m] == walk.s_keep[..m];

    if ok_all && ok_keep {
        println!("[dbg][7/11] pair_03_apply_block_prefix: s_all_final & s_keep_final ✓");
    } else {
        if !ok_all {
            if let Some(i) = (0..n).find(|&i| s_all_gpu[i] != walk.s_all[i]) {
                println!(
                    "[dbg][7/11] pair_03_apply_block_prefix: ✗ s_all mismatch at i={} (gpu={} cpu={})",
                    i, s_all_gpu[i], walk.s_all[i]
                );
            }
        }
        if !ok_keep {
            if let Some(i) = (0..m).find(|&i| s_keep_gpu[i] != walk.s_keep[i]) {
                println!(
                    "[dbg][7/11] pair_03_apply_block_prefix: ✗ s_keep mismatch at i={} (gpu={} cpu={})",
                    i, s_keep_gpu[i], walk.s_keep[i]
                );
            }
        }
    }
}
// --------------------- per-shader checks ---------------------

fn check_08_compact_boundaries_all(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) {
    let Some(ends_all_gpu) = map_u32s(device, &dbg.gpu.end_positions_all) else {
        println!("[dbg][8/11] compact_boundaries_all: (no end_positions_all) — skipped");
        return;
    };
    let Some(all_count_gpu) = map_first_u32(device, &dbg.gpu.token_count_all) else {
        println!("[dbg][8/11] compact_boundaries_all: (no token_count_all) — skipped");
        return;
    };

    let walk = cpu_tables_walk(input.as_bytes(), tbl);
    let expect = expected_all_compaction(&walk.flags, &walk.s_all, input.len() as u32);

    let upto = ends_all_gpu
        .len()
        .min(expect.len())
        .min(all_count_gpu as usize);

    let ok_prefix = expect[..upto] == ends_all_gpu[..upto];
    let cpu_count = walk.s_all.last().copied().unwrap_or(0);
    let counts_match = cpu_count == all_count_gpu;
    let lens_match = upto == ends_all_gpu.len() && upto == (all_count_gpu as usize);

    if ok_prefix && counts_match {
        if !lens_match {
            println!(
                "[dbg][8/11] compact_boundaries_all: ✓ (prefix & count match; buffer has extra capacity) gpu_ends={} gpu_count={}",
                ends_all_gpu.len(),
                all_count_gpu
            );
        } else {
            println!("[dbg][8/11] compact_boundaries_all: token_count_all & end_positions_all ✓");
        }
    } else {
        if !ok_prefix {
            println!(
                "[dbg][8/11] compact_boundaries_all: ✗ prefix mismatch within {} entries",
                upto
            );
        }
        if !counts_match {
            println!(
                "[dbg][8/11] compact_boundaries_all: ✗ count_all gpu={} cpu_last={}",
                all_count_gpu, cpu_count
            );
        }
        if upto < ends_all_gpu.len()
            || upto < all_count_gpu as usize
            || expect.len() != all_count_gpu as usize
        {
            println!(
                "[dbg][8/11] compact_boundaries_all: lengths: gpu_ends={} cpu_expect={} gpu_count={}",
                ends_all_gpu.len(),
                expect.len(),
                all_count_gpu
            );
        }
    }
}

fn check_09_compact_boundaries_kept(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    input: &str,
    tbl: &CompactTables,
) -> Option<KeptCompactionExpect> {
    let Some(ends_kept_gpu) = map_u32s(device, &dbg.gpu.end_positions) else {
        println!("[dbg][9/11] compact_boundaries_kept: (no end_positions) — skipped");
        return None;
    };
    let Some(all_idx_gpu) = map_u32s(device, &dbg.gpu.all_index_compact) else {
        println!("[dbg][9/11] compact_boundaries_kept: (no all_index_compact) — skipped");
        return None;
    };
    let Some(kept_count_gpu) = map_first_u32(device, &dbg.gpu.token_count) else {
        println!("[dbg][9/11] compact_boundaries_kept: (no token_count) — skipped");
        return None;
    };

    let walk = cpu_tables_walk(input.as_bytes(), tbl);
    let expect = expected_kept_compaction(
        &walk.flags,
        &walk.s_all,
        &walk.s_keep,
        &walk.end_excl_by_i,
        &walk.tok_types_packed,
        input.len() as u32,
    );

    // Clamp to the shortest among all sources; never slice using the raw GPU count.
    let kc_gpu = kept_count_gpu as usize;
    let upto = kc_gpu
        .min(ends_kept_gpu.len())
        .min(all_idx_gpu.len())
        .min(expect.end_positions.len())
        .min(expect.all_index_1based.len());

    let ok_ends_prefix = expect.end_positions[..upto] == ends_kept_gpu[..upto];
    let ok_idx_prefix = expect.all_index_1based[..upto] == all_idx_gpu[..upto];
    let cpu_kc = walk.s_keep.last().copied().unwrap_or(0);

    let counts_match = cpu_kc == kept_count_gpu;
    let lengths_sufficient = kc_gpu <= ends_kept_gpu.len() && kc_gpu <= all_idx_gpu.len();

    if ok_ends_prefix && ok_idx_prefix && counts_match && lengths_sufficient && upto == kc_gpu {
        println!(
            "[dbg][9/11] compact_boundaries_kept: token_count, end_positions, all_index_compact ✓"
        );
    } else {
        if !ok_ends_prefix {
            println!(
                "[dbg][9/11] compact_boundaries_kept: ✗ end_positions prefix mismatch within {} entries",
                upto
            );
        }
        if !ok_idx_prefix {
            println!(
                "[dbg][9/11] compact_boundaries_kept: ✗ all_index_compact prefix mismatch within {} entries",
                upto
            );
        }
        if kc_gpu > ends_kept_gpu.len() {
            println!(
                "[dbg][9/11] compact_boundaries_kept: ✗ GPU end_positions shorter than token_count ({} < {})",
                ends_kept_gpu.len(),
                kc_gpu
            );
        }
        if kc_gpu > all_idx_gpu.len() {
            println!(
                "[dbg][9/11] compact_boundaries_kept: ✗ GPU all_index_compact shorter than token_count ({} < {})",
                all_idx_gpu.len(),
                kc_gpu
            );
        }
        if !counts_match {
            println!(
                "[dbg][9/11] compact_boundaries_kept: ✗ token_count gpu={} != s_keep_last cpu={}",
                kept_count_gpu, cpu_kc
            );
        }
    }

    Some(expect)
}

// ---------- a tiny retagger mirroring shaders/lexer/retag_calls_and_arrays.slang ----------
fn is_primary_end(kind: TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Ident
            | TokenKind::Int
            | TokenKind::RParen
            | TokenKind::RBracket
            | TokenKind::RBrace
    )
}

fn check_10_retag_calls_and_arrays(
    device: &wgpu::Device,
    dbg: &DebugOutput,
    expect_kept: &KeptCompactionExpect,
) {
    let Some(types_compact_gpu) = map_u32s(device, &dbg.gpu.types_compact) else {
        println!("[dbg][10/11] retag_calls_and_arrays: (no types_compact) — skipped");
        return;
    };
    let kc = min(expect_kept.kinds_pre_retag.len(), types_compact_gpu.len());
    // Convert pre kinds (u16 ids) -> enum, retag on CPU, compare to gpu final kinds (u32 ids).
    let mut kinds_pre_enum = Vec::<TokenKind>::with_capacity(kc);
    for i in 0..kc {
        let k16 = expect_kept.kinds_pre_retag[i] & 0xFFFF;
        let Some(kind) = kind16_to_enum(k16) else {
            // Should not happen: kept stream must have valid kind.
            println!(
                "[dbg][10/11] retag_calls_and_arrays: ✗ pre kind 0xFFFF at k={}",
                i
            );
            return;
        };
        kinds_pre_enum.push(kind);
    }
    let kinds_post = retag_on_cpu(&kinds_pre_enum);
    let mut ok = true;
    for i in 0..kc {
        let want_u32 = kinds_post[i] as u32;
        if types_compact_gpu[i] != want_u32 {
            println!(
                "[dbg][10/11] retag_calls_and_arrays: ✗ mismatch at k={} (gpu={} cpu={})",
                i, types_compact_gpu[i], want_u32
            );
            ok = false;
            break;
        }
    }
    if ok {
        println!("[dbg][10/11] retag_calls_and_arrays: types_compact (post-retag) ✓");
    }
}

fn check_11_tokens_build(device: &wgpu::Device, dbg: &DebugOutput, input_len: u32) {
    let Some(kc_gpu) = map_first_u32(device, &dbg.gpu.token_count) else {
        println!("[dbg][11/11] tokens_build: (no token_count) — skipped");
        return;
    };
    let Some(ends_k) = map_u32s(device, &dbg.gpu.end_positions) else {
        println!("[dbg][11/11] tokens_build: (no end_positions) — skipped");
        return;
    };
    let Some(types_k) = map_u32s(device, &dbg.gpu.types_compact) else {
        println!("[dbg][11/11] tokens_build: (no types_compact) — skipped");
        return;
    };
    let Some(aic) = map_u32s(device, &dbg.gpu.all_index_compact) else {
        println!("[dbg][11/11] tokens_build: (no all_index_compact) — skipped");
        return;
    };
    let Some(ends_all) = map_u32s(device, &dbg.gpu.end_positions_all) else {
        println!("[dbg][11/11] tokens_build: (no end_positions_all) — skipped");
        return;
    };
    let Some(tokens) = map_u32s(device, &dbg.gpu.tokens_out) else {
        println!("[dbg][11/11] tokens_build: (no tokens_out) — skipped");
        return;
    };

    let kc = kc_gpu as usize;
    let upto = min(
        kc,
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
            ends_all[(all_zero - 1) as usize]
        };

        let rec_kind = tokens[3 * k + 0];
        let rec_start = tokens[3 * k + 1];
        let rec_len = tokens[3 * k + 2];

        let expect_len = end_excl.saturating_sub(start);
        if rec_kind != types_k[k] || rec_start != start || rec_len != expect_len {
            println!(
                "[dbg][11/11] tokens_build: ✗ token {} mismatch (gpu kind={},start={},len={} ; expect kind={},start={},len={})",
                k, rec_kind, rec_start, rec_len, types_k[k], start, expect_len
            );
            ok = false;
            break;
        }
        if end_excl > input_len {
            println!(
                "[dbg][11/11] tokens_build: ✗ token {} end_excl {} > n={}",
                k, end_excl, input_len
            );
            ok = false;
            break;
        }
        if rec_len == 0 {
            println!("[dbg][11/11] tokens_build: ✗ zero-length token at {}", k);
            ok = false;
            break;
        }
    }
    if ok {
        println!("[dbg][11/11] tokens_build: tokens_out fields ✓");
    }
}

// --------------------- public entrypoint ---------------------

/// One debug check for each shader, in order, against CPU oracles built from the
/// same compact tables the GPU uses. This function prints exactly 11 lines on
/// success (one per shader).
pub(crate) fn run_debug_sanity_checks(
    device: &wgpu::Device,
    input: &str,
    dbg: &DebugOutput,
    n_input_bytes: u32,
) {
    // Ensure we can read the original bytes (nice for extra guards; optional).
    let _ = map_u8s(device, &dbg.gpu.in_bytes);

    let Some(tbl) = load_tables_or_none() else {
        println!("[dbg] compact tables unavailable (n_states mismatch?) — all checks skipped");
        return;
    };

    check_01_dfa_01_scan_inblock(device, dbg, input, &tbl);
    check_02_dfa_02_scan_block_summaries(device, dbg, input, &tbl);
    check_03_dfa_03_apply_block_prefix(device, dbg, input, &tbl);
    check_04_boundary_finalize_and_seed(device, dbg, input, &tbl);
    check_05_pair_01_sum_inblock(device, dbg, input, &tbl);
    check_06_pair_02_scan_block_totals(device, dbg, input);
    check_07_pair_03_apply_block_prefix(device, dbg, input, &tbl);
    check_08_compact_boundaries_all(device, dbg, input, &tbl);

    // compact_kept returns expectations we re-use for the retag check
    if let Some(expect_kept) = check_09_compact_boundaries_kept(device, dbg, input, &tbl) {
        check_10_retag_calls_and_arrays(device, dbg, &expect_kept);
    } else {
        println!("[dbg][10/11] retag_calls_and_arrays: (previous step missing) — skipped");
    }

    check_11_tokens_build(device, dbg, n_input_bytes);
}
