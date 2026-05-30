use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use super::{
    GpuParser,
    record_parser_compute,
    support::{buffer_fingerprint, stamp_timer, write_uniform},
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        passes_core::bind_group,
        timer::GpuTimer,
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(super) struct TokensToKindsParams {
    token_capacity: u32,
}

pub(in crate::parser::driver) struct ResidentTokenKindBindGroups {
    pub(super) input_fingerprint: u64,
    pub(super) tokens_to_kinds_params: LaniusBuffer<TokensToKindsParams>,
    pub(super) tokens_to_kinds: wgpu::BindGroup,
    pub(super) tokens_to_identifier_kinds: wgpu::BindGroup,
}

impl GpuParser {
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

    pub(in crate::parser::driver) fn record_tokens_to_kinds_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let pass = &self.tokens_to_kinds;
        let identifier_pass = &self.tokens_to_identifier_kinds;
        let mut bind_guard = self
            .resident_token_kind_bind_groups
            .lock()
            .expect("parser.resident_token_kind_bind_groups poisoned");
        self.ensure_resident_token_kind_bind_groups(
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
        encoder.clear_buffer(&bufs.token_feature_flags.buffer, 0, Some(4));
        write_uniform(
            &self.queue,
            &bind_groups.tokens_to_kinds_params,
            &TokensToKindsParams { token_capacity },
        );

        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("parser.tokens_to_kinds.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bind_groups.tokens_to_kinds), &[]);
            compute.dispatch_workgroups((token_capacity + 2).div_ceil(256).max(1), 1, 1);
        }
        stamp_timer(timer_ref, encoder, "parser.tokens_to_kinds.symbols.done");

        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("parser.tokens_to_identifier_kinds.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&identifier_pass.pipeline);
            compute.set_bind_group(0, Some(&bind_groups.tokens_to_identifier_kinds), &[]);
            compute.dispatch_workgroups((token_capacity + 2).div_ceil(256).max(1), 1, 1);
        }
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens_to_kinds.identifiers.done",
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
        encoder.clear_buffer(&bufs.token_impl_header_kind.buffer, 0, None);

        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_impl_header_01_local"),
            &self.tokens_impl_header_01_local.bind_group_layouts[0],
            &self.tokens_impl_header_01_local.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_impl_header_01_local,
            &local_bind_group,
            "parser.tokens.impl_header.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.impl_header.local.done");

        self.record_token_delimiter_scan_steps(encoder, bufs, "parser.tokens.impl_header.scan")?;
        stamp_timer(timer_ref, encoder, "parser.tokens.impl_header.scan.done");

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "token_impl_header_kind".into(),
                bufs.token_impl_header_kind.as_entire_binding(),
            ),
            (
                "token_impl_context_event".into(),
                bufs.token_impl_context_event.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_impl_header_02_apply"),
            &self.tokens_impl_header_02_apply.bind_group_layouts[0],
            &self.tokens_impl_header_02_apply.reflection,
            0,
            &apply_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_impl_header_02_apply,
            &apply_bind_group,
            "parser.tokens.impl_header.apply",
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
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_where_clause_01_local"),
            &self.tokens_where_clause_01_local.bind_group_layouts[0],
            &self.tokens_where_clause_01_local.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_where_clause_01_local,
            &local_bind_group,
            "parser.tokens.where_clause.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.where_clause.local.done");

        self.record_token_delimiter_scan_steps(encoder, bufs, "parser.tokens.where_clause.scan")?;
        stamp_timer(timer_ref, encoder, "parser.tokens.where_clause.scan.done");

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "token_where_context_event".into(),
                bufs.token_where_context_event.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_where_clause_02_apply"),
            &self.tokens_where_clause_02_apply.bind_group_layouts[0],
            &self.tokens_where_clause_02_apply.reflection,
            0,
            &apply_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_where_clause_02_apply,
            &apply_bind_group,
            "parser.tokens.where_clause.apply",
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
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                bufs.token_block_prefix_paren.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                bufs.token_block_prefix_angle.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_match_pattern_01_local"),
            &self.tokens_match_pattern_01_local.bind_group_layouts[0],
            &self.tokens_match_pattern_01_local.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_match_pattern_01_local,
            &local_bind_group,
            "parser.tokens.match_pattern.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.match_pattern.local.done");

        self.record_token_delimiter_scan_steps(encoder, bufs, "parser.tokens.match_pattern.scan")?;
        stamp_timer(timer_ref, encoder, "parser.tokens.match_pattern.scan.done");

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                bufs.token_block_prefix_paren.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                bufs.token_block_prefix_angle.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "token_match_pattern_context_event".into(),
                bufs.token_match_pattern_context_event.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_match_pattern_02_apply"),
            &self.tokens_match_pattern_02_apply.bind_group_layouts[0],
            &self.tokens_match_pattern_02_apply.reflection,
            0,
            &apply_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_match_pattern_02_apply,
            &apply_bind_group,
            "parser.tokens.match_pattern.apply",
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
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_sum_brace".into(),
                bufs.token_block_sum_brace.as_entire_binding(),
            ),
            (
                "block_sum_bracket".into(),
                bufs.token_block_sum_bracket.as_entire_binding(),
            ),
            (
                "block_sum_paren".into(),
                bufs.token_block_sum_paren.as_entire_binding(),
            ),
            (
                "block_sum_angle".into(),
                bufs.token_block_sum_angle.as_entire_binding(),
            ),
            (
                "top_brace_owner_block".into(),
                bufs.token_top_brace_owner_block.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_delimiters_01_local"),
            &self.token_delimiters_01.bind_group_layouts[0],
            &self.token_delimiters_01.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.token_delimiters_01,
            &local_bind_group,
            "parser.tokens.delimiters.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.delimiters.local.done");

        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.delimiters.scan.depth",
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.depth_scan.done",
        );
        self.record_token_delimiter_owner_local(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_header.local.done",
        );
        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.delimiters.scan.owner_header",
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
        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.delimiters.scan.owner",
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_scan.done",
        );

        let context_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "top_brace_owner_block_prefix".into(),
                bufs.token_top_brace_owner_block_prefix.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
        ]);
        let context_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_context"),
            &self.tokens_brace_context.bind_group_layouts[0],
            &self.tokens_brace_context.reflection,
            0,
            &context_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_context,
            &context_bind_group,
            "parser.tokens.brace_context",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.brace_context.done");

        self.record_statement_phase_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;

        self.record_token_bracket_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.bracket_match.done");

        self.record_token_brace_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.brace_match.done");

        self.record_token_paren_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.paren_match.done");

        self.record_token_angle_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.angle_match.done");

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
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_statement_phase_01_local"),
            &self.tokens_statement_phase_01_local.bind_group_layouts[0],
            &self.tokens_statement_phase_01_local.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_statement_phase_01_local,
            &local_bind_group,
            "parser.tokens.statement_phase.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.local.done",
        );

        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.statement_phase.scan",
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.scan.done",
        );

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_statement_phase_02_apply"),
            &self.tokens_statement_phase_02_apply.bind_group_layouts[0],
            &self.tokens_statement_phase_02_apply.reflection,
            0,
            &apply_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_statement_phase_02_apply,
            &apply_bind_group,
            "parser.tokens.statement_phase.apply",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.statement_phase.apply.done",
        );
        Ok(())
    }

    fn record_token_bracket_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
            (
                "bracket_semantic_kind".into(),
                bufs.token_bracket_semantic_kind.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_bracket_match_01_depth_blocks"),
            &self.tokens_bracket_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_bracket_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_bracket_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.bracket_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_brace_match_min_tree_build(encoder, bufs)?;

        let pair_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "bracket_semantic_kind".into(),
                bufs.token_bracket_semantic_kind.as_entire_binding(),
            ),
        ]);
        let pair_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_bracket_match_03_pair_pse"),
            &self.tokens_bracket_match_03_pair_pse.bind_group_layouts[0],
            &self.tokens_bracket_match_03_pair_pse.reflection,
            0,
            &pair_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_bracket_match_03_pair_pse,
            &pair_bind_group,
            "parser.tokens.bracket_match.pair_pse",
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_brace_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_match_01_depth_blocks"),
            &self.tokens_brace_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_brace_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.brace_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_brace_match_min_tree_build(encoder, bufs)?;

        let pair_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
        ]);
        let pair_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_match_03_pair_pse"),
            &self.tokens_brace_match_03_pair_pse.bind_group_layouts[0],
            &self.tokens_brace_match_03_pair_pse.reflection,
            0,
            &pair_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_match_03_pair_pse,
            &pair_bind_group,
            "parser.tokens.brace_match.pair_pse",
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_angle_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                bufs.token_block_prefix_angle.as_entire_binding(),
            ),
            (
                "angle_match_depth".into(),
                bufs.token_angle_match_depth.as_entire_binding(),
            ),
            (
                "angle_match_block_min".into(),
                bufs.token_angle_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_angle_match_01_depth_blocks"),
            &self.tokens_angle_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_angle_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_angle_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.angle_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_angle_match_min_tree_build(encoder, bufs)?;

        Ok(())
    }

    fn record_token_paren_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                bufs.token_block_prefix_paren.as_entire_binding(),
            ),
            (
                "paren_match_depth".into(),
                bufs.token_paren_match_depth.as_entire_binding(),
            ),
            (
                "paren_match_block_min".into(),
                bufs.token_paren_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_paren_match_01_depth_blocks"),
            &self.tokens_paren_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_paren_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_paren_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.paren_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_paren_match_min_tree_build(encoder, bufs)?;

        Ok(())
    }

    fn record_token_brace_match_min_tree_build(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        for step in &bufs.token_brace_match_min_tree_steps {
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    bufs.token_brace_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_brace_match_min_tree.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_brace_match_02_build_min_tree"),
                &self.tokens_brace_match_02_build_min_tree.bind_group_layouts[0],
                &self.tokens_brace_match_02_build_min_tree.reflection,
                0,
                &resources,
            )?;
            record_parser_compute(
                encoder,
                &self.tokens_brace_match_02_build_min_tree,
                &bind_group,
                "parser.tokens.brace_match.build_min_tree",
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_paren_match_min_tree_build(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        for step in &bufs.token_brace_match_min_tree_steps {
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    bufs.token_paren_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_paren_match_min_tree.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_paren_match_02_build_min_tree"),
                &self.tokens_brace_match_02_build_min_tree.bind_group_layouts[0],
                &self.tokens_brace_match_02_build_min_tree.reflection,
                0,
                &resources,
            )?;
            record_parser_compute(
                encoder,
                &self.tokens_brace_match_02_build_min_tree,
                &bind_group,
                "parser.tokens.paren_match.build_min_tree",
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_angle_match_min_tree_build(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        for step in &bufs.token_brace_match_min_tree_steps {
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    bufs.token_angle_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_angle_match_min_tree.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_angle_match_02_build_min_tree"),
                &self.tokens_brace_match_02_build_min_tree.bind_group_layouts[0],
                &self.tokens_brace_match_02_build_min_tree.reflection,
                0,
                &resources,
            )?;
            record_parser_compute(
                encoder,
                &self.tokens_brace_match_02_build_min_tree,
                &bind_group,
                "parser.tokens.angle_match.build_min_tree",
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_delimiter_scan_steps(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        label: &'static str,
    ) -> Result<()> {
        for step in &bufs.token_delimiter_scan_steps {
            let prefix_brace_in = if step.read_from_a {
                &bufs.token_prefix_brace_a
            } else {
                &bufs.token_prefix_brace_b
            };
            let prefix_brace_out = if step.write_to_a {
                &bufs.token_prefix_brace_a
            } else {
                &bufs.token_prefix_brace_b
            };
            let prefix_bracket_in = if step.read_from_a {
                &bufs.token_prefix_bracket_a
            } else {
                &bufs.token_prefix_bracket_b
            };
            let prefix_bracket_out = if step.write_to_a {
                &bufs.token_prefix_bracket_a
            } else {
                &bufs.token_prefix_bracket_b
            };
            let prefix_paren_in = if step.read_from_a {
                &bufs.token_prefix_paren_a
            } else {
                &bufs.token_prefix_paren_b
            };
            let prefix_paren_out = if step.write_to_a {
                &bufs.token_prefix_paren_a
            } else {
                &bufs.token_prefix_paren_b
            };
            let prefix_angle_in = if step.read_from_a {
                &bufs.token_prefix_angle_a
            } else {
                &bufs.token_prefix_angle_b
            };
            let prefix_angle_out = if step.write_to_a {
                &bufs.token_prefix_angle_a
            } else {
                &bufs.token_prefix_angle_b
            };
            let top_owner_prefix_in = if step.read_from_a {
                &bufs.token_top_brace_owner_prefix_a
            } else {
                &bufs.token_top_brace_owner_prefix_b
            };
            let top_owner_prefix_out = if step.write_to_a {
                &bufs.token_top_brace_owner_prefix_a
            } else {
                &bufs.token_top_brace_owner_prefix_b
            };
            let statement_event_prefix_in = if step.read_from_a {
                &bufs.token_statement_event_prefix_a
            } else {
                &bufs.token_statement_event_prefix_b
            };
            let statement_event_prefix_out = if step.write_to_a {
                &bufs.token_statement_event_prefix_a
            } else {
                &bufs.token_statement_event_prefix_b
            };
            let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "block_sum_brace".into(),
                    bufs.token_block_sum_brace.as_entire_binding(),
                ),
                (
                    "block_sum_bracket".into(),
                    bufs.token_block_sum_bracket.as_entire_binding(),
                ),
                (
                    "block_sum_paren".into(),
                    bufs.token_block_sum_paren.as_entire_binding(),
                ),
                (
                    "block_sum_angle".into(),
                    bufs.token_block_sum_angle.as_entire_binding(),
                ),
                (
                    "prefix_brace_in".into(),
                    prefix_brace_in.as_entire_binding(),
                ),
                (
                    "prefix_bracket_in".into(),
                    prefix_bracket_in.as_entire_binding(),
                ),
                (
                    "prefix_paren_in".into(),
                    prefix_paren_in.as_entire_binding(),
                ),
                (
                    "prefix_angle_in".into(),
                    prefix_angle_in.as_entire_binding(),
                ),
                (
                    "top_brace_owner_block".into(),
                    bufs.token_top_brace_owner_block.as_entire_binding(),
                ),
                (
                    "top_brace_owner_prefix_in".into(),
                    top_owner_prefix_in.as_entire_binding(),
                ),
                (
                    "statement_event_block".into(),
                    bufs.token_statement_event_block.as_entire_binding(),
                ),
                (
                    "statement_event_prefix_in".into(),
                    statement_event_prefix_in.as_entire_binding(),
                ),
                (
                    "prefix_brace_out".into(),
                    prefix_brace_out.as_entire_binding(),
                ),
                (
                    "prefix_bracket_out".into(),
                    prefix_bracket_out.as_entire_binding(),
                ),
                (
                    "prefix_paren_out".into(),
                    prefix_paren_out.as_entire_binding(),
                ),
                (
                    "prefix_angle_out".into(),
                    prefix_angle_out.as_entire_binding(),
                ),
                (
                    "block_prefix_brace".into(),
                    bufs.token_block_prefix_brace.as_entire_binding(),
                ),
                (
                    "block_prefix_bracket".into(),
                    bufs.token_block_prefix_bracket.as_entire_binding(),
                ),
                (
                    "block_prefix_paren".into(),
                    bufs.token_block_prefix_paren.as_entire_binding(),
                ),
                (
                    "block_prefix_angle".into(),
                    bufs.token_block_prefix_angle.as_entire_binding(),
                ),
                (
                    "top_brace_owner_prefix_out".into(),
                    top_owner_prefix_out.as_entire_binding(),
                ),
                (
                    "top_brace_owner_block_prefix".into(),
                    bufs.token_top_brace_owner_block_prefix.as_entire_binding(),
                ),
                (
                    "statement_event_prefix_out".into(),
                    statement_event_prefix_out.as_entire_binding(),
                ),
                (
                    "statement_event_block_prefix".into(),
                    bufs.token_statement_event_block_prefix.as_entire_binding(),
                ),
            ]);
            let scan_bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_delimiters_02_scan"),
                &self.token_delimiters_02.bind_group_layouts[0],
                &self.token_delimiters_02.reflection,
                0,
                &scan_resources,
            )?;
            record_parser_compute(
                encoder,
                &self.token_delimiters_02,
                &scan_bind_group,
                label,
                bufs.token_delimiter_n_blocks,
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
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                bufs.token_block_prefix_paren.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                bufs.token_block_prefix_angle.as_entire_binding(),
            ),
            (
                "token_impl_context_event".into(),
                bufs.token_impl_context_event.as_entire_binding(),
            ),
            (
                "top_brace_owner_block".into(),
                bufs.token_top_brace_owner_block.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_delimiters_03_owner_local"),
            &self.token_delimiters_03_owner_local.bind_group_layouts[0],
            &self.token_delimiters_03_owner_local.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.token_delimiters_03_owner_local,
            &bind_group,
            "parser.tokens.delimiters.owner_local",
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
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                bufs.token_depth_paren_inblock.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                bufs.token_depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                bufs.token_block_prefix_paren.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                bufs.token_block_prefix_angle.as_entire_binding(),
            ),
            (
                "token_impl_context_event".into(),
                bufs.token_impl_context_event.as_entire_binding(),
            ),
            (
                "top_brace_owner_block_prefix".into(),
                bufs.token_top_brace_owner_block_prefix.as_entire_binding(),
            ),
            (
                "top_brace_owner_block".into(),
                bufs.token_top_brace_owner_block.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_delimiters_04_owner_apply"),
            &self.token_delimiters_04_owner_apply.bind_group_layouts[0],
            &self.token_delimiters_04_owner_apply.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.token_delimiters_04_owner_apply,
            &bind_group,
            "parser.tokens.delimiters.owner_apply",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        Ok(())
    }

    fn ensure_resident_token_kind_bind_groups(
        &self,
        slot: &mut Option<ResidentTokenKindBindGroups>,
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
            &bufs.token_bracket_semantic_kind,
            &bufs.token_statement_context_kind,
            &bufs.token_impl_header_kind,
            &bufs.token_impl_context_event,
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
            *slot = Some(self.create_resident_token_kind_bind_groups(
                fingerprint,
                token_buf,
                token_count_buf,
                bufs,
            )?);
        }
        Ok(())
    }

    fn create_resident_token_kind_bind_groups(
        &self,
        input_fingerprint: u64,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<ResidentTokenKindBindGroups> {
        let tokens_to_kinds_params = uniform_from_val(
            &self.device,
            "parser.tokens_to_kinds.params",
            &TokensToKindsParams { token_capacity: 0 },
        );

        let tokens_to_kinds_resources: HashMap<String, wgpu::BindingResource<'_>> =
            HashMap::from([
                ("gParams".into(), tokens_to_kinds_params.as_entire_binding()),
                ("token_words".into(), token_buf.as_entire_binding()),
                (
                    "lexer_token_count".into(),
                    token_count_buf.as_entire_binding(),
                ),
                (
                    "depth_paren_inblock".into(),
                    bufs.token_depth_paren_inblock.as_entire_binding(),
                ),
                (
                    "block_prefix_paren".into(),
                    bufs.token_block_prefix_paren.as_entire_binding(),
                ),
                (
                    "depth_brace_inblock".into(),
                    bufs.token_depth_brace_inblock.as_entire_binding(),
                ),
                (
                    "block_prefix_brace".into(),
                    bufs.token_block_prefix_brace.as_entire_binding(),
                ),
                (
                    "depth_bracket_inblock".into(),
                    bufs.token_depth_bracket_inblock.as_entire_binding(),
                ),
                (
                    "block_prefix_bracket".into(),
                    bufs.token_block_prefix_bracket.as_entire_binding(),
                ),
                (
                    "depth_angle_inblock".into(),
                    bufs.token_depth_angle_inblock.as_entire_binding(),
                ),
                (
                    "block_prefix_angle".into(),
                    bufs.token_block_prefix_angle.as_entire_binding(),
                ),
                (
                    "brace_match_depth".into(),
                    bufs.token_brace_match_depth.as_entire_binding(),
                ),
                (
                    "brace_match_block_min".into(),
                    bufs.token_brace_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_brace_match_min_tree.as_entire_binding(),
                ),
                (
                    "paren_match_depth".into(),
                    bufs.token_paren_match_depth.as_entire_binding(),
                ),
                (
                    "paren_match_block_min".into(),
                    bufs.token_paren_match_block_min.as_entire_binding(),
                ),
                (
                    "paren_match_min_tree".into(),
                    bufs.token_paren_match_min_tree.as_entire_binding(),
                ),
                (
                    "angle_match_depth".into(),
                    bufs.token_angle_match_depth.as_entire_binding(),
                ),
                (
                    "angle_match_block_min".into(),
                    bufs.token_angle_match_block_min.as_entire_binding(),
                ),
                (
                    "angle_match_min_tree".into(),
                    bufs.token_angle_match_min_tree.as_entire_binding(),
                ),
                (
                    "semantic_token_kinds".into(),
                    bufs.semantic_token_kinds.as_entire_binding(),
                ),
                (
                    "brace_semantic_kind".into(),
                    bufs.token_brace_semantic_kind.as_entire_binding(),
                ),
                (
                    "bracket_semantic_kind".into(),
                    bufs.token_bracket_semantic_kind.as_entire_binding(),
                ),
                (
                    "statement_context_kind".into(),
                    bufs.token_statement_context_kind.as_entire_binding(),
                ),
                (
                    "token_impl_header_kind".into(),
                    bufs.token_impl_header_kind.as_entire_binding(),
                ),
                (
                    "token_impl_context_event".into(),
                    bufs.token_impl_context_event.as_entire_binding(),
                ),
                (
                    "token_where_context_event".into(),
                    bufs.token_where_context_event.as_entire_binding(),
                ),
                (
                    "token_match_pattern_context_event".into(),
                    bufs.token_match_pattern_context_event.as_entire_binding(),
                ),
                (
                    "token_feature_flags".into(),
                    bufs.token_feature_flags.as_entire_binding(),
                ),
                (
                    "parser_token_count".into(),
                    bufs.token_count.as_entire_binding(),
                ),
            ]);
        let tokens_to_kinds = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_to_kinds"),
            &self.tokens_to_kinds.bind_group_layouts[0],
            &self.tokens_to_kinds.reflection,
            0,
            &tokens_to_kinds_resources,
        )?;
        let tokens_to_identifier_kinds_resources: HashMap<String, wgpu::BindingResource<'_>> =
            HashMap::from([
                ("gParams".into(), tokens_to_kinds_params.as_entire_binding()),
                ("token_words".into(), token_buf.as_entire_binding()),
                (
                    "lexer_token_count".into(),
                    token_count_buf.as_entire_binding(),
                ),
                (
                    "token_impl_context_event".into(),
                    bufs.token_impl_context_event.as_entire_binding(),
                ),
                (
                    "semantic_token_kinds".into(),
                    bufs.semantic_token_kinds.as_entire_binding(),
                ),
            ]);
        let tokens_to_identifier_kinds = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_to_identifier_kinds"),
            &self.tokens_to_identifier_kinds.bind_group_layouts[0],
            &self.tokens_to_identifier_kinds.reflection,
            0,
            &tokens_to_identifier_kinds_resources,
        )?;

        Ok(ResidentTokenKindBindGroups {
            input_fingerprint,
            tokens_to_kinds_params,
            tokens_to_kinds,
            tokens_to_identifier_kinds,
        })
    }
}
