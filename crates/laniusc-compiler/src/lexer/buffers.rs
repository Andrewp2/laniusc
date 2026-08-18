use super::{LexParams, compiler_graph::LexerCompilerGraph, passes::LexerPasses};
use crate::{
    gpu::{
        buffers::{
            DynamicUniformBuffer,
            LaniusBuffer,
            TrackedBufferView,
            dynamic_uniforms_from_vals_with_queue,
            readback_bytes,
            storage_ro_from_u32s_with_queue,
            storage_rw_for_array,
            storage_rw_uninit_bytes,
            uniform_from_val_with_queue,
        },
        operations::{ClearBuffersOperation, CopyBufferOperation},
    },
    lexer::tables::dfa::N_STATES,
};

/// Resident GPU buffers used by one lexer instance.
///
/// These buffers are reused across lexing calls when capacity permits. The
/// driver updates runtime sizes and input metadata before recording passes.
pub struct GpuBuffers {
    /// Owns the phase-colored storage aliased by the scratch and output views
    /// below. Buffer identity and lifetime come from this graph.
    pub(in crate::lexer) compiler_graph: LexerCompilerGraph,
    job_initialize: ClearBuffersOperation,
    count_readback: [CopyBufferOperation; 2],
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
    pub(in crate::lexer) dfa_scan_params: Option<DynamicUniformBuffer<super::passes::ScanParams>>,
    pub(in crate::lexer) pair_scan_params: Option<DynamicUniformBuffer<super::passes::ScanParams>>,
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
    /// Reused host-visible count/feature boundary for capacity-stable jobs.
    pub token_count_readback: LaniusBuffer<u8>,

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
    /// Returns lexer storage whose logical contents are dead after token
    /// materialization and whose physical allocation contains no retained
    /// token artifact.
    ///
    /// Lifetime coloring may place an early scratch row and a final output in
    /// the same allocation. Phase consumers must therefore filter by physical
    /// allocation identity rather than assuming a scratch field remains
    /// reusable merely because its logical lexer lifetime ended.
    pub(crate) fn post_lex_workspace(&self) -> Vec<TrackedBufferView<'_>> {
        let retained_allocations = [
            self.tokens_out.allocation_id(),
            self.token_count.allocation_id(),
            self.parser_feature_flags.allocation_id(),
            self.token_file_id.allocation_id(),
        ]
        .into_iter()
        .flatten()
        .collect::<std::collections::HashSet<_>>();
        let candidates: [TrackedBufferView<'_>; 7] = [
            (&self.tok_types).into(),
            (&self.flags_packed).into(),
            (&self.s_all_final).into(),
            (&self.s_keep_final).into(),
            (&self.end_positions).into(),
            (&self.types_compact).into(),
            (&self.all_index_compact).into(),
        ];
        candidates
            .into_iter()
            .filter(|buffer| {
                buffer
                    .allocation_id()
                    .is_none_or(|allocation| !retained_allocations.contains(&allocation))
            })
            .collect()
    }

    pub(in crate::lexer) fn record_job_initialize(&self, encoder: &mut wgpu::CommandEncoder) {
        self.job_initialize.record(encoder);
    }

    pub(in crate::lexer) fn record_count_readback(&self, encoder: &mut wgpu::CommandEncoder) {
        for copy in &self.count_readback {
            copy.record(encoder);
        }
    }

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
        passes: &LexerPasses,
    ) -> anyhow::Result<Self> {
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

        let compiler_graph = LexerCompilerGraph::new(
            device,
            n,
            source_file_capacity,
            next_emit_packed.len(),
            next_u8_packed.len(),
            token_map.len(),
            passes,
        )?;

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
        let dfa_02_ping: LaniusBuffer<u32> = compiler_graph.buffer("dfa_ping")?;
        let dfa_02_pong: LaniusBuffer<u32> = compiler_graph.buffer("dfa_pong")?;
        let dfa_chunk_summaries: LaniusBuffer<u32> =
            compiler_graph.buffer("dfa_chunk_summaries")?;
        debug_assert_eq!(dfa_02_ping.count, per_block_count);
        debug_assert_eq!(dfa_chunk_summaries.count, per_block_count * DFA_CHUNK_COUNT);
        let dfa_scan_values = (0..super::util::compute_rounds(nb_dfa))
            .map(|round| super::passes::ScanParams {
                stride: 1u32 << round,
                use_ping_as_src: u32::from(round % 2 == 0),
            })
            .collect::<Vec<_>>();
        let dfa_scan_params = (!dfa_scan_values.is_empty()).then(|| {
            dynamic_uniforms_from_vals_with_queue(
                device,
                queue,
                "ScanParams[FUNC-BLOCKS]",
                &dfa_scan_values,
            )
        });
        let pair_scan_values = super::passes::pair::block_total_scan_steps(nb_sum)
            .into_iter()
            .map(|step| super::passes::ScanParams {
                stride: step.scan_step,
                use_ping_as_src: u32::from(step.read_from_a),
            })
            .collect::<Vec<_>>();
        let pair_scan_params = (!pair_scan_values.is_empty()).then(|| {
            dynamic_uniforms_from_vals_with_queue(
                device,
                queue,
                "ScanParams[PAIR-BLOCKS]",
                &pair_scan_values,
            )
        });

        let tok_types: LaniusBuffer<u32> = compiler_graph.buffer("tok_types")?;

        let flags_packed: LaniusBuffer<u32> = compiler_graph.buffer("flags_packed")?;

        // end_excl_by_i eliminated (computed inline); pair scan reuses dfa_02 ping/pong

        let s_all_final: LaniusBuffer<u32> = compiler_graph.buffer("s_all_final")?;
        let s_keep_final: LaniusBuffer<u32> = compiler_graph.buffer("s_keep_final")?;

        let end_positions: LaniusBuffer<u32> = compiler_graph.buffer("end_positions")?;
        let types_compact: LaniusBuffer<u32> = compiler_graph.buffer("types_compact")?;
        let all_index_compact: LaniusBuffer<u32> = compiler_graph.buffer("all_index_compact")?;

        let token_count: LaniusBuffer<u32> = compiler_graph.buffer("token_count")?;
        let parser_feature_flags: LaniusBuffer<u32> =
            compiler_graph.buffer("parser_feature_flags")?;
        let token_count_readback = readback_bytes(device, "rb.lex.resident.token_count", 8, 8);

        let tokens_out: LaniusBuffer<super::GpuToken> = compiler_graph.buffer("tokens_out")?;
        let source_file_count = storage_rw_for_array::<u32>(device, "source_file_count", 1);
        let source_file_capacity = source_file_capacity.max(1) as usize;
        let source_file_start =
            storage_rw_for_array::<u32>(device, "source_file_start", source_file_capacity);
        let source_file_len =
            storage_rw_for_array::<u32>(device, "source_file_len", source_file_capacity);
        let source_file_start_flags: LaniusBuffer<u32> =
            compiler_graph.buffer("source_file_start_flags")?;
        let source_file_end_flags: LaniusBuffer<u32> =
            compiler_graph.buffer("source_file_end_flags")?;
        let token_file_id: LaniusBuffer<u32> = compiler_graph.buffer("token_file_id")?;

        let job_initialize = compiler_graph.job_initialize_operation(
            &flags_packed,
            &source_file_start_flags,
            &source_file_end_flags,
            &token_count,
            &parser_feature_flags,
        )?;
        let count_readback = compiler_graph.count_readback_operations(
            &token_count,
            &parser_feature_flags,
            &token_count_readback,
        )?;

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

        Ok(Self {
            compiler_graph,
            job_initialize,
            count_readback,
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
            dfa_scan_params,
            pair_scan_params,
            tok_types,
            flags_packed,

            s_all_final,
            s_keep_final,

            end_positions,
            types_compact,
            all_index_compact,
            token_count,
            parser_feature_flags,
            token_count_readback,

            tokens_out,
            source_file_count,
            source_file_start,
            source_file_len,
            source_file_start_flags,
            source_file_end_flags,
            token_file_id,
        })
    }
}

impl crate::gpu::passes_core::CompilerGraphBuffers for GpuBuffers {
    fn validate_compiler_pass(
        &self,
        operation: &'static str,
        resources: &std::collections::HashMap<String, wgpu::BindingResource<'_>>,
        dispatch_args: Option<&crate::gpu::buffers::LaniusBuffer<u32>>,
    ) -> anyhow::Result<()> {
        self.compiler_graph
            .validate_reflected_runtime_bindings(operation, resources, dispatch_args)
    }
}

impl From<LaniusBuffer<u8>> for LaniusBuffer<super::GpuToken> {
    fn from(b: LaniusBuffer<u8>) -> Self {
        let count = b.count;
        b.reinterpret(count)
    }
}
