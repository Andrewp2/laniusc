// src/lexer/gpu/buffers.rs

use super::LexParams;
use crate::{
    gpu::buffers::{
        LaniusBuffer,
        storage_ro_from_bytes,
        storage_ro_from_u32s,
        storage_rw_for_array,
        storage_rw_uninit_bytes,
        uniform_from_val,
    },
    lexer::tables::dfa::N_STATES,
};

pub struct GpuBuffers {
    pub n: u32,
    pub nb_dfa: u32, // blocks for 128-wide DFA passes
    pub nb_sum: u32, // blocks for 256-wide sum passes

    /// Uniform params buffer (LexParams)
    pub params: LaniusBuffer<super::LexParams>,

    // inputs/tables
    pub in_bytes: LaniusBuffer<u8>,
    pub next_emit: LaniusBuffer<u32>, // 256 * N_STATES, low15=next, high1=emit
    pub token_map: LaniusBuffer<u32>, // N_STATES

    // function-id mapping + two-pass prefix for DFA states
    pub block_summaries: LaniusBuffer<u32>, // per-block function vector (N_STATES each)
    pub block_ping: LaniusBuffer<u32>,
    pub block_pong: LaniusBuffer<u32>,
    pub block_prefix: LaniusBuffer<u32>,
    pub f_final: LaniusBuffer<u32>,

    pub tok_types: LaniusBuffer<u32>, // type at boundary after i (packed)
    pub flags_packed: LaniusBuffer<u32>, // packed flags per i
    pub end_excl_by_i: LaniusBuffer<u32>, // exact exclusive end index per boundary i

    // seeds → hierarchical sum scratch/finals for BOTH streams
    pub block_totals_pair: LaniusBuffer<u32>,
    pub block_pair_ping: LaniusBuffer<u32>,
    pub block_pair_pong: LaniusBuffer<u32>,
    pub block_prefix_pair: LaniusBuffer<u32>,
    pub s_all_final: LaniusBuffer<u32>,
    pub s_keep_final: LaniusBuffer<u32>,

    // compaction outputs (ALL and KEPT)
    pub end_positions: LaniusBuffer<u32>,     // kept
    pub end_positions_all: LaniusBuffer<u32>, // all
    pub types_compact: LaniusBuffer<u32>,     // kept
    pub all_index_compact: LaniusBuffer<u32>, // kept
    pub token_count: LaniusBuffer<u32>,       // kept
    pub token_count_all: LaniusBuffer<u32>,   // all (debug/optional)

    // final tokens (kept)
    pub tokens_out: LaniusBuffer<super::GpuToken>,
}

impl GpuBuffers {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        device: &wgpu::Device,
        n: u32,
        start_state: u32,
        input_bytes: &[u8],
        next_emit_packed: &[u32],
        token_map: &[u32],
        skip_kinds: [u32; 4],
    ) -> Self {
        const BLOCK_WIDTH_DFA: u32 = 128;
        const BLOCK_WIDTH_SUM: u32 = 256;

        let nb_dfa = n.div_ceil(BLOCK_WIDTH_DFA);
        let nb_sum = n.div_ceil(BLOCK_WIDTH_SUM);

        // ---- inputs/tables
        let in_bytes: LaniusBuffer<u8> =
            storage_ro_from_bytes::<u8>(device, "in_bytes", input_bytes, n as usize);

        let token_map_buf: LaniusBuffer<u32> = storage_ro_from_u32s(device, "token_map", token_map);

        let next_emit_buf: LaniusBuffer<u32> =
            storage_ro_from_u32s(device, "next_emit", next_emit_packed);

        // per-block function vectors (N_STATES u32s per block)
        let per_block_count = N_STATES * (nb_dfa as usize);
        let block_summaries: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_summaries", per_block_count);
        let block_ping: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_ping", per_block_count);
        let block_pong: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_pong", per_block_count);
        let block_prefix: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_prefix", per_block_count);

        let f_final: LaniusBuffer<u32> = storage_rw_for_array::<u32>(device, "f_final", n as usize);

        let tok_types: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "tok_types", n as usize);

        let flags_packed: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "flags_packed", n as usize);

        let end_excl_by_i: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "end_excl_by_i", n as usize);

        // pair sums: 2*u32 per block (we store counts for ALL/KEPT)
        let pair_elems_per_block = 2usize;
        let pair_total = (nb_sum as usize) * pair_elems_per_block;
        let block_totals_pair: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_totals_pair", pair_total);
        let block_pair_ping: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_pair_ping", pair_total);
        let block_pair_pong: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_pair_pong", pair_total);
        let block_prefix_pair: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_prefix_pair", pair_total);

        // final sums (per boundary)
        let s_all_final: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "s_all_final", n as usize);
        let s_keep_final: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "s_keep_final", n as usize);

        // compaction + outputs (per boundary)
        let end_positions: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "end_positions", n as usize);
        let end_positions_all: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "end_positions_all", n as usize);
        let types_compact: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "types_compact", n as usize);
        let all_index_compact: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "all_index_compact", n as usize);

        // single u32 counters
        let token_count: LaniusBuffer<u32> = storage_rw_for_array::<u32>(device, "token_count", 1);
        let token_count_all: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "token_count_all", 1);

        // final tokens
        // NOTE: If `GpuToken` is a WGSL struct consumed by shaders, it should derive `ShaderType`.
        // If it doesn't yet, this uses Rust size; upgrade to `storage_rw_for_array::<GpuToken>`
        // after you add `#[derive(ShaderType, Default)]` on `GpuToken`.
        let tokens_out: LaniusBuffer<super::GpuToken> = storage_rw_uninit_bytes(
            device,
            "tokens_out",
            (n as usize) * std::mem::size_of::<super::GpuToken>(),
            n as usize,
        )
        .into();

        // Params (uniform)
        let params_val = LexParams {
            n,
            m: N_STATES as u32,
            start_state,
            skip0: skip_kinds[0],
            skip1: skip_kinds[1],
            skip2: skip_kinds[2],
            skip3: skip_kinds[3],
        };
        let params = uniform_from_val(device, "LexParams", &params_val);

        Self {
            n,
            nb_dfa,
            nb_sum,
            params,

            in_bytes,
            next_emit: next_emit_buf,
            token_map: token_map_buf,

            block_summaries,
            block_ping,
            block_pong,
            block_prefix,
            f_final,

            tok_types,
            flags_packed,
            end_excl_by_i,

            block_totals_pair,
            block_pair_ping,
            block_pair_pong,
            block_prefix_pair,

            s_all_final,
            s_keep_final,

            end_positions,
            end_positions_all,
            types_compact,
            all_index_compact,
            token_count,
            token_count_all,

            tokens_out,
        }
    }
}

// small From to help the `tokens_out` construction above
impl From<LaniusBuffer<u8>> for LaniusBuffer<super::GpuToken> {
    fn from(b: LaniusBuffer<u8>) -> Self {
        LaniusBuffer::new((b.buffer, b.byte_size as u64), b.count)
    }
}
