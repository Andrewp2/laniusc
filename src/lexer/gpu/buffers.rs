use super::LexParams;
use crate::{
    gpu::buffers::{
        LaniusBuffer,
        storage_ro_from_u32s,
        storage_rw_for_array,
        storage_rw_uninit_bytes,
        uniform_from_val,
    },
    lexer::tables::dfa::N_STATES,
};

pub struct GpuBuffers {
    pub n: u32,
    pub nb_dfa: u32,
    pub nb_sum: u32,

    pub params: LaniusBuffer<super::LexParams>,

    pub in_bytes: LaniusBuffer<u8>,
    pub next_emit: LaniusBuffer<u32>,
    pub next_u8: LaniusBuffer<u32>,
    pub token_map: LaniusBuffer<u32>,

    pub dfa_02_ping: LaniusBuffer<u32>,
    pub dfa_02_pong: LaniusBuffer<u32>,
    pub tok_types: LaniusBuffer<u32>,
    pub flags_packed: LaniusBuffer<u32>,
    pub s_all_final: LaniusBuffer<u32>,
    pub s_keep_final: LaniusBuffer<u32>,

    pub end_positions: LaniusBuffer<u32>,
    pub types_compact: LaniusBuffer<u32>,
    pub all_index_compact: LaniusBuffer<u32>,
    pub token_count: LaniusBuffer<u32>,

    pub tokens_out: LaniusBuffer<super::GpuToken>,
}

impl GpuBuffers {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        device: &wgpu::Device,
        n: u32,
        start_state: u32,
        next_emit_packed: &[u32],
        next_u8_packed: &[u32],
        token_map: &[u32],
        skip_kinds: [u32; 4],
    ) -> Self {
        const BLOCK_WIDTH_DFA: u32 = 256;
        const BLOCK_WIDTH_SUM: u32 = 256;

        let nb_dfa = n.div_ceil(BLOCK_WIDTH_DFA);
        let nb_sum = n.div_ceil(BLOCK_WIDTH_SUM);
        debug_assert!(BLOCK_WIDTH_DFA > 0 && BLOCK_WIDTH_SUM > 0);
        let n_states = token_map.len();
        let expected_words = ((256 * n_states) + 1) / 2;
        debug_assert_eq!(
            next_emit_packed.len(),
            expected_words,
            "next_emit_packed size mismatch (got {}, expect {})",
            next_emit_packed.len(),
            expected_words
        );
        debug_assert!(!token_map.is_empty(), "token_map must not be empty");

        // Allocate input buffer with capacity n; contents are filled by driver via queue.write_buffer
        let in_bytes: LaniusBuffer<u8> =
            storage_rw_uninit_bytes(device, "in_bytes", n as usize, n as usize);

        let token_map: LaniusBuffer<u32> = storage_ro_from_u32s(device, "token_map", token_map);

        let next_emit: LaniusBuffer<u32> =
            storage_ro_from_u32s(device, "next_emit", next_emit_packed);

        let next_u8: LaniusBuffer<u32> = storage_ro_from_u32s(device, "next_u8", next_u8_packed);

        let per_block_count = N_STATES * (nb_dfa as usize);
        let dfa_02_ping: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_ping", per_block_count);
        let dfa_02_pong: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_pong", per_block_count);

        let tok_types: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "tok_types", n as usize);

        let flags_packed: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "flags_packed", n as usize);

        // end_excl_by_i eliminated (computed inline); pair scan reuses dfa_02 ping/pong

        let s_all_final: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "s_all_final", n as usize);
        let s_keep_final: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "s_keep_final", n as usize);

        let end_positions: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "end_positions", n as usize);
        let types_compact: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "types_compact", n as usize);
        let all_index_compact: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "all_index_compact", n as usize);

        let token_count: LaniusBuffer<u32> = storage_rw_for_array::<u32>(device, "token_count", 1);

        let tokens_out = storage_rw_for_array::<super::GpuToken>(device, "tokens_out", n as usize);

        let params_val = LexParams {
            n,
            m: n_states as u32,
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
            next_emit,
            next_u8,
            token_map,

            dfa_02_ping,
            dfa_02_pong,
            tok_types,
            flags_packed,

            s_all_final,
            s_keep_final,

            end_positions,
            types_compact,
            all_index_compact,
            token_count,

            tokens_out,
        }
    }
}

impl From<LaniusBuffer<u8>> for LaniusBuffer<super::GpuToken> {
    fn from(b: LaniusBuffer<u8>) -> Self {
        LaniusBuffer::new((b.buffer, b.byte_size as u64), b.count)
    }
}
