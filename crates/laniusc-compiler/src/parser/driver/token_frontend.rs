use anyhow::Result;
use encase::ShaderType;

use super::{
    GpuParser,
    support::{buffer_fingerprint, stamp_timer, write_uniform},
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        operations::ComputeOperation,
        resource_registry::ResourceMap,
        timer::GpuTimer,
    },
    parser::{buffers::ParserBuffers, compiler_graph::token_frontend as graph_labels},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for token-to-parser-kind frontend passes.
pub(super) struct TokensToKindsParams {
    token_capacity: u32,
    match_tree_n_blocks: u32,
    match_tree_leaf_base: u32,
}

/// Cached bind groups for token-kind and identifier-kind frontend passes.
pub(in crate::parser::driver) struct ResidentTokenKindOperations {
    pub(super) input_fingerprint: u64,
    pub(super) tokens_to_kinds_params: LaniusBuffer<TokensToKindsParams>,
    pub(super) tokens_to_kinds: ComputeOperation,
    pub(super) tokens_to_identifier_kinds: ComputeOperation,
}

impl GpuParser {
    #[allow(clippy::too_many_arguments)]
    fn record_cached_operation<'a>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        cache_key: &str,
        operation: &'static str,
        pass: &crate::gpu::passes_core::PassData,
        build_resources: impl FnOnce() -> Result<ResourceMap<'a>>,
        elements: u32,
    ) -> Result<()> {
        let mut operations = self
            .token_compute_operations
            .lock()
            .expect("parser.token_compute_operations poisoned");
        if !operations.contains_key(cache_key) {
            let resources = build_resources()?;
            let capacity = (bufs.semantic_token_kinds.count as u32).max(elements);
            let operation = bufs.compiler_graph.direct_operation(
                &self.device,
                &resources,
                operation,
                pass,
                capacity,
            )?;
            operations.insert(cache_key.to_owned(), operation);
        }
        operations
            .get(cache_key)
            .expect("token operation was inserted")
            .record_elements(encoder, elements)
    }

    #[allow(clippy::too_many_arguments)]
    fn record_cached_token_operation<'a>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &'a ParserBuffers,
        token_buf: &'a wgpu::Buffer,
        token_count_buf: &'a wgpu::Buffer,
        cache_key: &str,
        operation: &'static str,
        pass: &crate::gpu::passes_core::PassData,
        extras: &[(&'static str, wgpu::BindingResource<'a>)],
        elements: u32,
    ) -> Result<()> {
        self.record_cached_operation(
            encoder,
            bufs,
            cache_key,
            operation,
            pass,
            || {
                let mut resources = bufs.compiler_graph.token_operation_resources(
                    operation,
                    token_buf,
                    token_count_buf,
                )?;
                for (name, binding) in extras {
                    resources.add(name, binding.clone());
                }
                Ok(resources)
            },
            elements,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_cached_graph_operation<'a>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &'a ParserBuffers,
        cache_key: &str,
        operation: &'static str,
        pass: &crate::gpu::passes_core::PassData,
        extras: &[(&'static str, wgpu::BindingResource<'a>)],
        elements: u32,
    ) -> Result<()> {
        self.record_cached_operation(
            encoder,
            bufs,
            cache_key,
            operation,
            pass,
            || {
                let mut resources = bufs.compiler_graph.operation_resources(operation)?;
                for (name, binding) in extras {
                    resources.add(name, binding.clone());
                }
                Ok(resources)
            },
            elements,
        )
    }

    /// Records token frontend passes without GPU timing labels.
    pub(in crate::parser::driver) fn record_tokens_to_kinds(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_tokens_to_kinds_timed(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
            &mut timer_ref,
        )
    }

    /// Records token frontend passes and emits timer stamps for each phase.
    pub(in crate::parser::driver) fn record_tokens_to_kinds_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let mut bind_guard = self
            .resident_token_kind_operations
            .lock()
            .expect("parser.resident_token_kind_operations poisoned");
        self.ensure_resident_token_kind_operations(
            &mut bind_guard,
            token_buf,
            token_count_buf,
            bufs,
        )?;
        let bind_groups = bind_guard
            .as_ref()
            .expect("resident token-kind parser bind groups allocated");
        self.record_impl_header_phase_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;
        self.record_token_delimiters_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;
        self.record_match_pattern_phase_timed(
            encoder,
            token_buf,
            token_count_buf,
            bufs,
            timer_ref,
        )?;
        self.record_where_clause_phase_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;
        bufs.clear_operations().record_token_feature_flags(encoder);
        write_uniform(
            &self.queue,
            &bind_groups.tokens_to_kinds_params,
            &TokensToKindsParams {
                token_capacity,
                match_tree_n_blocks: bufs.token_brace_match_block_min.count.max(1) as u32,
                match_tree_leaf_base: bufs.token_brace_match_min_tree_base,
            },
        );

        bind_groups
            .tokens_to_kinds
            .record_elements(encoder, token_capacity + 2)?;
        stamp_timer(timer_ref, encoder, "parser.tokens_to_kinds.symbols.done");

        self.record_type_path_context_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;

        bind_groups
            .tokens_to_identifier_kinds
            .record_elements(encoder, token_capacity + 2)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens_to_kinds.identifiers.done",
        );
        self.record_generic_shr_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;
        Ok(())
    }

    fn record_generic_shr_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_generic_shr_01_local",
            "parser.tokens.generic_shr.local",
            &self.passes.token_frontend.tokens_generic_shr_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_generic_shr_summary_scan(
            encoder,
            bufs,
            graph_labels::GENERIC_SHR_SCAN_UP,
            graph_labels::GENERIC_SHR_SCAN_DOWN,
        )?;

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_generic_shr_03_apply",
            "parser.tokens.generic_shr.apply",
            &self.passes.token_frontend.tokens_generic_shr_03_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_input_capacity,
        )?;

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_generic_shr_04_close_kinds",
            "parser.tokens.generic_shr.close_kinds",
            &self.passes.token_frontend.tokens_generic_shr_04_close_kinds,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_input_capacity,
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.generic_shr.done");
        Ok(())
    }

    fn record_raw_clamped_angle_depth(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_generic_shr_00_raw_local",
            "parser.tokens.generic_shr.raw_local",
            &self.passes.token_frontend.tokens_generic_shr_00_raw_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_generic_shr_summary_scan(
            encoder,
            bufs,
            graph_labels::GENERIC_SHR_RAW_SCAN_UP,
            graph_labels::GENERIC_SHR_RAW_SCAN_DOWN,
        )?;

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_generic_shr_00_raw_apply",
            "parser.tokens.generic_shr.raw_apply",
            &self.passes.token_frontend.tokens_generic_shr_00_raw_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_input_capacity,
        )?;
        Ok(())
    }

    fn record_generic_shr_summary_scan(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        for (index, step) in bufs.token_block_scan_plan.up.iter().enumerate() {
            let invocation = format!("{up_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                up_label,
                &self.passes.token_frontend.tokens_generic_shr_02_scan_up,
                &[("gGenericScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        for (index, step) in bufs.token_block_scan_plan.down.iter().enumerate() {
            let invocation = format!("{down_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                down_label,
                &self.passes.token_frontend.tokens_generic_shr_02_scan_down,
                &[("gGenericScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_type_path_context_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_type_path_context_01_local",
            "parser.tokens.type_path_context.local",
            &self.passes.token_frontend.tokens_type_path_context_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.type_path_context.local.done",
        );

        self.record_statement_event_scan(
            encoder,
            bufs,
            graph_labels::TYPE_PATH_SCAN_UP,
            graph_labels::TYPE_PATH_SCAN_DOWN,
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.type_path_context.scan.done",
        );

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_type_path_context_02_apply",
            "parser.tokens.type_path_context.apply",
            &self.passes.token_frontend.tokens_type_path_context_02_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.type_path_context.apply.done",
        );
        Ok(())
    }

    fn record_impl_header_phase_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        stamp_timer(
            timer_ref,
            encoder,
            "compile.source_pack.parser.submission.begin",
        );
        bufs.clear_operations()
            .record_token_impl_header_kind(encoder);

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_impl_header_01_local",
            "parser.tokens.impl_header.local",
            &self.passes.token_frontend.tokens_impl_header_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.impl_header.local.done");

        self.record_statement_event_scan(
            encoder,
            bufs,
            graph_labels::IMPL_HEADER_SCAN_UP,
            graph_labels::IMPL_HEADER_SCAN_DOWN,
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.impl_header.scan.done");

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_impl_header_02_apply",
            "parser.tokens.impl_header.apply",
            &self.passes.token_frontend.tokens_impl_header_02_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.impl_header.apply.done");
        Ok(())
    }

    fn record_where_clause_phase_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_where_clause_01_local",
            "parser.tokens.where_clause.local",
            &self.passes.token_frontend.tokens_where_clause_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.where_clause.local.done");

        self.record_statement_event_scan(
            encoder,
            bufs,
            graph_labels::WHERE_CLAUSE_SCAN_UP,
            graph_labels::WHERE_CLAUSE_SCAN_DOWN,
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.where_clause.scan.done");

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_where_clause_02_apply",
            "parser.tokens.where_clause.apply",
            &self.passes.token_frontend.tokens_where_clause_02_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.where_clause.apply.done");
        Ok(())
    }

    fn record_match_pattern_phase_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_match_pattern_01_local",
            "parser.tokens.match_pattern.local",
            &self.passes.token_frontend.tokens_match_pattern_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.match_pattern.local.done");

        self.record_statement_event_scan(
            encoder,
            bufs,
            graph_labels::MATCH_PATTERN_SCAN_UP,
            graph_labels::MATCH_PATTERN_SCAN_DOWN,
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.match_pattern.scan.done");

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_match_pattern_02_apply",
            "parser.tokens.match_pattern.apply",
            &self.passes.token_frontend.tokens_match_pattern_02_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.match_pattern.apply.done");
        Ok(())
    }

    fn record_token_delimiters_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_delimiters_01_local",
            "parser.tokens.delimiters.local",
            &self.passes.token_frontend.token_delimiters_01,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.delimiters.local.done");

        self.record_token_delimiter_hierarchy(
            encoder,
            bufs,
            graph_labels::DELIMITER_DEPTH_SCAN_UP,
            graph_labels::DELIMITER_DEPTH_SCAN_DOWN,
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.depth_scan.done",
        );
        self.record_raw_clamped_angle_depth(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.clamped_angle.done",
        );
        self.record_token_delimiter_owner_local(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_header.local.done",
        );
        self.record_token_delimiter_hierarchy(
            encoder,
            bufs,
            graph_labels::DELIMITER_OWNER_HEADER_SCAN_UP,
            graph_labels::DELIMITER_OWNER_HEADER_SCAN_DOWN,
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_header.scan.done",
        );
        self.record_token_delimiter_owner_apply(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_apply.done",
        );
        self.record_token_delimiter_hierarchy(
            encoder,
            bufs,
            graph_labels::DELIMITER_OWNER_SCAN_UP,
            graph_labels::DELIMITER_OWNER_SCAN_DOWN,
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_scan.done",
        );

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_brace_context",
            "parser.tokens.brace_context",
            &self.passes.token_frontend.tokens_brace_context,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.brace_context.done");

        self.record_statement_phase_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;

        self.record_token_delimiter_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.delimiter_match.done");

        Ok(())
    }

    fn record_statement_phase_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_statement_phase_01_local",
            "parser.tokens.statement_phase.local",
            &self.passes.token_frontend.tokens_statement_phase_01_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.local.done",
        );

        self.record_statement_event_scan(
            encoder,
            bufs,
            graph_labels::STATEMENT_PHASE_SCAN_UP,
            graph_labels::STATEMENT_PHASE_SCAN_DOWN,
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.scan.done",
        );

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_statement_phase_02_apply",
            "parser.tokens.statement_phase.apply",
            &self.passes.token_frontend.tokens_statement_phase_02_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.apply.done",
        );
        Ok(())
    }

    fn record_token_delimiter_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_delimiter_match_01_depth_blocks",
            "parser.tokens.delimiter_match.depth_blocks",
            &self
                .passes
                .token_frontend
                .tokens_delimiter_match_01_depth_blocks,
            &[("gParams", bufs.token_brace_match_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_delimiter_match_min_tree_build(encoder, bufs)?;
        bufs.clear_operations()
            .record_token_braced_rhs_statement_kind(encoder);
        self.record_token_brace_pairing(encoder, token_buf, token_count_buf, bufs)?;
        self.record_token_bracket_pairing(encoder, token_buf, token_count_buf, bufs)
    }

    fn record_token_bracket_pairing(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_bracket_match_03_pair_pse",
            "parser.tokens.bracket_match.pair_pse",
            &self.passes.token_frontend.tokens_bracket_match_03_pair_pse,
            &[("gParams", bufs.token_brace_match_params.as_entire_binding())],
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_brace_pairing(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_brace_match_03_pair_pse",
            "parser.tokens.brace_match.pair_pse",
            &self.passes.token_frontend.tokens_brace_match_03_pair_pse,
            &[("gParams", bufs.token_brace_match_params.as_entire_binding())],
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_delimiter_match_min_tree_build(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        for (index, step) in bufs.token_brace_match_min_tree_steps.iter().enumerate() {
            let invocation = format!("parser_tokens_delimiter_match_02_build_min_tree.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                "parser.tokens.delimiter_match.build_min_tree",
                &self
                    .passes
                    .token_frontend
                    .tokens_delimiter_match_02_build_min_tree,
                &[("gMinTree", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_delimiter_hierarchy(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        for (index, step) in bufs.token_block_scan_plan.up.iter().enumerate() {
            let invocation = format!("{up_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                up_label,
                &self.passes.token_frontend.token_delimiters_02_scan_up,
                &[("gDelimiterScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        for (index, step) in bufs.token_block_scan_plan.down.iter().enumerate() {
            let invocation = format!("{down_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                down_label,
                &self.passes.token_frontend.token_delimiters_02_scan_down,
                &[("gDelimiterScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_statement_event_scan(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        for (index, step) in bufs.token_block_scan_plan.up.iter().enumerate() {
            let invocation = format!("{up_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                up_label,
                &self.passes.token_frontend.token_statement_event_scan_up,
                &[("gContextScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        for (index, step) in bufs.token_block_scan_plan.down.iter().enumerate() {
            let invocation = format!("{down_label}.{index}");
            self.record_cached_graph_operation(
                encoder,
                bufs,
                &invocation,
                down_label,
                &self.passes.token_frontend.token_statement_event_scan_down,
                &[("gContextScan", step.params.as_entire_binding())],
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_delimiter_owner_local(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_delimiters_03_owner_local",
            "parser.tokens.delimiters.owner_local",
            &self.passes.token_frontend.token_delimiters_03_owner_local,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        Ok(())
    }

    fn record_token_delimiter_owner_apply(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        self.record_cached_token_operation(
            encoder,
            bufs,
            token_buf,
            token_count_buf,
            "parser_tokens_delimiters_04_owner_apply",
            "parser.tokens.delimiters.owner_apply",
            &self.passes.token_frontend.token_delimiters_04_owner_apply,
            &[("gParams", bufs.token_delimiter_params.as_entire_binding())],
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        Ok(())
    }

    fn ensure_resident_token_kind_operations(
        &self,
        slot: &mut Option<ResidentTokenKindOperations>,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            &bufs.semantic_token_kinds,
            &bufs.token_depth_paren_inblock,
            &bufs.token_block_prefix_paren,
            &bufs.token_depth_brace_inblock,
            &bufs.token_block_prefix_brace,
            &bufs.token_depth_bracket_inblock,
            &bufs.token_block_prefix_bracket,
            &bufs.token_depth_angle_inblock,
            &bufs.token_block_prefix_angle,
            &bufs.token_paren_match_depth,
            &bufs.token_paren_match_block_min,
            &bufs.token_paren_match_min_tree,
            &bufs.token_angle_match_depth,
            &bufs.token_angle_match_block_min,
            &bufs.token_angle_match_min_tree,
            &bufs.token_brace_semantic_kind,
            &bufs.token_braced_rhs_statement_kind,
            &bufs.token_bracket_semantic_kind,
            &bufs.token_statement_context_kind,
            &bufs.token_impl_header_kind,
            &bufs.token_impl_context_event,
            &bufs.token_type_path_context_kind,
            &bufs.token_where_context_event,
            &bufs.token_match_pattern_context_event,
            &bufs.token_brace_match_depth,
            &bufs.token_brace_match_block_min,
            &bufs.token_brace_match_min_tree,
            &bufs.token_feature_flags,
            &bufs.token_count,
        ]);
        if slot
            .as_ref()
            .is_none_or(|cached| cached.input_fingerprint != fingerprint)
        {
            // Every token-frontend pass shares the generic bind-group cache.
            // A new lexer allocation changes token_buf/token_count_buf while
            // parser-owned resident buffers can remain reusable, so invalidate
            // all token-pass bindings before recreating the specialized pair.
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
            self.token_compute_operations
                .lock()
                .expect("parser.token_compute_operations poisoned")
                .clear();
            *slot = Some(self.create_resident_token_kind_operations(
                fingerprint,
                token_buf,
                token_count_buf,
                bufs,
            )?);
        }
        Ok(())
    }

    fn create_resident_token_kind_operations(
        &self,
        input_fingerprint: u64,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<ResidentTokenKindOperations> {
        let tokens_to_kinds_params = uniform_from_val(
            &self.device,
            "parser.tokens_to_kinds.params",
            &TokensToKindsParams {
                token_capacity: 0,
                match_tree_n_blocks: 1,
                match_tree_leaf_base: 1,
            },
        );

        let mut tokens_to_kinds_resources = bufs.compiler_graph.token_operation_resources(
            "parser.tokens_to_kinds.pass",
            token_buf,
            token_count_buf,
        )?;
        tokens_to_kinds_resources.buffer("gParams", &tokens_to_kinds_params);
        let tokens_to_kinds = bufs.compiler_graph.direct_operation(
            &self.device,
            &tokens_to_kinds_resources,
            "parser.tokens_to_kinds.pass",
            &self.passes.token_frontend.tokens_to_kinds,
            bufs.semantic_token_kinds.count as u32,
        )?;
        let mut tokens_to_identifier_kinds_resources =
            bufs.compiler_graph.token_operation_resources(
                "parser.tokens_to_identifier_kinds.pass",
                token_buf,
                token_count_buf,
            )?;
        tokens_to_identifier_kinds_resources.buffer("gParams", &tokens_to_kinds_params);
        let tokens_to_identifier_kinds = bufs.compiler_graph.direct_operation(
            &self.device,
            &tokens_to_identifier_kinds_resources,
            "parser.tokens_to_identifier_kinds.pass",
            &self.passes.token_frontend.tokens_to_identifier_kinds,
            bufs.semantic_token_kinds.count as u32,
        )?;

        Ok(ResidentTokenKindOperations {
            input_fingerprint,
            tokens_to_kinds_params,
            tokens_to_kinds,
            tokens_to_identifier_kinds,
        })
    }
}
