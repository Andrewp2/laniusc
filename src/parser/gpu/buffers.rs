use encase::ShaderType;

use crate::gpu::buffers::{
    LaniusBuffer,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType, Default)]
pub struct ActionHeader {
    pub push_len: u32,
    pub emit_len: u32,
    pub pop_tag: u32,
    pub pop_count: u32,
}

/// All GPU-side buffers for the parser pipeline (no readbacks/staging here).
pub struct ParserBuffers {
    // sizes
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub total_sc: u32,
    pub total_emit: u32,

    // pair→header
    pub params_llp: LaniusBuffer<super::passes::llp_pairs::LLPParams>,
    pub token_kinds: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>,
    pub out_headers: LaniusBuffer<ActionHeader>,

    // pack varlen (7-array layout packed into a single blob)
    pub params_pack: LaniusBuffer<super::passes::pack_varlen::PackParams>,
    pub sc_offsets: LaniusBuffer<u32>,
    pub emit_offsets: LaniusBuffer<u32>,
    pub tables_blob: LaniusBuffer<u32>,
    pub out_sc: LaniusBuffer<u32>,
    pub out_emit: LaniusBuffer<u32>,

    // bracket matching / validation
    pub params_brackets: LaniusBuffer<super::passes::brackets_match::BracketParams>,
    pub match_for_index: LaniusBuffer<u32>,
    pub depths_out: LaniusBuffer<i32>,
    pub valid_out: LaniusBuffer<u32>,
}

impl ParserBuffers {
    /// Create all GPU buffers for the parser pipeline in one place — like the lexer.
    ///
    /// - `token_kinds_u32`: token kinds including the sentinel; n_pairs = n_tokens - 1
    /// - `action_table_bytes`: (n_kinds * n_kinds) grid of `ActionHeader` bytes (row-major)
    /// - `tables`: precomputed “3 data structures / 7 arrays” table set used by the pack pass
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        let n_tokens = token_kinds_u32.len() as u32;
        let n_pairs = n_tokens.saturating_sub(1) as usize;

        // ---------- Pair→Header ----------
        let token_kinds = storage_ro_from_u32s(device, "parser.token_kinds", token_kinds_u32);

        let params_llp = uniform_from_val(
            device,
            "parser.params_llp",
            &super::passes::llp_pairs::LLPParams { n_tokens, n_kinds },
        );

        let action_table = if action_table_bytes.is_empty() {
            // keep shape-compat, but zero-sized table
            let one = vec![0u8; core::mem::size_of::<ActionHeader>()];
            storage_ro_from_bytes::<u8>(device, "parser.action_table", &one, one.len())
        } else {
            storage_ro_from_bytes::<u8>(
                device,
                "parser.action_table",
                action_table_bytes,
                action_table_bytes.len(),
            )
        };

        let out_headers: LaniusBuffer<ActionHeader> =
            storage_rw_for_array::<ActionHeader>(device, "parser.out_headers", n_pairs.max(1));

        // ---------- Pack varlen (compute pair-wise offsets here on CPU) ----------
        let mut sc_offsets_host = Vec::with_capacity(n_pairs);
        let mut emit_offsets_host = Vec::with_capacity(n_pairs);
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        for i in 0..n_pairs {
            let prev = token_kinds_u32[i];
            let thisk = token_kinds_u32[i + 1];
            let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
            sc_offsets_host.push(acc_sc);
            acc_sc += tables.sc_len[idx2d];
            emit_offsets_host.push(acc_emit);
            acc_emit += tables.pp_len[idx2d];
        }
        let total_sc = acc_sc;
        let total_emit = acc_emit;
        // --- Optional upper-bound allocation to avoid “measure-then-allocate” later.
        let max_sc_per_pair = *tables.sc_len.iter().max().unwrap_or(&0);
        let max_emit_per_pair = *tables.pp_len.iter().max().unwrap_or(&0);
        let n_pairs_u32 = n_pairs as u32;

        let ub_mode = std::env::var("LANIUS_PARSER_UPPER_BOUND_ALLOC")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false);

        let cap_sc = if ub_mode {
            max_sc_per_pair.saturating_mul(n_pairs_u32).max(total_sc)
        } else {
            total_sc
        };
        let cap_emit = if ub_mode {
            max_emit_per_pair
                .saturating_mul(n_pairs_u32)
                .max(total_emit)
        } else {
            total_emit
        };

        // Build the single packed blob: [sc_superseq | sc_off | sc_len | pp_superseq | pp_off | pp_len]
        let mut blob: Vec<u32> = Vec::with_capacity(
            tables.sc_superseq.len()
                + tables.sc_off.len()
                + tables.sc_len.len()
                + tables.pp_superseq.len()
                + tables.pp_off.len()
                + tables.pp_len.len(),
        );

        let sc_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_superseq);

        let sc_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_off);

        let sc_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_len);

        let pp_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_superseq);

        let pp_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_off);

        let pp_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_len);

        let params_pack = uniform_from_val(
            device,
            "pack.params",
            &super::passes::pack_varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );

        let sc_offsets = storage_ro_from_u32s(device, "pack.sc_offsets", &sc_offsets_host);
        let emit_offsets = storage_ro_from_u32s(device, "pack.emit_offsets", &emit_offsets_host);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let out_sc = storage_rw_for_array::<u32>(
            device,
            "pack.out_sc",
            cap_sc.max(1) as usize, // capacity, not exact length
        );
        let out_emit =
            storage_rw_for_array::<u32>(device, "pack.out_emit", cap_emit.max(1) as usize);

        // ---------- Brackets / validation ----------
        // We validate over the final stack-change stream (out_sc).
        // Match array needs length = total_sc; depths=[final,min], valid=[1].
        let params_brackets = uniform_from_val(
            device,
            "brackets.params",
            &super::passes::brackets_match::BracketParams {
                n_sc: total_sc,
                typed_check: 0, // driver can flip with queue.write_buffer if it wants typed checks
            },
        );

        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            total_sc.max(1) as usize,
        );
        let depths_out =
            storage_rw_for_array::<i32>(device, "brackets.depths_out", 2 /* [final, min] */);
        let valid_out = storage_rw_for_array::<u32>(device, "brackets.valid_out", 1);

        Self {
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,

            params_llp,
            token_kinds,
            action_table,
            out_headers,

            params_pack,
            sc_offsets,
            emit_offsets,
            tables_blob,
            out_sc,
            out_emit,

            params_brackets,
            match_for_index,
            depths_out,
            valid_out,
        }
    }
}
