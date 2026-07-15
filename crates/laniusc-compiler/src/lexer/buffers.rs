use super::LexParams;
use crate::{
    gpu::buffers::{
        LaniusBuffer,
        storage_ro_from_u32s_with_queue,
        storage_rw_for_array,
        storage_rw_uninit_bytes,
        uniform_from_val_with_queue,
    },
    lexer::tables::dfa::N_STATES,
};

/// Resident GPU buffers used by one lexer instance.
///
/// These buffers are reused across lexing calls when capacity permits. The
/// driver updates runtime sizes and input metadata before recording passes.
pub struct GpuBuffers {
    /// Current byte length, not including word-alignment padding.
    pub n: u32,
    /// Number of 256-byte DFA blocks for the current input.
    pub nb_dfa: u32,
    /// Number of 256-byte pair-scan blocks for the current input.
    pub nb_sum: u32,
    /// Host-visible copy of `parser_feature_flags` from the last count boundary.
    pub parser_feature_flags_value: u32,

    /// Uniform parameters shared by lexer shaders.
    pub params: LaniusBuffer<super::LexParams>,

    /// Uploaded source bytes, padded to a word boundary.
    pub in_bytes: LaniusBuffer<u8>,
    /// Packed DFA transition and emit table, two `u16` entries per `u32`.
    pub next_emit: LaniusBuffer<u32>,
    /// Packed byte-indexed DFA transition table, four states per `u32`.
    pub next_u8: LaniusBuffer<u32>,
    /// Map from DFA accepting state to token kind or `INVALID_TOKEN`.
    pub token_map: LaniusBuffer<u32>,

    /// Ping buffer for DFA block-prefix scans.
    pub dfa_02_ping: LaniusBuffer<u32>,
    /// Pong buffer for DFA block-prefix scans.
    pub dfa_02_pong: LaniusBuffer<u32>,
    /// Per-block DFA summaries retained for prefix application.
    pub dfa_chunk_summaries: LaniusBuffer<u32>,
    /// Raw token kinds by byte boundary; also reused by all-boundary compaction.
    pub tok_types: LaniusBuffer<u32>,
    /// Packed boundary and keep flags emitted by DFA prefix application.
    pub flags_packed: LaniusBuffer<u32>,
    /// Compact rank for every token boundary, including skipped tokens.
    pub s_all_final: LaniusBuffer<u32>,
    /// Compact rank for kept token boundaries.
    pub s_keep_final: LaniusBuffer<u32>,

    /// End positions for kept tokens.
    pub end_positions: LaniusBuffer<u32>,
    /// Token kinds compacted to kept-token order.
    pub types_compact: LaniusBuffer<u32>,
    /// Index from kept tokens back to the all-boundary stream.
    pub all_index_compact: LaniusBuffer<u32>,
    /// Number of kept tokens produced by the current input.
    pub token_count: LaniusBuffer<u32>,
    /// Conservative parser-family flags collected by the GPU token builder.
    pub parser_feature_flags: LaniusBuffer<u32>,

    /// Final resident token records consumed by parser and readback paths.
    pub tokens_out: LaniusBuffer<super::GpuToken>,
    /// Number of source files represented in the current input.
    pub source_file_count: LaniusBuffer<u32>,
    /// Concatenated-input start byte for each source file.
    pub source_file_start: LaniusBuffer<u32>,
    /// Byte length for each source file.
    pub source_file_len: LaniusBuffer<u32>,
    /// Per-byte flag marking source-file starts.
    pub source_file_start_flags: LaniusBuffer<u32>,
    /// Per-byte flag marking source-file ends.
    pub source_file_end_flags: LaniusBuffer<u32>,
    /// Source-file index for each final token.
    pub token_file_id: LaniusBuffer<u32>,
}

impl GpuBuffers {
    /// Allocates lexer buffers for a byte capacity and source-file capacity.
    ///
    /// The returned buffers are sized for capacity. The driver sets `n`,
    /// `nb_dfa`, `nb_sum`, input bytes, source-file metadata, and `LexParams`
    /// before each pass recording.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        n: u32,
        source_file_capacity: u32,
        start_state: u32,
        next_emit_packed: &[u32],
        next_u8_packed: &[u32],
        token_map: &[u32],
        skip_kinds: [u32; 4],
    ) -> Self {
        const BLOCK_WIDTH_DFA: u32 = 256;
        const BLOCK_WIDTH_SUM: u32 = 256;
        const DFA_CHUNK_COUNT: usize = 3;

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

        let token_map: LaniusBuffer<u32> =
            storage_ro_from_u32s_with_queue(device, queue, "token_map", token_map);

        let next_emit: LaniusBuffer<u32> =
            storage_ro_from_u32s_with_queue(device, queue, "next_emit", next_emit_packed);

        let next_u8: LaniusBuffer<u32> =
            storage_ro_from_u32s_with_queue(device, queue, "next_u8", next_u8_packed);

        let per_block_count = N_STATES * (nb_dfa as usize);
        let dfa_02_ping: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_ping", per_block_count);
        let dfa_02_pong: LaniusBuffer<u32> =
            storage_rw_for_array::<u32>(device, "block_pong", per_block_count);
        let dfa_chunk_summaries: LaniusBuffer<u32> = storage_rw_for_array::<u32>(
            device,
            "dfa_chunk_summaries",
            per_block_count * DFA_CHUNK_COUNT,
        );

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
        let parser_feature_flags =
            storage_rw_for_array::<u32>(device, "lexer.parser_feature_flags", 1);

        let tokens_out = storage_rw_for_array::<super::GpuToken>(device, "tokens_out", n as usize);
        let source_file_count = storage_rw_for_array::<u32>(device, "source_file_count", 1);
        let source_file_capacity = source_file_capacity.max(1) as usize;
        let source_file_start =
            storage_rw_for_array::<u32>(device, "source_file_start", source_file_capacity);
        let source_file_len =
            storage_rw_for_array::<u32>(device, "source_file_len", source_file_capacity);
        let source_file_start_flags =
            storage_rw_for_array::<u32>(device, "source_file_start_flags", n as usize + 1);
        let source_file_end_flags =
            storage_rw_for_array::<u32>(device, "source_file_end_flags", n as usize + 1);
        let token_file_id = storage_rw_for_array::<u32>(device, "token_file_id", n as usize);

        let params_val = LexParams {
            n,
            m: n_states as u32,
            start_state,
            skip0: skip_kinds[0],
            skip1: skip_kinds[1],
            skip2: skip_kinds[2],
            skip3: skip_kinds[3],
        };
        let params = uniform_from_val_with_queue(device, queue, "LexParams", &params_val);

        Self {
            n,
            nb_dfa,
            nb_sum,
            parser_feature_flags_value: 0,
            params,

            in_bytes,
            next_emit,
            next_u8,
            token_map,

            dfa_02_ping,
            dfa_02_pong,
            dfa_chunk_summaries,
            tok_types,
            flags_packed,

            s_all_final,
            s_keep_final,

            end_positions,
            types_compact,
            all_index_compact,
            token_count,
            parser_feature_flags,

            tokens_out,
            source_file_count,
            source_file_start,
            source_file_len,
            source_file_start_flags,
            source_file_end_flags,
            token_file_id,
        }
    }
}

impl From<LaniusBuffer<u8>> for LaniusBuffer<super::GpuToken> {
    fn from(b: LaniusBuffer<u8>) -> Self {
        let count = b.count;
        b.reinterpret(count)
    }
}
