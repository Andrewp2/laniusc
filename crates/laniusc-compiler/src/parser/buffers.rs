//! GPU buffer allocation for parser token facts, pair streams, tree rows, and HIR rows.

mod constructors;
mod model;
mod scan_steps;
mod scans;
mod sizing;
mod storage;
pub use model::{
    ActionHeader,
    GpuHirView,
    HirArrayElement,
    HirCallArg,
    HirCore,
    HirField,
    HirGenericParam,
    HirLinks,
    HirMatchArm,
    HirMatchPayload,
    HirMethodCore,
    HirMethodSignature,
    HirParam,
    HirPath,
    HirPathSegment,
    HirPayload,
    HirPredicate,
    HirRange,
    HirSemanticFacts,
    HirString,
    HirTypeArg,
    HirVariant,
    HirVariantPayload,
    ParserBuffers,
    TokenBraceMatchParams,
    TokenDelimiterParams,
};
pub use scan_steps::*;
use scans::*;
pub(crate) use sizing::resident_partial_parse_tree_capacity_for_tables;
use sizing::{
    ParserFamilyCapacities,
    resident_partial_parse_tree_capacity,
    resident_virtual_pair_width,
};
use storage::{
    alias_storage_buffer,
    dispatch_args_buffer,
    dispatch_args_schedule_buffer,
    dispatch_args_schedule_with_count_buffer,
    reuse_or_allocate_u32_workspace,
    u32_workspace_subrange,
    workspace_subrange,
};
pub(crate) use storage::{dispatch_args_schedule_count_offset, pointer_jump_step_capacity};

use crate::gpu::buffers::{
    LaniusBuffer,
    TrackedBufferView,
    readback_bytes,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

pub(crate) fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut bytes = encase::UniformBuffer::new(Vec::<u8>::new());
    bytes
        .write(value)
        .expect("failed to encode active parser parameters");
    buffer.write(queue, 0, bytes.as_ref());
}

impl ParserBuffers {
    /// Updates the logical token dimensions for a reused resident allocation.
    /// Physical storage may be larger, but parser dispatches and token-boundary
    /// uniforms must describe only the current job.
    pub(crate) fn set_active_token_capacity(&mut self, queue: &wgpu::Queue, token_capacity: u32) {
        let token_capacity = token_capacity.max(1);
        let n_tokens = token_capacity.saturating_add(2);
        self.n_tokens = n_tokens;
        self.token_input_capacity = token_capacity;
        self.token_delimiter_n_blocks = self.token_input_capacity.div_ceil(256).max(1);
        let n_pairs = n_tokens.saturating_sub(1);
        self.total_sc = n_pairs.saturating_mul(self.resident_sc_width);
        self.total_emit = n_pairs.saturating_mul(self.resident_emit_width);
        write_uniform(
            queue,
            &self.params_llp,
            &super::passes::llp_pairs::LLPParams {
                n_tokens,
                n_kinds: self.n_kinds,
            },
        );
        // PackParams contains table-blob offsets that are resident-allocation
        // specific. Rewrite only the logical fields and the physical output
        // capacities; leave the six table offsets resident.
        let pack_prefix = [
            n_tokens,
            self.n_kinds,
            self.total_sc,
            self.total_emit,
            self.out_sc.count as u32,
            self.out_emit.count as u32,
        ];
        let mut pack_bytes = [0u8; 24];
        for (index, value) in pack_prefix.into_iter().enumerate() {
            pack_bytes[index * 4..index * 4 + 4].copy_from_slice(&value.to_le_bytes());
        }
        self.params_pack.write(queue, 0, &pack_bytes);
        write_uniform(
            queue,
            &self.token_delimiter_params,
            &TokenDelimiterParams {
                n_tokens: self.token_input_capacity,
                n_blocks: self.token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        write_uniform(
            queue,
            &self.token_brace_match_params,
            &TokenBraceMatchParams {
                n_tokens: self.token_input_capacity,
            },
        );
        write_uniform(
            queue,
            &self.source_file_token_end_params,
            &super::passes::source_file_token_end::Params { token_capacity },
        );
        // Bracket scratch is allocated to the resident maximum, but the
        // current packed stream may be smaller. Keep the per-pass logical
        // stream bound in sync while retaining the physical block tree: the
        // latter is deliberately reused across jobs and its zeroed tail is
        // part of the stable workspace contract.
        write_uniform(
            queue,
            &self.b01_params,
            &super::passes::brackets::scan_inblock::Params {
                n_sc: self.total_sc,
                wg_size: 256,
            },
        );
        write_uniform(
            queue,
            &self.b03_params,
            &super::passes::brackets::apply_prefix::Params {
                n_sc: self.total_sc,
                wg_size: 256,
            },
        );
        write_uniform(
            queue,
            &self.b07_params,
            &super::passes::brackets::pse_pair::Params {
                n_sc: self.total_sc,
                n_blocks: self.b_n_blocks,
                leaf_base: self.b_min_tree_base,
                typed_check: 1,
                emit_matches: u32::from(self.emit_stack_matches),
            },
        );
        write_uniform(
            queue,
            &self.b_clear_matches_params,
            &super::passes::brackets::clear_matches::Params {
                n_sc: self.total_sc,
            },
        );
    }

    /// Restores writable job storage to the zeroed state guaranteed for a
    /// fresh WGPU allocation. Logical aliases share an allocation identity,
    /// so each physical buffer is cleared at most once.
    pub(crate) fn clear_job_storage(&self, encoder: &mut wgpu::CommandEncoder) {
        for buffer in &self.resettable_buffers {
            if buffer.byte_size == 0 {
                continue;
            }
            debug_assert_eq!(buffer.byte_size % wgpu::COPY_BUFFER_ALIGNMENT, 0);
            encoder.clear_buffer(&buffer.buffer, 0, Some(buffer.byte_size));
        }
    }

    pub(crate) fn resettable_storage_totals(&self) -> (usize, u64) {
        (
            self.resettable_buffers.len(),
            self.resettable_buffers
                .iter()
                .map(|buffer| buffer.byte_size)
                .sum(),
        )
    }

    /// Returns every parser allocation whose contents are dead after compact
    /// HIR materialization. An allocation containing any retained HIR range is
    /// conservatively excluded in full.
    pub(crate) fn post_hir_workspace<'a>(&'a self, hir: &GpuHirView) -> Vec<TrackedBufferView<'a>> {
        let retained = hir.retained_allocation_ids();
        self.resettable_buffers
            .iter()
            .filter(|buffer| !retained.contains(&buffer.allocation_id))
            .map(crate::gpu::buffers::ResettableBuffer::tracked_view)
            .collect()
    }
}

impl ParserBuffers {
    fn new_with_sizing(
        device: &wgpu::Device,
        n_tokens: u32,
        source_capacity: u32,
        token_kinds_u32: Option<&[u32]>,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        resident_partial_parse_capacity: bool,
        retain_debug_hir_buffers: bool,
        tree_capacity_override: Option<u32>,
        parser_feature_flags: u32,
    ) -> Self {
        let n_pairs = n_tokens.saturating_sub(1) as usize;
        let token_input_capacity = n_tokens.saturating_sub(2).max(1);
        let token_delimiter_n_blocks = token_input_capacity.div_ceil(256).max(1);
        let pair_capacity = n_pairs.max(1);
        let ll1_status = storage_rw_for_array::<u32>(device, "parser.ll1_status", 6);
        let ll1_status_readback =
            readback_bytes(device, "rb.parser.recorded_ll1_hir.status", 32, 32);

        let stream_has_soi = token_kinds_u32
            .map(|kinds| kinds.first().copied() == Some(0))
            .unwrap_or(true);
        let first_input = if n_tokens > 1 && stream_has_soi { 1 } else { 0 };
        // Match the canonical LL(1) stream: the last token is the EOF sentinel and is not
        // consumed as ordinary input.
        let input_end = n_tokens.saturating_sub(1);
        let n_input_tokens = input_end.saturating_sub(first_input);
        let token_count = storage_ro_from_u32s(device, "parser.token_count", &[n_input_tokens]);
        let active_pair_thread_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_thread_dispatch_args");
        let active_pair_group_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_group_dispatch_args");
        // ---------- Pair-to-header ----------
        let semantic_token_kinds = if let Some(kinds) = token_kinds_u32 {
            // Test/debug one-shot parsing receives already-classified parser
            // token kinds. Resident compilation fills this buffer on the GPU
            // with `tokens_to_kinds` instead.
            storage_ro_from_u32s(device, "parser.semantic_token_kinds.input", kinds)
        } else {
            storage_rw_for_array::<u32>(device, "parser.semantic_token_kinds", n_tokens as usize)
        };
        let token_delimiter_params = uniform_from_val(
            device,
            "parser.token_delimiters.params",
            &TokenDelimiterParams {
                n_tokens: token_input_capacity,
                n_blocks: token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        let token_delimiter_scan_steps =
            make_token_delimiter_scan_steps(device, token_input_capacity, token_delimiter_n_blocks);
        let token_depth_paren_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_paren_inblock",
            token_input_capacity as usize,
        );
        let token_depth_brace_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_brace_inblock",
            token_input_capacity as usize,
        );
        let token_depth_bracket_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_bracket_inblock",
            n_tokens.max(1) as usize,
        );
        let token_depth_angle_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_angle_inblock",
            token_input_capacity as usize,
        );
        let token_block_sum_paren = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_paren",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_angle = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_angle",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_paren_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_paren_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_paren_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_paren_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_paren = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_paren",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_angle_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_angle_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_angle_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_angle_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_angle = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_angle",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_brace_semantic_kind",
            n_tokens.max(1) as usize,
        );
        let token_braced_rhs_statement_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_braced_rhs_statement_kind",
            token_input_capacity as usize,
        );
        let token_bracket_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_bracket_semantic_kind",
            token_input_capacity as usize,
        );
        let token_statement_context_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_context_kind",
            token_input_capacity as usize,
        );
        let token_impl_header_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_impl_header_kind",
            token_input_capacity as usize,
        );
        let token_impl_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_impl_context_event",
            token_input_capacity as usize,
        );
        let token_type_path_context_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_type_path_context_kind",
            token_input_capacity as usize,
        );
        let token_where_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_where_context_event",
            token_input_capacity as usize,
        );
        let token_match_pattern_context_event = storage_rw_for_array::<u32>(
            device,
            "parser.token_match_pattern_context_event",
            token_input_capacity as usize,
        );
        let token_generic_shr_block_sum = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.block_sum",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_prefix_sum_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.prefix_sum_a",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_prefix_sum_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.prefix_sum_b",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_prefix_min_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.prefix_min_a",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_prefix_min_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.prefix_min_b",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_block_prefix_sum = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.block_prefix_sum",
            token_delimiter_n_blocks as usize,
        );
        let token_generic_shr_block_prefix_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_generic_shr.block_prefix_min",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_match_params = uniform_from_val(
            device,
            "parser.token_brace_match.params",
            &TokenBraceMatchParams {
                n_tokens: token_input_capacity,
            },
        );
        let token_brace_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_depth",
            token_input_capacity as usize,
        );
        let token_brace_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_match_min_tree_base =
            next_power_of_two_u32(token_delimiter_n_blocks).max(1);
        let token_brace_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_brace_match_min_tree_steps = make_tree_prefix_max_build_steps(
            device,
            token_delimiter_n_blocks,
            token_brace_match_min_tree_base,
        );
        let token_bracket_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_depth",
            token_input_capacity as usize,
        );
        let token_bracket_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_bracket_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_bracket_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_paren_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_depth",
            token_input_capacity as usize,
        );
        let token_paren_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_paren_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_paren_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_angle_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_depth",
            token_input_capacity as usize,
        );
        let token_angle_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_angle_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_angle_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_feature_flags = if token_kinds_u32.is_some() {
            storage_ro_from_u32s(
                device,
                "parser.token_feature_flags.conservative",
                &[u32::MAX],
            )
        } else {
            storage_ro_from_u32s(device, "parser.token_feature_flags", &[0])
        };

        let params_llp = uniform_from_val(
            device,
            "parser.params_llp",
            &super::passes::llp_pairs::LLPParams { n_tokens, n_kinds },
        );

        let action_table = if action_table_bytes.is_empty() {
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

        let out_headers: LaniusBuffer<ActionHeader> = storage_rw_for_array::<ActionHeader>(
            device,
            "parser.out_headers",
            pair_capacity.saturating_add(1),
        );

        // ---------- Pack varlen ----------
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        if resident_partial_parse_capacity {
            let max_sc_len = resident_virtual_pair_width(&tables.sc_len, n_kinds);
            let max_emit_len = resident_virtual_pair_width(&tables.pp_len, n_kinds);
            acc_sc = (n_pairs as u32).saturating_mul(max_sc_len);
            acc_emit = (n_pairs as u32).saturating_mul(max_emit_len);
        } else {
            let token_kinds_u32 =
                token_kinds_u32.expect("non-resident parser sizing requires explicit token kinds");
            for i in 0..n_pairs {
                let prev = token_kinds_u32[i];
                let thisk = token_kinds_u32[i + 1];
                let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
                acc_sc += tables.sc_len[idx2d];
                acc_emit += tables.pp_len[idx2d];
            }
        }
        let total_sc = acc_sc;
        let total_emit = acc_emit;
        let resident_sc_width = if resident_partial_parse_capacity {
            resident_virtual_pair_width(&tables.sc_len, n_kinds)
        } else {
            0
        };
        let resident_emit_width = if resident_partial_parse_capacity {
            resident_virtual_pair_width(&tables.pp_len, n_kinds)
        } else {
            0
        };
        let tree_count_uses_status = true;
        let tree_capacity = tree_capacity_override
            .unwrap_or_else(|| {
                if tree_count_uses_status {
                    resident_partial_parse_tree_capacity(total_emit)
                } else {
                    total_emit
                }
            })
            .max(1);
        let emit_capacity = if resident_partial_parse_capacity {
            tree_capacity
        } else {
            total_emit.max(1)
        };

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
            &super::passes::pack::varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_capacity: total_sc.max(1),
                emit_capacity,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );
        let pack_offsets_status_params = uniform_from_val(
            device,
            "pack.offset_status.params",
            &super::passes::pack::offsets::status::Params {
                n_pairs: n_tokens.saturating_sub(1),
                emit_capacity,
            },
        );

        let n_pack_pairs = pair_capacity;
        let sc_offsets = storage_rw_for_array::<u32>(device, "pack.sc_offsets", n_pack_pairs);
        let emit_offsets = storage_rw_for_array::<u32>(device, "pack.emit_offsets", n_pack_pairs);
        let pack_sc_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_a", n_pack_pairs);
        let pack_sc_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_b", n_pack_pairs);
        let pack_emit_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_a", n_pack_pairs);
        let pack_emit_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_b", n_pack_pairs);
        let pack_offset_scan_steps =
            make_pack_offset_scan_steps(device, n_tokens.saturating_sub(1));
        let pack_total_reduce_steps =
            make_pack_total_reduce_steps(device, n_tokens.saturating_sub(1));
        let partial_parse_status =
            storage_rw_for_array::<u32>(device, "pack.partial_parse_status", 6);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);
        let out_sc = storage_rw_for_array::<u32>(device, "pack.out_sc", total_sc.max(1) as usize);
        let out_emit = storage_rw_for_array::<u32>(device, "pack.out_emit", emit_capacity as usize);
        let out_emit_pos =
            storage_rw_for_array::<u32>(device, "pack.out_emit_pos", emit_capacity as usize);

        // ---------- Brackets (parallel) ----------
        //
        // Resident parsing validates stack effects before publishing acceptance,
        // so bracket scratch is sized to the conservative stack capacity.
        const WG: u32 = 256;
        let bracket_capacity = total_sc.max(1);
        let n_blocks = total_sc.div_ceil(WG).max(1);

        let b01_params = uniform_from_val(
            device,
            "brackets.b01.params",
            &super::passes::brackets::scan_inblock::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );
        let b02_params = uniform_from_val(
            device,
            "brackets.b02.params",
            &super::passes::brackets::scan_block_prefix::Params {
                n_blocks,
                scan_step: 0,
            },
        );
        let b02_scan_steps = make_brackets_block_prefix_scan_steps(device, n_blocks);
        let b03_params = uniform_from_val(
            device,
            "brackets.b03.params",
            &super::passes::brackets::apply_prefix::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );

        let emit_stack_matches = retain_debug_hir_buffers || !resident_partial_parse_capacity;
        let b07_params = uniform_from_val(
            device,
            "brackets.b07.params",
            &super::passes::brackets::pse_pair::Params {
                n_sc: total_sc,
                n_blocks,
                leaf_base: next_power_of_two_u32(n_blocks).max(1),
                typed_check: 1,
                emit_matches: u32::from(emit_stack_matches),
            },
        );
        let b_clear_matches_params = uniform_from_val(
            device,
            "brackets.clear_matches.params",
            &super::passes::brackets::clear_matches::Params { n_sc: total_sc },
        );
        let b_min_tree_base = next_power_of_two_u32(n_blocks).max(1);
        let b_min_tree = storage_rw_for_array::<i32>(
            device,
            "brackets.min_tree",
            b_min_tree_base.saturating_mul(2) as usize,
        );
        let b_min_tree_steps = make_tree_prefix_max_build_steps(device, n_blocks, b_min_tree_base);

        let b_exscan_inblock = storage_rw_for_array::<i32>(
            device,
            "brackets.exscan_inblock",
            bracket_capacity as usize,
        );
        let b_block_sum =
            storage_rw_for_array::<i32>(device, "brackets.block_sum", n_blocks as usize);
        let b_block_minpref =
            storage_rw_for_array::<i32>(device, "brackets.block_minpref", n_blocks as usize);
        let b_block_row_min =
            storage_rw_for_array::<i32>(device, "brackets.block_row_min", n_blocks as usize);
        let b_block_maxdepth =
            storage_rw_for_array::<i32>(device, "brackets.block_maxdepth", n_blocks as usize);
        let b_block_prefix =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix", n_blocks as usize);
        let b_block_prefix_sum_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_a", n_blocks as usize);
        let b_block_prefix_sum_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_b", n_blocks as usize);
        let b_block_prefix_min_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_a", n_blocks as usize);
        let b_block_prefix_min_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_b", n_blocks as usize);

        let depths_out = storage_rw_for_array::<i32>(device, "brackets.depths_out", 3);
        let valid_out = storage_rw_for_array::<u32>(device, "brackets.valid_out", 1);

        let b_layer =
            storage_rw_for_array::<u32>(device, "brackets.layer", bracket_capacity as usize);
        // Production validation only writes the match table when a later raw
        // tree consumer or a debug readback needs it. Otherwise its allocation
        // is phase-colored HIR scratch and only needs dense tree capacity.
        let match_capacity = if emit_stack_matches {
            bracket_capacity
        } else {
            tree_capacity
        };
        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            match_capacity as usize,
        );

        // ---------- Tree parent recovery ----------
        let family_capacities = ParserFamilyCapacities::new(tree_capacity, parser_feature_flags);
        let tree_n_node_blocks = tree_capacity.div_ceil(WG).max(1);
        let tree_n_prefix_blocks = tree_capacity.saturating_add(1).div_ceil(WG).max(1);
        let tree_prefix_params_base = super::passes::tree::prefix::local::Params {
            n: tree_capacity,
            uses_status_count: u32::from(tree_count_uses_status),
            n_node_blocks: tree_n_node_blocks,
            n_prefix_blocks: tree_n_prefix_blocks,
            scan_step: 0,
        };
        let tree_prefix_params = uniform_from_val(
            device,
            "parser.tree_prefix.params",
            &tree_prefix_params_base,
        );
        let tree_active_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_active_dispatch_args");
        let tree_enum_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_enum_dispatch_args");
        let tree_match_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_match_dispatch_args");
        let tree_struct_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_struct_dispatch_args");
        let tree_pointer_jump_dispatch_args = dispatch_args_schedule_with_count_buffer(
            device,
            "parser.tree_pointer_jump_dispatch_args",
            pointer_jump_step_capacity(tree_capacity) as usize,
        );
        let hir_semantic_dispatch_args =
            dispatch_args_buffer(device, "parser.hir_semantic_dispatch_args");
        let hir_semantic_depth_block_max = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_depth_block_max",
            tree_n_node_blocks as usize,
        );
        let hir_semantic_pointer_jump_dispatch_args = dispatch_args_schedule_buffer(
            device,
            "parser.hir_semantic_pointer_jump_dispatch_args",
            pointer_jump_step_capacity(tree_capacity) as usize,
        );
        let tree_prefix_scan_steps =
            make_tree_prefix_scan_steps(device, tree_prefix_params_base, tree_n_node_blocks);
        let tree_prefix_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_inblock",
            tree_capacity as usize,
        );
        let tree_block_sum = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_sum",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_a = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_b = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix",
            tree_n_node_blocks as usize,
        );
        let tree_prefix =
            storage_rw_for_array::<i32>(device, "parser.tree_prefix", tree_capacity as usize + 1);
        let tree_prefix_block_max = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max",
            tree_n_prefix_blocks as usize,
        );
        let tree_prefix_block_max_tree_base = next_power_of_two_u32(tree_n_prefix_blocks).max(1);
        let tree_prefix_block_max_tree = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max_tree",
            tree_prefix_block_max_tree_base.saturating_mul(2) as usize,
        );
        let tree_prefix_max_build_steps = make_tree_prefix_max_build_steps(
            device,
            tree_n_prefix_blocks,
            tree_prefix_block_max_tree_base,
        );

        // Shared tables/outputs
        let prod_arity = storage_ro_from_u32s(device, "parser.prod_arity", &tables.prod_arity);
        let node_kind =
            storage_rw_for_array::<u32>(device, "parser.node_kind", tree_capacity as usize);
        let parent = storage_rw_for_array::<u32>(device, "parser.parent", tree_capacity as usize);
        let tree_params = uniform_from_val(
            device,
            "parser.tree_parent.params",
            &super::passes::tree::parent::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_span_params = uniform_from_val(
            device,
            "parser.tree_spans.params",
            &super::passes::tree::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_prev_sibling_params = uniform_from_val(
            device,
            "parser.tree_prev_sibling.params",
            &super::passes::tree::prev::sibling::clear::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let first_child =
            storage_rw_for_array::<u32>(device, "parser.first_child", tree_capacity as usize);
        let next_sibling =
            storage_rw_for_array::<u32>(device, "parser.next_sibling", tree_capacity as usize);
        let prev_sibling =
            storage_rw_for_array::<u32>(device, "parser.prev_sibling", tree_capacity as usize);
        let subtree_end =
            storage_rw_for_array::<u32>(device, "parser.subtree_end", tree_capacity as usize);
        let hir_params = uniform_from_val(
            device,
            "parser.hir_nodes.params",
            &super::passes::hir::nodes::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                semantic_parent_local_ancestor_span:
                    super::passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_span_params = uniform_from_val(
            device,
            "parser.hir_spans.params",
            &super::passes::hir::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
            },
        );
        let hir_type_fields_params = uniform_from_val(
            device,
            "parser.hir_type_fields.params",
            &super::passes::hir::types::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_item_fields_params = uniform_from_val(
            device,
            "parser.hir_item_fields.params",
            &super::passes::hir::item::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_param_fields_params = uniform_from_val(
            device,
            "parser.hir_param_fields.params",
            &super::passes::hir::param::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_method_fields_params = uniform_from_val(
            device,
            "parser.hir_method_fields.params",
            &super::passes::hir::method::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_expr_fields_params = uniform_from_val(
            device,
            "parser.hir_expr_fields.params",
            &super::passes::hir::expr::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_member_fields_params = uniform_from_val(
            device,
            "parser.hir_member_fields.params",
            &super::passes::hir::member::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_stmt_fields_params = uniform_from_val(
            device,
            "parser.hir_stmt_fields.params",
            &super::passes::hir::stmt_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_call_fields_params = uniform_from_val(
            device,
            "parser.hir_call_fields.params",
            &super::passes::hir::call::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_array_fields_params = uniform_from_val(
            device,
            "parser.hir_array_fields.params",
            &super::passes::hir::array::fields::Params {
                n: family_capacities.arrays,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_enum_match_fields_params = uniform_from_val(
            device,
            "parser.hir_enum_match_fields.params",
            &super::passes::hir::enums::match_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                family_flags: u32::from(
                    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0,
                ) | (u32::from(
                    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0,
                ) << 1),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_struct_fields_params = uniform_from_val(
            device,
            "parser.hir_struct_fields.params",
            &super::passes::hir::structs::fields::Params {
                n: family_capacities.structs,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_kind", tree_capacity as usize);
        let hir_semantic_block_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_block_count",
            tree_n_node_blocks as usize,
        );
        let hir_semantic_prefix_scan_steps =
            make_hir_semantic_prefix_scan_steps(device, tree_n_node_blocks);
        // Raw type records still alias the parser prefix arrays in resident
        // compilation, and remain live through type checking during the HIR
        // migration. Keep canonical-family scan storage distinct until every
        // consumer reads compact type metadata instead of those raw columns.
        let hir_semantic_flag =
            storage_rw_for_array::<u32>(device, "parser.hir_semantic_flag", tree_capacity as usize);
        let hir_semantic_local_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_local_prefix",
            tree_capacity as usize,
        );
        let hir_semantic_block_prefix_a =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_a, tree_n_node_blocks as usize);
        let hir_semantic_block_prefix_b =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_b, tree_n_node_blocks as usize);
        let hir_node_dense_id =
            storage_rw_for_array::<u32>(device, "parser.hir_node_dense_id", tree_capacity as usize);
        let hir_semantic_prefix_before_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_prefix_before_node",
            tree_capacity as usize,
        );
        let reuse_semantic_debug_buffers =
            resident_partial_parse_capacity && !retain_debug_hir_buffers;
        // This intermediate navigation still retains context-carrying grammar
        // wrappers, so it is not yet covered by the canonical token-anchor
        // bound. It becomes token-sized only when those relations move to the
        // canonical HIR graph.
        let semantic_dense_capacity = tree_capacity;
        let hir_semantic_dense_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_dense_node",
            semantic_dense_capacity as usize,
        );
        let hir_semantic_subtree_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_subtree_end",
            tree_capacity as usize,
        );
        let hir_semantic_count =
            storage_rw_for_array::<u32>(device, "parser.hir_semantic_count", 1);
        let hir_semantic_parent = if reuse_semantic_debug_buffers {
            // `hir_semantic_prefix_before_node` is only live until
            // `hir_semantic_subtree_end` projects dense ranges. Production
            // resident compilation does not read it back, so the durable dense
            // parent records can reuse that tree-sized allocation.
            alias_storage_buffer::<u32, u32>(
                &hir_semantic_prefix_before_node,
                tree_capacity as usize,
            )
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_semantic_parent",
                tree_capacity as usize,
            )
        };
        let hir_semantic_first_child = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_first_child",
            semantic_dense_capacity as usize,
        );
        let hir_semantic_next_sibling = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_next_sibling",
            semantic_dense_capacity as usize,
        );
        let hir_semantic_depth = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_depth",
            tree_capacity as usize,
        );
        let hir_semantic_child_index = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_child_index",
            tree_capacity as usize,
        );
        // Shared scratch for Pareas-style linked-list pointer jumping. The
        // durable HIR outputs remain in their own buffers; these workspaces are
        // overwritten by each list-family link/rank/scatter sequence. In the
        // resident non-debug path, stack validation has finished before any of
        // these workspaces are used, so reuse its twelve dead allocations. A
        // size check preserves correctness when a grammar's tree capacity is
        // larger than its stack-effect stream capacity.
        let out_sc_slot0 = reuse_semantic_debug_buffers
            .then(|| u32_workspace_subrange(device, &out_sc, 0, tree_capacity as usize))
            .flatten();
        let out_sc_slot1 = reuse_semantic_debug_buffers
            .then(|| u32_workspace_subrange(device, &out_sc, 1, tree_capacity as usize))
            .flatten();
        let bracket_scan_slot0 = reuse_semantic_debug_buffers
            .then(|| {
                u32_workspace_subrange(device, &b_exscan_inblock, 0, tree_capacity as usize)
            })
            .flatten();
        let bracket_scan_slot1 = reuse_semantic_debug_buffers
            .then(|| {
                u32_workspace_subrange(device, &b_exscan_inblock, 1, tree_capacity as usize)
            })
            .flatten();
        let bracket_layer_slot0 = reuse_semantic_debug_buffers
            .then(|| u32_workspace_subrange(device, &b_layer, 0, tree_capacity as usize))
            .flatten();
        let bracket_layer_slot1 = reuse_semantic_debug_buffers
            .then(|| u32_workspace_subrange(device, &b_layer, 1, tree_capacity as usize))
            .flatten();
        let hir_list0_owner_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_owner_a",
            tree_capacity as usize,
            out_sc_slot0.as_ref(),
        );
        let hir_list0_owner_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_owner_b",
            tree_capacity as usize,
            None,
        );
        let hir_list0_link_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_link_a",
            tree_capacity as usize,
            out_sc_slot1.as_ref(),
        );
        let hir_list0_link_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_link_b",
            tree_capacity as usize,
            None,
        );
        let hir_list0_rank_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_rank_a",
            tree_capacity as usize,
            bracket_scan_slot0.as_ref(),
        );
        let hir_list0_rank_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list0_rank_b",
            tree_capacity as usize,
            None,
        );
        let hir_list1_owner_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_owner_a",
            tree_capacity as usize,
            bracket_scan_slot1.as_ref(),
        );
        let hir_list1_owner_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_owner_b",
            tree_capacity as usize,
            None,
        );
        let hir_list1_link_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_link_a",
            tree_capacity as usize,
            bracket_layer_slot0.as_ref(),
        );
        let hir_list1_link_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_link_b",
            tree_capacity as usize,
            None,
        );
        let hir_list1_rank_a = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_rank_a",
            tree_capacity as usize,
            bracket_layer_slot1.as_ref(),
        );
        let hir_list1_rank_b = reuse_or_allocate_u32_workspace(
            device,
            "parser.hir_list1_rank_b",
            tree_capacity as usize,
            reuse_semantic_debug_buffers.then_some(&match_for_index),
        );
        let hir_semantic_parent_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_parent_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_parent_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_semantic_parent_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_semantic_depth_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_depth_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_depth_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_depth_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_semantic_child_index_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_child_index_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_child_index_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_child_index_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_token_pos =
            storage_rw_for_array::<u32>(device, "parser.hir_token_pos", tree_capacity as usize);
        let hir_token_end =
            storage_rw_for_array::<u32>(device, "parser.hir_token_end", tree_capacity as usize);
        let hir_token_file_id =
            storage_rw_for_array::<u32>(device, "parser.hir_token_file_id", tree_capacity as usize);
        let (hir_type_form, hir_type_value_node, hir_type_len_token, hir_type_len_value) =
            if resident_partial_parse_capacity {
                // Resident compilation does not expose packed productions as
                // parser debug artifacts. After `hir_nodes`, the production
                // streams and tree-prefix scratch are dead, so reuse them for
                // tree-sized type metadata.
                (
                    alias_storage_buffer::<u32, u32>(&out_emit, tree_capacity as usize),
                    alias_storage_buffer::<u32, u32>(&out_emit_pos, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix_inblock, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix, tree_capacity as usize),
                )
            } else {
                (
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_form",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_value_node",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_token",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_value",
                        tree_capacity as usize,
                    ),
                )
            };
        let hir_type_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        // Right-recursive list families use a previous-node record only from
        // their link pass through the immediately following scatter pass.
        // Reuse one scratch buffer across those phases; durable next/start/count
        // records remain separately allocated below.
        let hir_previous_scratch = storage_rw_for_array::<u32>(
            device,
            "parser.hir_previous_scratch",
            tree_capacity as usize,
        );

        // Dense subtree bounds remain live through type checking, where they
        // define flattened recursive type comparisons. Keep the later durable
        // type-leaf relation in distinct storage even in production mode.
        let hir_type_path_leaf_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_path_leaf_node",
            tree_capacity as usize,
        );
        let hir_bound_path_owner_by_leaf = storage_rw_for_array::<u32>(
            device,
            "parser.hir_bound_path_owner_by_leaf",
            tree_capacity as usize,
        );
        let hir_path_root_owner =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_path_segment_owner_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_path_segment_owner",
            tree_capacity as usize,
        );
        let hir_path_segment_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_path_segment_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_path_segment_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_path_segment_rank_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_path_segment_rank",
            tree_capacity as usize,
        );
        let hir_path_segment_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_path_segment_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_path_segment_count",
            tree_capacity as usize,
        );
        let hir_type_path_leaf_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_path_leaf_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_path_leaf_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_path_leaf_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_start",
            tree_capacity as usize,
        );
        let hir_type_arg_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_count",
            tree_capacity as usize,
        );
        let hir_type_arg_next =
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_next", tree_capacity as usize);
        let hir_type_alias_target_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_alias_target_node",
            tree_capacity as usize,
        );
        let hir_fn_return_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_fn_return_type_node",
            tree_capacity as usize,
        );
        // Function-signature ownership is a transient pointer-jump family. It
        // starts after type-alias ownership has been consumed. The function
        // owner row remains live through parameter-link seeding, so keep it on
        // the second scratch family while parameter ranks reuse list0.
        let hir_fn_signature_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_fn_signature_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_fn_signature_return_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_fn_signature_return_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_fn_signature_function_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_fn_signature_function_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_type_arg_owner_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_owner_a",
            tree_capacity as usize,
        );
        let hir_type_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_arg_rank_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_arg_rank_a",
            tree_capacity as usize,
        );
        let hir_type_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_type_arg_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_type_root_owner = storage_rw_for_array::<u32>(
            device,
            "parser.hir_type_root_owner",
            tree_capacity as usize,
        );
        let hir_type_alias_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_alias_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_alias_owner_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_alias_owner_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_item_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_item_kind", tree_capacity as usize);
        let hir_item_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_name_token",
            token_input_capacity as usize,
        );
        let hir_item_namespace = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_namespace",
            token_input_capacity as usize,
        );
        let hir_item_visibility = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_visibility",
            token_input_capacity as usize,
        );
        let hir_item_path_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_start",
            token_input_capacity as usize,
        );
        let hir_item_path_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_end",
            token_input_capacity as usize,
        );
        let hir_item_path_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_node",
            token_input_capacity as usize,
        );
        let hir_item_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        let hir_item_import_target_kind = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_import_target_kind",
            token_input_capacity as usize,
        );
        let hir_param_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_param_record",
            token_input_capacity.saturating_mul(4) as usize,
        );
        let hir_param_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_param_type_node",
            token_input_capacity as usize,
        );
        let method_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_PREDICATES != 0;
        let member_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MEMBERS != 0;
        let enum_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0;
        let match_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0;
        let string_expr_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRING_EXPRS != 0;
        // Optional HIR families have consumers that index their scalar rows by
        // arbitrary source node even when the family is absent. Preserve that
        // full address space while sharing the two immutable default states:
        // INVALID and zero. The normal HIR clear passes initialize these rows
        // on the GPU. A present family always receives independent storage.
        let optional_invalid_sentinel =
            (!(method_required
                && member_required
                && enum_required
                && match_required
                && string_expr_required))
                .then(|| {
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_optional_invalid_sentinel",
                        tree_capacity as usize,
                    )
                });
        let optional_zero_sentinel =
            (!(method_required && enum_required && string_expr_required)).then(|| {
                storage_rw_for_array::<u32>(
                    device,
                    "parser.hir_optional_zero_sentinel",
                    tree_capacity as usize,
                )
            });
        let optional_invalid_row = |required, label| {
            if required {
                storage_rw_for_array::<u32>(device, label, tree_capacity as usize)
            } else {
                alias_storage_buffer::<u32, u32>(
                    optional_invalid_sentinel
                        .as_ref()
                        .expect("absent optional HIR family requires INVALID sentinel"),
                    tree_capacity as usize,
                )
            }
        };
        let optional_zero_row = |required, label| {
            if required {
                storage_rw_for_array::<u32>(device, label, tree_capacity as usize)
            } else {
                alias_storage_buffer::<u32, u32>(
                    optional_zero_sentinel
                        .as_ref()
                        .expect("absent optional HIR family requires zero sentinel"),
                    tree_capacity as usize,
                )
            }
        };
        let hir_method_owner_node =
            optional_invalid_row(method_required, "parser.hir_method_owner_node");
        let hir_method_impl_node =
            optional_invalid_row(method_required, "parser.hir_method_impl_node");
        let hir_method_name_token =
            optional_invalid_row(method_required, "parser.hir_method_name_token");
        let hir_method_first_param_token =
            optional_invalid_row(method_required, "parser.hir_method_first_param_token");
        let hir_method_receiver_mode =
            optional_zero_row(method_required, "parser.hir_method_receiver_mode");
        let hir_method_visibility =
            optional_zero_row(method_required, "parser.hir_method_visibility");
        let hir_method_signature_flags =
            optional_zero_row(method_required, "parser.hir_method_signature_flags");
        let hir_method_impl_receiver_type_node =
            optional_invalid_row(method_required, "parser.hir_method_impl_receiver_type_node");
        let hir_param_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_param_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_param_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_param_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let stmt_record_words = tree_capacity.saturating_mul(4) as usize;
        let stmt_slot_bytes = tree_capacity as u64 * core::mem::size_of::<u32>() as u64;
        let storage_alignment =
            u64::from(device.limits().min_storage_buffer_offset_alignment.max(1));
        let stmt_slot_stride = stmt_slot_bytes.div_ceil(storage_alignment) * storage_alignment;
        let stmt_arena_words = if retain_debug_hir_buffers {
            stmt_record_words
        } else {
            stmt_slot_stride.saturating_mul(4).div_ceil(4) as usize
        };
        let hir_stmt_record_arena = storage_rw_for_array::<u32>(
            device,
            "parser.hir_stmt_record",
            stmt_arena_words,
        );
        let hir_stmt_record = hir_stmt_record_arena
            .subrange(0, stmt_record_words as u64 * 4, stmt_record_words)
            .expect("statement record view must fit its phase arena");
        // Once canonical identity gathers the compact statement record, these
        // four aligned ranges become call/array/match/struct raw-family rows.
        let call_phase_row = |label: &str, slot: usize| {
            if retain_debug_hir_buffers {
                storage_rw_for_array::<u32>(device, label, tree_capacity as usize)
            } else {
                u32_workspace_subrange(
                    device,
                    &hir_stmt_record_arena,
                    slot,
                    tree_capacity as usize,
                )
                .expect("statement arena must contain four call-family slots")
            }
        };
        let hir_call_arg_end = call_phase_row("parser.hir_call_arg_end", 0);
        let hir_call_arg_count = call_phase_row("parser.hir_call_arg_count", 1);
        let hir_call_arg_parent_call = call_phase_row("parser.hir_call_arg_parent_call", 2);
        let hir_call_arg_ordinal = call_phase_row("parser.hir_call_arg_ordinal", 3);
        // Absent enum/match families still have source-node-addressed consumers
        // in type checking and codegen, so use the common optional sentinels.
        let enum_phase_row = |label: &str| {
            if !enum_required {
                alias_storage_buffer::<u32, u32>(
                    optional_invalid_sentinel
                        .as_ref()
                        .expect("absent enum HIR family requires INVALID sentinel"),
                    tree_capacity as usize,
                )
            } else {
                storage_rw_for_array::<u32>(device, label, tree_capacity as usize)
            }
        };
        let hir_variant_parent_enum = enum_phase_row("parser.hir_variant_parent_enum");
        let hir_variant_ordinal = enum_phase_row("parser.hir_variant_ordinal");
        let enum_debug_capacity = if enum_required && retain_debug_hir_buffers {
            tree_capacity as usize
        } else {
            1
        };
        let hir_variant_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_start",
            enum_debug_capacity,
        );
        let hir_variant_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_count",
            enum_debug_capacity,
        );
        let hir_variant_payload_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_node",
            if enum_required && retain_debug_hir_buffers {
                tree_capacity.saturating_mul(4) as usize
            } else {
                1
            },
        );
        let hir_variant_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_variant_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_variant_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_variant_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_variant_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_variant_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_variant_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_variant_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_variant_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_variant_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_variant_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_variant_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_rank_flag =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_flag", tree_capacity as usize);
        let hir_rank_local_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_local_prefix",
            tree_capacity as usize,
        );
        let hir_rank_block_sum = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_sum",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let hir_rank_node =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_node", tree_capacity as usize);
        let hir_rank_count = storage_rw_for_array::<u32>(device, "parser.hir_rank_count", 1);
        let hir_rank_dispatch_args = dispatch_args_buffer(device, "parser.hir_rank_dispatch_args");
        let hir_list_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_list_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_list_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_list_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_list_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_list_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_enum_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_enum_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_enum_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_enum_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_enum_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_enum_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_match_scrutinee_node =
            optional_invalid_row(match_required, "parser.hir_match_scrutinee_node");
        let match_debug_capacity = if match_required && retain_debug_hir_buffers {
            tree_capacity as usize
        } else {
            1
        };
        let hir_match_arm_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_start",
            match_debug_capacity,
        );
        let hir_match_arm_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_count",
            match_debug_capacity,
        );
        let hir_match_arm_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_next",
            match_debug_capacity,
        );
        let match_phase_row = |label: &str, reuse: &LaniusBuffer<u32>| {
            if !match_required {
                alias_storage_buffer::<u32, u32>(
                    optional_invalid_sentinel
                        .as_ref()
                        .expect("absent match HIR family requires INVALID sentinel"),
                    tree_capacity as usize,
                )
            } else if retain_debug_hir_buffers {
                storage_rw_for_array::<u32>(device, label, tree_capacity as usize)
            } else {
                alias_storage_buffer::<u32, u32>(reuse, tree_capacity as usize)
            }
        };
        let hir_match_arm_pattern_node = match_phase_row(
            "parser.hir_match_arm_pattern_node",
            &hir_call_arg_parent_call,
        );
        let hir_match_pattern_owner_arm = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_pattern_owner_arm",
            match_debug_capacity,
        );
        let hir_match_arm_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_start",
            match_debug_capacity,
        );
        let hir_match_arm_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_count",
            match_debug_capacity,
        );
        let hir_match_arm_result_node = match_phase_row(
            "parser.hir_match_arm_result_node",
            &hir_call_arg_end,
        );
        // Arm rows and pattern-payload rows are disjoint productions.  The
        // arm's pattern reference and the payload's owner-arm reference may
        // therefore occupy one raw-tree column without either pass observing
        // an overlapping element.
        let hir_match_payload_owner_arm = match_phase_row(
            "parser.hir_match_payload_owner_arm",
            &hir_call_arg_parent_call,
        );
        let hir_match_payload_match_node = match_phase_row(
            "parser.hir_match_payload_match_node",
            &hir_call_arg_count,
        );
        let hir_match_payload_ordinal = match_phase_row(
            "parser.hir_match_payload_ordinal",
            &hir_call_arg_ordinal,
        );
        let hir_match_arm_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_match_arm_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_match_arm_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_match_arm_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_match_arm_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_match_arm_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_match_arm_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_match_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_match_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_match_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_match_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_match_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_match_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_match_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_match_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_match_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_match_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_match_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_match_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_call_callee_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_callee_node",
            tree_capacity as usize,
        );
        let hir_call_callee_path_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_callee_path_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_call_parent_by_callee = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_parent_by_callee",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_call_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_context_stmt_node",
            if retain_debug_hir_buffers {
                tree_capacity as usize
            } else {
                1
            },
        );
        let hir_call_arg_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_start",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_call_arg_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_call_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_call_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_call_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_call_arg_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_call_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_lit_first_element = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_first_element",
            if retain_debug_hir_buffers {
                family_capacities.arrays as usize
            } else {
                1
            },
        );
        let hir_array_lit_element_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_element_count",
            if retain_debug_hir_buffers {
                family_capacities.arrays as usize
            } else {
                1
            },
        );
        let hir_array_lit_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_context_stmt_node",
            if retain_debug_hir_buffers {
                family_capacities.arrays as usize
            } else {
                1
            },
        );
        let hir_array_element_parent_lit = if retain_debug_hir_buffers {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_array_element_parent_lit",
                family_capacities.arrays as usize,
            )
        } else {
            alias_storage_buffer::<u32, u32>(
                &hir_call_arg_parent_call,
                family_capacities.arrays as usize,
            )
        };
        let hir_array_element_ordinal = if retain_debug_hir_buffers {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_array_element_ordinal",
                family_capacities.arrays as usize,
            )
        } else {
            alias_storage_buffer::<u32, u32>(
                &hir_call_arg_ordinal,
                family_capacities.arrays as usize,
            )
        };
        let hir_array_element_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_next",
            if retain_debug_hir_buffers {
                family_capacities.arrays as usize
            } else {
                1
            },
        );
        let hir_array_element_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_array_element_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_array_element_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_array_element_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_array_element_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_array_element_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_element_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let expr_record_words = tree_capacity.saturating_mul(4) as usize;
        let expr_arena_words = if retain_debug_hir_buffers {
            expr_record_words
        } else {
            // The raw four-word expression record owns this arena until
            // canonical identity has gathered it. Afterwards, six compact
            // four-word side tables occupy aligned, disjoint ranges. Fields
            // use durable storage because their final compaction is later than
            // the other expression-arena consumers. Size for
            // both lifetimes explicitly: token and raw-tree capacities are
            // related by grammar expansion, but neither is guaranteed larger.
            let compact_slot_bytes = u64::from(token_input_capacity)
                .saturating_mul(4)
                .saturating_mul(core::mem::size_of::<u32>() as u64);
            let compact_slot_stride = compact_slot_bytes
                .div_ceil(storage_alignment)
                .saturating_mul(storage_alignment);
            let raw_expr_bytes = (expr_record_words as u64).saturating_mul(4);
            raw_expr_bytes
                .max(compact_slot_stride.saturating_mul(6))
                .div_ceil(4) as usize
        };
        let hir_expr_record_arena = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_record",
            expr_arena_words,
        );
        let hir_expr_record = hir_expr_record_arena
            .subrange(0, expr_record_words as u64 * 4, expr_record_words)
            .expect("expression record view must fit its phase arena");
        let hir_expr_name_role = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_name_role",
            tree_capacity as usize,
        );
        let hir_expr_result_root_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_result_root_node",
            tree_capacity as usize,
        );
        let hir_expr_result_root_scratch_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_result_root_scratch_node",
            tree_capacity as usize,
        );
        let hir_binary_span_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_binary_span_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_binary_span_start_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_binary_span_start_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_expr_int_value = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_int_value",
            if retain_debug_hir_buffers {
                tree_capacity as usize
            } else {
                token_input_capacity as usize
            },
        );
        let hir_expr_float_bits = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_float_bits",
            if retain_debug_hir_buffers {
                tree_capacity as usize
            } else {
                token_input_capacity as usize
            },
        );
        let literal_row_capacity = if retain_debug_hir_buffers {
            tree_capacity
        } else {
            token_input_capacity
        };
        let hir_expr_string_start = if string_expr_required {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_expr_string_start",
                literal_row_capacity as usize,
            )
        } else {
            alias_storage_buffer::<u32, u32>(
                optional_invalid_sentinel
                    .as_ref()
                    .expect("absent string HIR family requires INVALID sentinel"),
                tree_capacity as usize,
            )
        };
        let hir_expr_string_len = if string_expr_required {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_expr_string_len",
                literal_row_capacity as usize,
            )
        } else {
            alias_storage_buffer::<u32, u32>(
                optional_zero_sentinel
                    .as_ref()
                    .expect("absent string HIR family requires zero sentinel"),
                tree_capacity as usize,
            )
        };
        let hir_literal_values_params = uniform_from_val(
            device,
            "parser.hir_literal_values.params",
            &super::passes::hir::literal_values::Params {
                n: tree_capacity,
                source_len: source_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_string_decode_params = uniform_from_val(
            device,
            "parser.hir_string_decode.params",
            &super::passes::hir::string::decode::Params {
                n: tree_capacity,
                source_len: source_capacity,
                pool_capacity: source_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_string_data_offset = storage_rw_for_array::<u32>(
            device,
            "parser.hir_string_data_offset",
            if string_expr_required {
                literal_row_capacity as usize
            } else {
                1
            },
        );
        let hir_string_decoded_len = storage_rw_for_array::<u32>(
            device,
            "parser.hir_string_decoded_len",
            if string_expr_required {
                literal_row_capacity as usize
            } else {
                1
            },
        );
        let hir_string_data_words = storage_rw_for_array::<u32>(
            device,
            "parser.hir_string_data_words",
            if string_expr_required {
                source_capacity.max(1).div_ceil(4) as usize
            } else {
                1
            },
        );
        let hir_string_pool_len =
            storage_rw_for_array::<u32>(device, "parser.hir_string_pool_len", 1);
        let hir_string_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_string_node",
            if string_expr_required {
                tree_capacity as usize
            } else {
                1
            },
        );
        let hir_string_count = storage_rw_for_array::<u32>(device, "parser.hir_string_count", 1);
        let hir_member_receiver_node =
            optional_invalid_row(member_required, "parser.hir_member_receiver_node");
        let hir_member_receiver_token =
            optional_invalid_row(member_required, "parser.hir_member_receiver_token");
        let hir_member_name_token =
            optional_invalid_row(member_required, "parser.hir_member_name_token");
        let hir_stmt_scope_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_stmt_scope_end",
            tree_capacity as usize,
        );
        let hir_nearest_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_stmt_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_nearest_block_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_block_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_nearest_enclosing_control_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_enclosing_control_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_nearest_loop_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_loop_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_nearest_fn_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_fn_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let hir_nearest_array_element_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_nearest_array_element_node",
            if retain_debug_hir_buffers { tree_capacity as usize } else { 1 },
        );
        let struct_phase_row = |label: &str, reuse: &LaniusBuffer<u32>| {
            if retain_debug_hir_buffers {
                storage_rw_for_array::<u32>(device, label, family_capacities.structs as usize)
            } else {
                alias_storage_buffer::<u32, u32>(reuse, family_capacities.structs as usize)
            }
        };
        // Calls, arrays, and matches have all been compacted before struct
        // reconstruction starts. Reuse those four raw columns for the four
        // simultaneously-live struct facts.
        let hir_struct_field_parent_struct = struct_phase_row(
            "parser.hir_struct_field_parent_struct",
            &hir_call_arg_parent_call,
        );
        let hir_struct_field_ordinal = struct_phase_row(
            "parser.hir_struct_field_ordinal",
            &hir_call_arg_ordinal,
        );
        let hir_struct_field_type_node = struct_phase_row(
            "parser.hir_struct_field_type_node",
            &hir_call_arg_end,
        );
        let hir_struct_decl_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_start",
            if retain_debug_hir_buffers {
                family_capacities.structs as usize
            } else {
                1
            },
        );
        let hir_struct_decl_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_count",
            if retain_debug_hir_buffers {
                family_capacities.structs as usize
            } else {
                1
            },
        );
        let hir_struct_lit_head_node = struct_phase_row(
            "parser.hir_struct_lit_head_node",
            &hir_call_arg_count,
        );
        let hir_struct_lit_context_stmt_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_context_stmt_node",
            if retain_debug_hir_buffers {
                family_capacities.structs as usize
            } else {
                1
            },
        );
        let hir_struct_lit_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_start",
            if retain_debug_hir_buffers {
                family_capacities.structs as usize
            } else {
                1
            },
        );
        let hir_struct_lit_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_count",
            if retain_debug_hir_buffers {
                family_capacities.structs as usize
            } else {
                1
            },
        );
        // These facts are written through distinct shader bindings in the
        // same struct passes. Even though declaration and literal field rows
        // are disjoint grammar productions, overlapping writable bindings do
        // not establish a valid GPU ownership contract. Keep the physical
        // ranges distinct until declaration fields have been compacted.
        let hir_struct_lit_field_parent_lit = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_parent_lit",
            family_capacities.structs as usize,
        );
        let hir_struct_lit_field_value_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_value_node",
            family_capacities.structs as usize,
        );
        // `prev_sibling` is consumed for the last time by
        // `hir_struct_field_links`. The following rank/scatter passes do not
        // read it, so the final struct-literal next-link output can reuse that
        // tree-sized buffer instead of retaining one more parser allocation.
        let hir_struct_lit_field_next =
            alias_storage_buffer::<u32, u32>(&prev_sibling, tree_capacity as usize);
        let hir_struct_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_struct_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_struct_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_struct_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_struct_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_struct_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_struct_lit_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_struct_lit_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_struct_lit_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_struct_lit_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_struct_lit_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_stmt_context_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_stmt_context_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_contextual_stmt_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_contextual_stmt_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_nearest_stmt_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_nearest_stmt_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_nearest_block_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_nearest_block_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_nearest_enclosing_control_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_nearest_enclosing_control_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_nearest_loop_value_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_nearest_loop_value_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_nearest_fn_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_nearest_fn_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        // These scratch rows are dead after expression-root and array-element
        // records are finalized, immediately before context propagation starts.
        let hir_nearest_array_element_value_a =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_nearest_array_element_value_b = alias_storage_buffer::<u32, u32>(
            &hir_expr_result_root_scratch_node,
            tree_capacity as usize,
        );
        let hir_struct_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_struct_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_struct_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_struct_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_struct_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_struct_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let default_token_file_id = storage_rw_for_array::<u32>(
            device,
            "parser.default_token_file_id",
            n_tokens.max(1) as usize,
        );
        let source_file_token_end_params = uniform_from_val(
            device,
            "parser.source_file_token_end.params",
            &super::passes::source_file_token_end::Params {
                token_capacity: token_input_capacity,
            },
        );
        let source_file_token_end = storage_rw_for_array::<u32>(
            device,
            "parser.source_file_token_end",
            token_input_capacity as usize,
        );

        // Canonical HIR is the durable parser phase output. Candidate rows are
        // deduplicated by source-token anchor, so the token capacity is a hard
        // checked upper bound rather than a grammar-amplified estimate.
        let hir_canonical_capacity = token_input_capacity;
        assert!(
            tree_capacity < (1u32 << 28),
            "raw parse-tree capacity exceeds canonical HIR anchor arbitration range",
        );
        let hir_canonical_params = uniform_from_val(
            device,
            "parser.hir_canonical.params",
            &super::passes::hir::canonical::CanonicalHirParams {
                raw_capacity: tree_capacity,
                canonical_capacity: hir_canonical_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                local_ancestor_span: super::passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
                records_use_token_rows: u32::from(!retain_debug_hir_buffers),
            },
        );
        let hir_canonical_count =
            storage_rw_for_array::<u32>(device, "parser.hir_canonical_count", 1);
        let hir_canonical_status =
            storage_rw_for_array::<u32>(device, "parser.hir_canonical_status", 13);
        // Family compaction resolves structural wrappers through the elected
        // source-anchor winner. Once every compact family has materialized,
        // the declaration-index passes repurpose this storage as the compact
        // type-declaration-name-token -> dense-HIR map retained by GpuHirView.
        let hir_canonical_anchor_owner = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_anchor_owner",
            hir_canonical_capacity as usize,
        );
        // Semantic navigation/depth construction finishes before canonical
        // identity starts. Production mode can therefore hand three dead
        // semantic-tree rows to the canonical raw/dense maps. Debug mode keeps
        // the original rows intact for parser readback.
        let hir_canonical_prefix_before_raw = if reuse_semantic_debug_buffers {
            alias_storage_buffer::<u32, u32>(
                &hir_semantic_child_index,
                tree_capacity as usize,
            )
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_canonical_prefix_before_raw",
                tree_capacity as usize,
            )
        };
        let hir_canonical_dense_to_raw = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_dense_to_raw",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_alias_to_dense = if reuse_semantic_debug_buffers {
            alias_storage_buffer::<u32, u32>(&hir_semantic_subtree_end, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_canonical_alias_to_dense",
                tree_capacity as usize,
            )
        };
        let hir_canonical_raw_to_dense = if reuse_semantic_debug_buffers {
            alias_storage_buffer::<u32, u32>(&hir_semantic_depth, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_canonical_raw_to_dense",
                tree_capacity as usize,
            )
        };
        let hir_canonical_stmt_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_stmt_record",
            hir_canonical_capacity.saturating_mul(4) as usize,
        );
        let hir_canonical_expr_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_expr_record",
            hir_canonical_capacity.saturating_mul(4) as usize,
        );
        let hir_core = storage_rw_for_array::<HirCore>(
            device,
            "parser.hir_core",
            hir_canonical_capacity as usize,
        );
        let hir_links = storage_rw_for_array::<HirLinks>(
            device,
            "parser.hir_links",
            hir_canonical_capacity as usize,
        );
        let hir_payload = storage_rw_for_array::<HirPayload>(
            device,
            "parser.hir_payload",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_semantic_facts = storage_rw_for_array::<HirSemanticFacts>(
            device,
            "parser.hir_canonical_semantic_facts",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_semantic_dense_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_semantic_dense_node",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_scope_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_scope_end",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_nearest_loop = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_nearest_loop",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_nearest_block = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_nearest_block",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_nearest_control = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_nearest_control",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_nearest_fn = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_nearest_fn",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_context_stmt = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_context_stmt",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_fn_return_type = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_fn_return_type",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_type_root_owner = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_type_root_owner",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_type_alias_target = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_type_alias_target",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_const_type = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_const_type",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_const_value = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_const_value",
            hir_canonical_capacity as usize,
        );
        // Parent publication uses owner-plus-one so the buffer can be reset
        // with a native zero clear. Once root initialization has decoded it,
        // the same physical slot becomes the pointer-jump scratch buffer.
        let hir_canonical_expr_parent_encoded = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_expr_parent_encoded",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_expr_parent = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_expr_parent",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_expr_root = storage_rw_for_array::<u32>(
            device,
            "parser.hir_canonical_expr_root",
            hir_canonical_capacity as usize,
        );
        let hir_canonical_expr_root_scratch = alias_storage_buffer::<u32, u32>(
            &hir_canonical_expr_parent_encoded,
            hir_canonical_capacity as usize,
        );
        let hir_canonical_expr_forest_status =
            storage_rw_for_array::<u32>(device, "parser.hir_canonical_expr_forest_status", 1);
        let hir_call_arg_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_call_arg_table_count", 1);
        let hir_call_arg_family_flag = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_family_flag",
            tree_capacity as usize,
        );
        let hir_call_args = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirCallArg>(
                device,
                "parser.hir_call_args",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirCallArg>(
                device,
                &hir_expr_record_arena,
                0,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact call arguments")
        };
        let hir_call_arg_ranges = storage_rw_for_array::<HirRange>(
            device,
            "parser.hir_call_arg_ranges",
            hir_canonical_capacity as usize,
        );
        let hir_param_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_param_table_count", 1);
        // Call arguments are captured early, then consumed before parameter
        // and type-argument compaction begins. All three family marks therefore
        // occupy one serial HIR-family workspace slot.
        let hir_param_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_param_rows = storage_rw_for_array::<HirParam>(
            device,
            "parser.hir_params",
            hir_canonical_capacity as usize,
        );
        let hir_param_ranges = storage_rw_for_array::<HirRange>(
            device,
            "parser.hir_param_ranges",
            hir_canonical_capacity as usize,
        );
        let hir_type_arg_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_table_count", 1);
        let hir_type_arg_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_type_arg_rows = storage_rw_for_array::<HirTypeArg>(
            device,
            "parser.hir_type_args",
            hir_canonical_capacity as usize,
        );
        let hir_type_arg_ranges = storage_rw_for_array::<HirRange>(
            device,
            "parser.hir_type_arg_ranges",
            hir_canonical_capacity as usize,
        );
        let hir_generic_param_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_generic_param_table_count", 1);
        let hir_generic_param_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_generic_param_rows = storage_rw_for_array::<HirGenericParam>(
            device,
            "parser.hir_generic_params",
            hir_canonical_capacity as usize,
        );
        let hir_generic_param_ranges = storage_rw_for_array::<HirRange>(
            device,
            "parser.hir_generic_param_ranges",
            hir_canonical_capacity as usize,
        );
        let hir_path_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_path_table_count", 1);
        let hir_path_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_path_rows = storage_rw_for_array::<HirPath>(
            device,
            "parser.hir_paths",
            hir_canonical_capacity as usize,
        );
        let hir_path_segment_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_path_segment_table_count", 1);
        let hir_path_segment_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_path_segment_rows = storage_rw_for_array::<HirPathSegment>(
            device,
            "parser.hir_path_segments",
            hir_canonical_capacity as usize,
        );
        let hir_field_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_field_table_count", 1);
        let hir_field_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_field_rows = storage_rw_for_array::<HirField>(
            device,
            "parser.hir_fields",
            hir_canonical_capacity as usize,
        );
        let hir_variant_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_variant_table_count", 1);
        let hir_variant_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_variant_rows = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirVariant>(
                device,
                "parser.hir_variants",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirVariant>(
                device,
                &hir_expr_record_arena,
                1,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact variants")
        };
        // This map is migration-only: the raw typechecker still consumes the
        // path-owner workspace after compact HIR materialization, so the two
        // lifetimes cannot alias yet. Once name resolution consumes compact
        // paths, this map can take that phase-colored slot.
        let hir_variant_raw_to_row = if retain_debug_hir_buffers {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_variant_raw_to_row",
                tree_capacity as usize,
            )
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_variant_raw_to_row",
                tree_capacity as usize,
            )
        };
        let hir_variant_compact_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_compact_payload_start",
            hir_canonical_capacity as usize,
        );
        let hir_variant_compact_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_compact_payload_count",
            hir_canonical_capacity as usize,
        );
        let hir_variant_payload_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_variant_payload_table_count", 1);
        let hir_variant_payload_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_variant_payload_rows = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirVariantPayload>(
                device,
                "parser.hir_variant_payloads",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirVariantPayload>(
                device,
                &hir_expr_record_arena,
                2,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact variant payloads")
        };
        let hir_match_arm_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_match_arm_table_count", 1);
        let hir_match_arm_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_match_arm_raw_to_row =
            alias_storage_buffer::<u32, u32>(&hir_variant_raw_to_row, tree_capacity as usize);
        let hir_match_arm_rows = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirMatchArm>(
                device,
                "parser.hir_match_arms",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirMatchArm>(
                device,
                &hir_expr_record_arena,
                3,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact match arms")
        };
        let hir_match_arm_ranges = storage_rw_for_array::<HirRange>(
            device,
            "parser.hir_match_arm_ranges",
            hir_canonical_capacity as usize,
        );
        let hir_match_pattern_to_arm = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_pattern_to_arm",
            hir_canonical_capacity as usize,
        );
        let hir_match_compact_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_compact_payload_start",
            hir_canonical_capacity as usize,
        );
        let hir_match_compact_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_compact_payload_count",
            hir_canonical_capacity as usize,
        );
        let hir_match_payload_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_match_payload_table_count", 1);
        let hir_match_payload_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_match_payload_rows = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirMatchPayload>(
                device,
                "parser.hir_match_payloads",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirMatchPayload>(
                device,
                &hir_expr_record_arena,
                4,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact match payloads")
        };
        let hir_array_compact_element_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_compact_element_start",
            hir_canonical_capacity as usize,
        );
        let hir_array_compact_element_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_compact_element_count",
            hir_canonical_capacity as usize,
        );
        let hir_array_element_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_array_element_table_count", 1);
        let hir_array_element_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_array_element_rows = if retain_debug_hir_buffers {
            storage_rw_for_array::<HirArrayElement>(
                device,
                "parser.hir_array_elements",
                hir_canonical_capacity as usize,
            )
        } else {
            workspace_subrange::<_, HirArrayElement>(
                device,
                &hir_expr_record_arena,
                5,
                hir_canonical_capacity as usize,
            )
            .expect("expression arena must fit compact array elements")
        };
        let hir_canonical_string_rows = storage_rw_for_array::<HirString>(
            device,
            "parser.hir_canonical_strings",
            hir_canonical_capacity as usize,
        );
        let hir_method_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_method_table_count", 1);
        let hir_method_family_flag =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_family_flag, tree_capacity as usize);
        let hir_method_core_rows = storage_rw_for_array::<HirMethodCore>(
            device,
            "parser.hir_method_cores",
            hir_canonical_capacity as usize,
        );
        let hir_method_signature_rows = storage_rw_for_array::<HirMethodSignature>(
            device,
            "parser.hir_method_signatures",
            hir_canonical_capacity as usize,
        );
        let hir_predicate_table_count =
            storage_rw_for_array::<u32>(device, "parser.hir_predicate_table_count", 1);
        let hir_predicate_rows = storage_rw_for_array::<HirPredicate>(
            device,
            "parser.hir_predicates",
            hir_canonical_capacity as usize,
        );

        Self {
            resettable_buffers: Vec::new(),
            source_capacity: source_capacity.max(1),
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,
            resident_sc_width,
            resident_emit_width,
            tree_count_uses_status,
            tree_capacity,
            parser_feature_flags,
            hir_array_capacity: family_capacities.arrays,
            hir_enum_match_capacity: family_capacities.enum_match,
            hir_struct_capacity: family_capacities.structs,
            hir_canonical_capacity,
            retain_debug_hir_buffers,

            ll1_status,
            ll1_status_readback,
            params_llp,
            semantic_token_kinds,
            token_delimiter_params,
            token_delimiter_scan_steps,
            token_input_capacity,
            token_delimiter_n_blocks,
            token_depth_paren_inblock,
            token_depth_brace_inblock,
            token_depth_bracket_inblock,
            token_depth_angle_inblock,
            token_block_sum_paren,
            token_block_sum_brace,
            token_block_sum_bracket,
            token_block_sum_angle,
            token_prefix_paren_a,
            token_prefix_paren_b,
            token_block_prefix_paren,
            token_prefix_brace_a,
            token_prefix_brace_b,
            token_block_prefix_brace,
            token_prefix_bracket_a,
            token_prefix_bracket_b,
            token_block_prefix_bracket,
            token_prefix_angle_a,
            token_prefix_angle_b,
            token_block_prefix_angle,
            token_top_brace_owner_block,
            token_top_brace_owner_prefix_a,
            token_top_brace_owner_prefix_b,
            token_top_brace_owner_block_prefix,
            token_statement_event_block,
            token_statement_event_prefix_a,
            token_statement_event_prefix_b,
            token_statement_event_block_prefix,
            token_brace_semantic_kind,
            token_braced_rhs_statement_kind,
            token_bracket_semantic_kind,
            token_statement_context_kind,
            token_impl_header_kind,
            token_impl_context_event,
            token_type_path_context_kind,
            token_where_context_event,
            token_match_pattern_context_event,
            token_generic_shr_block_sum,
            token_generic_shr_block_min,
            token_generic_shr_prefix_sum_a,
            token_generic_shr_prefix_sum_b,
            token_generic_shr_prefix_min_a,
            token_generic_shr_prefix_min_b,
            token_generic_shr_block_prefix_sum,
            token_generic_shr_block_prefix_min,
            token_brace_match_params,
            token_brace_match_depth,
            token_brace_match_block_min,
            token_brace_match_min_tree_base,
            token_brace_match_min_tree,
            token_brace_match_min_tree_steps,
            token_bracket_match_depth,
            token_bracket_match_block_min,
            token_bracket_match_min_tree,
            token_paren_match_depth,
            token_paren_match_block_min,
            token_paren_match_min_tree,
            token_angle_match_depth,
            token_angle_match_block_min,
            token_angle_match_min_tree,
            token_feature_flags,
            token_count,
            default_token_file_id,
            source_file_token_end_params,
            source_file_token_end,
            active_pair_thread_dispatch_args,
            active_pair_group_dispatch_args,
            action_table,
            out_headers,

            params_pack,
            pack_offsets_status_params,
            sc_offsets,
            emit_offsets,
            pack_sc_prefix_a,
            pack_sc_prefix_b,
            pack_emit_prefix_a,
            pack_emit_prefix_b,
            pack_offset_scan_steps,
            pack_total_reduce_steps,
            partial_parse_status,
            tables_blob,
            out_sc,
            out_emit,
            out_emit_pos,

            b01_params,
            b02_params,
            b02_scan_steps,
            b03_params,
            b07_params,
            b_clear_matches_params,
            emit_stack_matches,
            b_min_tree_base,
            b_min_tree,
            b_min_tree_steps,

            b_exscan_inblock,
            b_block_sum,
            b_block_minpref,
            b_block_row_min,
            b_block_maxdepth,
            b_block_prefix,
            b_block_prefix_sum_a,
            b_block_prefix_sum_b,
            b_block_prefix_min_a,
            b_block_prefix_min_b,

            depths_out,
            valid_out,

            b_layer,
            match_for_index,

            b_n_blocks: n_blocks,

            // Tree parent recovery
            tree_prefix_params,
            tree_prefix_scan_steps,
            tree_n_node_blocks,
            tree_active_dispatch_args,
            tree_enum_dispatch_args,
            tree_match_dispatch_args,
            tree_struct_dispatch_args,
            tree_pointer_jump_dispatch_args,
            hir_semantic_dispatch_args,
            hir_semantic_depth_block_max,
            hir_semantic_pointer_jump_dispatch_args,
            tree_prefix_inblock,
            tree_block_sum,
            tree_block_prefix_a,
            tree_block_prefix_b,
            tree_block_prefix,
            tree_prefix,
            tree_prefix_block_max,
            tree_prefix_block_max_tree,
            tree_prefix_max_build_steps,
            tree_params,
            tree_span_params,
            tree_prev_sibling_params,
            prod_arity,
            node_kind,
            parent,
            first_child,
            next_sibling,
            prev_sibling,
            subtree_end,

            // HIR-facing classification
            hir_param_rows,
            hir_param_ranges,
            hir_type_arg_table_count,
            hir_type_arg_family_flag,
            hir_type_arg_rows,
            hir_type_arg_ranges,
            hir_generic_param_table_count,
            hir_generic_param_family_flag,
            hir_generic_param_rows,
            hir_generic_param_ranges,
            hir_path_table_count,
            hir_path_family_flag,
            hir_path_rows,
            hir_path_segment_table_count,
            hir_path_segment_family_flag,
            hir_path_segment_rows,
            hir_field_table_count,
            hir_field_family_flag,
            hir_field_rows,
            hir_variant_table_count,
            hir_variant_family_flag,
            hir_variant_rows,
            hir_variant_raw_to_row,
            hir_variant_compact_payload_start,
            hir_variant_compact_payload_count,
            hir_variant_payload_table_count,
            hir_variant_payload_family_flag,
            hir_variant_payload_rows,
            hir_match_arm_table_count,
            hir_match_arm_family_flag,
            hir_match_arm_raw_to_row,
            hir_match_arm_rows,
            hir_match_arm_ranges,
            hir_match_pattern_to_arm,
            hir_match_compact_payload_start,
            hir_match_compact_payload_count,
            hir_match_payload_table_count,
            hir_match_payload_family_flag,
            hir_match_payload_rows,
            hir_array_compact_element_start,
            hir_array_compact_element_count,
            hir_array_element_table_count,
            hir_array_element_family_flag,
            hir_array_element_rows,
            hir_canonical_string_rows,
            hir_method_table_count,
            hir_method_family_flag,
            hir_method_core_rows,
            hir_method_signature_rows,
            hir_predicate_table_count,
            hir_predicate_rows,
            hir_span_params,
            hir_type_fields_params,
            hir_item_fields_params,
            hir_param_fields_params,
            hir_method_fields_params,
            hir_expr_fields_params,
            hir_member_fields_params,
            hir_stmt_fields_params,
            hir_call_fields_params,
            hir_array_fields_params,
            hir_enum_match_fields_params,
            hir_struct_fields_params,
            hir_kind,
            hir_semantic_block_count,
            hir_semantic_prefix_scan_steps,
            hir_semantic_flag,
            hir_semantic_local_prefix,
            hir_semantic_block_prefix_a,
            hir_semantic_block_prefix_b,
            hir_node_dense_id,
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_semantic_parent_link_a,
            hir_semantic_parent_link_b,
            hir_semantic_parent_value_a,
            hir_semantic_parent_value_b,
            hir_semantic_depth_link_a,
            hir_semantic_depth_link_b,
            hir_semantic_depth_value_a,
            hir_semantic_depth_value_b,
            hir_semantic_child_index_link_a,
            hir_semantic_child_index_link_b,
            hir_semantic_child_index_rank_a,
            hir_semantic_child_index_rank_b,
            hir_semantic_count,
            hir_canonical_params,
            hir_canonical_count,
            hir_canonical_status,
            hir_canonical_anchor_owner,
            hir_canonical_prefix_before_raw,
            hir_canonical_dense_to_raw,
            hir_canonical_alias_to_dense,
            hir_canonical_raw_to_dense,
            hir_canonical_stmt_record,
            hir_canonical_expr_record,
            hir_core,
            hir_links,
            hir_payload,
            hir_canonical_semantic_facts,
            hir_canonical_semantic_dense_node,
            hir_canonical_scope_end,
            hir_canonical_nearest_loop,
            hir_canonical_nearest_block,
            hir_canonical_nearest_control,
            hir_canonical_nearest_fn,
            hir_canonical_context_stmt,
            hir_canonical_fn_return_type,
            hir_canonical_type_root_owner,
            hir_canonical_type_alias_target,
            hir_canonical_const_type,
            hir_canonical_const_value,
            hir_canonical_expr_parent_encoded,
            hir_canonical_expr_parent,
            hir_canonical_expr_root,
            hir_canonical_expr_root_scratch,
            hir_canonical_expr_forest_status,
            hir_call_arg_table_count,
            hir_call_arg_family_flag,
            hir_call_args,
            hir_call_arg_ranges,
            hir_param_table_count,
            hir_param_family_flag,
            hir_params,
            hir_token_pos,
            hir_token_end,
            hir_token_file_id,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_bound_path_owner_by_leaf,
            hir_path_root_owner,
            hir_path_segment_owner_a,
            hir_path_segment_owner_b,
            hir_path_segment_link_a,
            hir_path_segment_link_b,
            hir_path_segment_rank_a,
            hir_path_segment_rank_b,
            hir_path_segment_count,
            hir_type_path_leaf_link_a,
            hir_type_path_leaf_link_b,
            hir_type_path_leaf_value_a,
            hir_type_path_leaf_value_b,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_fn_signature_owner_link_a,
            hir_fn_signature_owner_link_b,
            hir_fn_signature_return_owner_a,
            hir_fn_signature_return_owner_b,
            hir_fn_signature_function_owner_a,
            hir_fn_signature_function_owner_b,
            hir_type_arg_owner_a,
            hir_type_arg_owner_b,
            hir_type_arg_link_a,
            hir_type_arg_link_b,
            hir_type_arg_rank_a,
            hir_type_arg_rank_b,
            hir_type_arg_previous,
            hir_type_root_owner,
            hir_type_alias_owner_link_a,
            hir_type_alias_owner_link_b,
            hir_type_alias_owner_value_a,
            hir_type_alias_owner_value_b,
            hir_item_kind,
            hir_item_name_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_path_node,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_param_record,
            hir_param_type_node,
            hir_method_owner_node,
            hir_method_impl_node,
            hir_method_name_token,
            hir_method_first_param_token,
            hir_method_receiver_mode,
            hir_method_visibility,
            hir_method_signature_flags,
            hir_method_impl_receiver_type_node,
            hir_param_owner_a,
            hir_param_link_a,
            hir_param_rank_a,
            hir_param_rank_b,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_payload_node,
            hir_variant_owner_a,
            hir_variant_owner_b,
            hir_variant_link_a,
            hir_variant_link_b,
            hir_variant_rank_a,
            hir_variant_rank_b,
            hir_variant_payload_owner_a,
            hir_variant_payload_owner_b,
            hir_variant_payload_link_a,
            hir_variant_payload_link_b,
            hir_variant_payload_rank_a,
            hir_variant_payload_rank_b,
            hir_list_rank_flag,
            hir_list_rank_local_prefix,
            hir_list_rank_block_sum,
            hir_list_rank_block_prefix_a,
            hir_list_rank_block_prefix_b,
            hir_list_rank_node,
            hir_list_rank_count,
            hir_list_rank_dispatch_args,
            hir_enum_rank_flag,
            hir_enum_rank_local_prefix,
            hir_enum_rank_block_sum,
            hir_enum_rank_block_prefix_a,
            hir_enum_rank_block_prefix_b,
            hir_enum_rank_node,
            hir_enum_rank_count,
            hir_enum_rank_dispatch_args,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_pattern_owner_arm,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_match_arm_owner_a,
            hir_match_arm_owner_b,
            hir_match_arm_link_a,
            hir_match_arm_link_b,
            hir_match_arm_rank_a,
            hir_match_arm_rank_b,
            hir_match_arm_previous,
            hir_match_payload_owner_a,
            hir_match_payload_owner_b,
            hir_match_payload_link_a,
            hir_match_payload_link_b,
            hir_match_payload_rank_a,
            hir_match_payload_rank_b,
            hir_match_rank_flag,
            hir_match_rank_local_prefix,
            hir_match_rank_block_sum,
            hir_match_rank_block_prefix_a,
            hir_match_rank_block_prefix_b,
            hir_match_rank_node,
            hir_match_rank_count,
            hir_match_rank_dispatch_args,
            hir_call_callee_node,
            hir_call_callee_path_node,
            hir_call_parent_by_callee,
            hir_call_context_stmt_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_call_arg_owner_a,
            hir_call_arg_owner_b,
            hir_call_arg_link_a,
            hir_call_arg_link_b,
            hir_call_arg_rank_a,
            hir_call_arg_rank_b,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_lit_context_stmt_node,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_array_element_owner_a,
            hir_array_element_owner_b,
            hir_array_element_link_a,
            hir_array_element_link_b,
            hir_array_element_rank_a,
            hir_array_element_rank_b,
            hir_array_element_previous,
            hir_expr_record,
            hir_expr_name_role,
            hir_expr_result_root_node,
            hir_expr_result_root_scratch_node,
            hir_binary_span_link_a,
            hir_binary_span_link_b,
            hir_binary_span_start_a,
            hir_binary_span_start_b,
            hir_expr_int_value,
            hir_expr_float_bits,
            hir_expr_string_start,
            hir_expr_string_len,
            hir_literal_values_params,
            hir_string_decode_params,
            hir_string_data_offset,
            hir_string_decoded_len,
            hir_string_data_words,
            hir_string_pool_len,
            hir_string_node,
            hir_string_count,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_stmt_record,
            hir_stmt_scope_end,
            hir_nearest_stmt_node,
            hir_nearest_block_node,
            hir_nearest_enclosing_control_node,
            hir_nearest_loop_node,
            hir_nearest_fn_node,
            hir_nearest_array_element_node,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_context_stmt_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
            hir_struct_lit_field_next,
            hir_struct_field_owner_a,
            hir_struct_field_owner_b,
            hir_struct_field_link_a,
            hir_struct_field_link_b,
            hir_struct_field_rank_a,
            hir_struct_field_rank_b,
            hir_struct_lit_field_owner_a,
            hir_struct_lit_field_owner_b,
            hir_struct_lit_field_link_a,
            hir_struct_lit_field_link_b,
            hir_struct_lit_field_rank_a,
            hir_struct_lit_field_rank_b,
            hir_struct_lit_field_previous,
            hir_stmt_context_link_a,
            hir_stmt_context_link_b,
            hir_contextual_stmt_value_a,
            hir_contextual_stmt_value_b,
            hir_nearest_stmt_value_a,
            hir_nearest_stmt_value_b,
            hir_nearest_block_value_a,
            hir_nearest_block_value_b,
            hir_nearest_enclosing_control_value_a,
            hir_nearest_enclosing_control_value_b,
            hir_nearest_loop_value_a,
            hir_nearest_loop_value_b,
            hir_nearest_fn_value_a,
            hir_nearest_fn_value_b,
            hir_nearest_array_element_value_a,
            hir_nearest_array_element_value_b,
            hir_struct_rank_flag,
            hir_struct_rank_local_prefix,
            hir_struct_rank_block_sum,
            hir_struct_rank_block_prefix_a,
            hir_struct_rank_block_prefix_b,
            hir_struct_rank_node,
            hir_struct_rank_count,
            hir_struct_rank_dispatch_args,
        }
    }
}
