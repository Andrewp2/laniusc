// src/parser/driver/resident_passes.rs

use super::*;

impl GpuParser {
    /// Records the resident LL(1) parser pipeline over already-resident token buffers.
    pub(super) fn record_ll1_resident_passes(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        include_tree: bool,
        include_hir_spans: bool,
        literal_source: Option<(u32, &wgpu::Buffer, &wgpu::Buffer)>,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let mut no_timer: Option<&mut GpuTimer> = None;
        let mut dbg_ref: Option<&mut DebugOutput> = None;
        let mut cache_guard = self.bg_cache.lock().expect("parser.bg_cache poisoned");
        let mut ctx = PassContext {
            device: &self.device,
            encoder,
            buffers: bufs,
            maybe_timer: &mut no_timer,
            maybe_dbg: &mut dbg_ref,
            bg_cache: Some(&mut *cache_guard),
        };

        self.record_active_pair_dispatch_args(ctx.encoder, bufs)?;
        stamp_timer(timer_ref, ctx.encoder, "parser.active_pair_dispatch_args");
        self.passes
            .llp_pairs
            .record_pass_indirect(&mut ctx, &bufs.active_pair_thread_dispatch_args)?;
        stamp_timer(timer_ref, ctx.encoder, "parser.llp_pairs");
        self.passes.pack_offsets.record_scan_indirect(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            &bufs.active_pair_thread_dispatch_args,
        )?;
        stamp_timer(timer_ref, ctx.encoder, "parser.pack_offsets");
        self.passes.pack_offsets_status.record_pass_indirect(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            &bufs.active_pair_thread_dispatch_args,
        )?;
        stamp_timer(timer_ref, ctx.encoder, "parser.pack_offsets_status");
        self.passes
            .pack_varlen
            .record_pass_indirect(&mut ctx, &bufs.active_pair_group_dispatch_args)?;
        stamp_timer(timer_ref, ctx.encoder, "parser.pack_varlen");
        passes::record_stack_effect_validation(&mut ctx, &self.passes)?;
        stamp_timer(timer_ref, ctx.encoder, "parser.stack_effect_status");
        if include_tree {
            self.record_tree_active_dispatch_args(ctx.encoder, bufs)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_active_dispatch_args");
            self.record_tree_feature_dispatch_args(ctx.encoder, bufs)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_feature_dispatch_args");
            self.passes.tree_prefix_01.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_01");
            self.passes
                .tree_prefix_02
                .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_02");
            self.passes.tree_prefix_03.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_capacity.saturating_add(1),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_03");
            self.passes
                .tree_prefix_04
                .record_build(ctx.device, ctx.encoder, ctx.buffers)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_04");
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch = ComputePassBatch::begin(ctx.encoder, "parser.tree-records.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_parent,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_spans,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_prev_sibling_clear,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_prev_sibling_scatter,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_nodes,
                    &bufs.tree_active_dispatch_args,
                )?;
            } else {
                self.passes
                    .tree_parent
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_parent");
                self.passes
                    .tree_spans
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_spans");
                self.passes
                    .tree_prev_sibling_clear
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_prev_sibling_clear");
                self.passes
                    .tree_prev_sibling_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_prev_sibling_scatter");
                self.passes
                    .hir_nodes
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_nodes");
            }
            self.passes.hir_semantic_prefix_local.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_prefix_local");
            self.passes.hir_semantic_prefix_blocks.record_scan(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_prefix_blocks");
            self.passes.hir_semantic_compact_scatter.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(
                timer_ref,
                ctx.encoder,
                "parser.hir_semantic_compact_scatter",
            );
            self.passes.hir_semantic_dispatch_args.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(1),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_dispatch_args");
            self.passes
                .hir_semantic_subtree_end
                .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_subtree_end");
            self.passes.hir_semantic_parent_init.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_init");
            self.passes.hir_semantic_parent_step.record_steps(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_step");
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch = ComputePassBatch::begin(ctx.encoder, "parser.semantic-nav.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_parent_scatter,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_nav,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_depth_init,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            } else {
                self.passes
                    .hir_semantic_parent_scatter
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_scatter");
                self.passes
                    .hir_semantic_nav
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_nav");
                self.passes
                    .hir_semantic_depth_init
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_depth_init");
            }
            self.passes.hir_semantic_depth_step.record_steps_indirect(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
                &bufs.hir_semantic_dispatch_args,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_depth_step");
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch =
                    ComputePassBatch::begin(ctx.encoder, "parser.semantic-child-index.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_child_index_clear,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_child_index_links,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            } else {
                self.passes
                    .hir_semantic_child_index_clear
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_semantic_child_index_clear",
                );
                self.passes
                    .hir_semantic_child_index_links
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_semantic_child_index_links",
                );
            }
            self.passes
                .hir_semantic_child_index_rank_step
                .record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            stamp_timer(
                timer_ref,
                ctx.encoder,
                "parser.hir_semantic_child_index_rank_step",
            );
            if include_hir_spans {
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-type-records.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_record_clear_base,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_record_clear_calls,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_fields,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_path_leaf_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_record_clear_base
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_record_clear_base");
                    self.passes
                        .hir_record_clear_calls
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_record_clear_calls");
                    self.passes
                        .hir_type_fields
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_fields");
                    self.passes
                        .hir_type_path_leaf_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_links");
                }
                self.passes.hir_type_path_leaf_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.tree_active_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_step");
                ctx.encoder.clear_buffer(
                    &bufs.hir_type_path_leaf_link_b.buffer,
                    0,
                    Some(u64::from(bufs.tree_capacity) * 4),
                );
                ctx.encoder
                    .clear_buffer(&bufs.source_file_token_end, 0, None);
                self.passes.source_file_token_end.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(bufs.token_input_capacity),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.source_file_token_end");
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-type-links.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_path_leaf_scatter,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_spans,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_arg_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_type_path_leaf_scatter
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_scatter");
                    self.passes
                        .hir_spans
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_spans");
                    self.passes
                        .hir_type_arg_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_links");
                }
                clear_type_arg_rank_b(ctx.encoder, bufs);
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_type_fields_params,
                        &bufs.hir_type_arg_owner_a,
                        &bufs.hir_type_arg_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_type_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_compact_scatter",
                );
                self.passes.hir_type_arg_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_list_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_rank_step");
                self.passes
                    .hir_type_arg_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_scatter");
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-enum-links.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_enum_match_fields,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_enum_variant_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_enum_match_fields
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_match_fields");
                    self.passes
                        .hir_enum_variant_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_links");
                }
                self.passes.hir_enum_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_enum_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_rank_prefix_blocks");
                self.passes.hir_enum_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_enum_rank_compact_scatter",
                );
                self.passes
                    .hir_enum_variant_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_enum_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_rank_step");
                self.passes
                    .hir_enum_variant_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_scatter");
                self.passes
                    .hir_item_fields
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_item_fields");
                self.passes
                    .hir_type_alias_owner_init
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_owner_init");
                self.passes
                    .hir_type_alias_owner_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_owner_step");
                self.passes
                    .hir_type_alias_target
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_target");
                self.passes
                    .hir_fn_signature_owner_init
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_signature_owner_init");
                self.passes
                    .hir_fn_signature_owner_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.tree_active_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_signature_owner_step");
                self.passes
                    .hir_fn_return_type
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_return_type");
                self.passes
                    .hir_method_signature_status
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_method_signature_status");
                self.passes
                    .hir_param_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_param_fields_params,
                        &bufs.hir_param_owner_a,
                        &bufs.hir_param_link_a,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_param_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_param_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_param_rank_compact_scatter",
                );
                self.passes.hir_param_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_list_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_rank_step");
                self.passes
                    .hir_param_id_clear
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_id_clear");
                self.passes
                    .hir_param_id_base
                    .record_pass_indirect(&mut ctx, &bufs.hir_list_rank_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_id_base");
                self.passes
                    .hir_param_id_apply
                    .record_pass_indirect(&mut ctx, &bufs.hir_list_rank_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_id_apply");
                if parser_compute_pass_batching_enabled(timer_ref) {
                    {
                        let bg_cache = ctx
                            .bg_cache
                            .as_deref_mut()
                            .expect("parser batching requires bind-group cache");
                        let mut batch =
                            ComputePassBatch::begin(ctx.encoder, "parser.hir-core-fields.batch");
                        batch.record_pass_indirect_cached(
                            ctx.device,
                            ctx.buffers,
                            bg_cache,
                            &self.passes.hir_param_fields,
                            &bufs.hir_semantic_dispatch_args,
                        )?;
                        batch.record_pass_indirect_cached(
                            ctx.device,
                            ctx.buffers,
                            bg_cache,
                            &self.passes.hir_method_fields,
                            &bufs.hir_semantic_dispatch_args,
                        )?;
                        batch.record_pass_indirect_cached(
                            ctx.device,
                            ctx.buffers,
                            bg_cache,
                            &self.passes.hir_expr_fields,
                            &bufs.hir_semantic_dispatch_args,
                        )?;
                    }
                    self.passes
                        .hir_expr_result_root_step
                        .record_steps_indirect(
                            ctx.device,
                            ctx.encoder,
                            ctx.buffers,
                            &bufs.tree_active_dispatch_args,
                        )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_expr_result_root_step");
                    self.passes
                        .hir_binary_spans
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_spans");
                    self.passes.hir_binary_span_step.record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_span_step");
                    self.passes
                        .hir_binary_span_apply
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_span_apply");
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-core-stmt-fields.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_member_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_index_spans,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_member_spans,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_stmt_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_param_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_fields");
                    self.passes
                        .hir_method_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_method_fields");
                    self.passes
                        .hir_expr_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_expr_fields");
                    self.passes
                        .hir_expr_result_root_step
                        .record_steps_indirect(
                            ctx.device,
                            ctx.encoder,
                            ctx.buffers,
                            &bufs.tree_active_dispatch_args,
                        )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_expr_result_root_step");
                    self.passes
                        .hir_binary_spans
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_spans");
                    self.passes.hir_binary_span_step.record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_span_step");
                    self.passes
                        .hir_binary_span_apply
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_binary_span_apply");
                    self.passes
                        .hir_member_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_member_fields");
                    self.passes
                        .hir_index_spans
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_index_spans");
                    self.passes
                        .hir_member_spans
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_member_spans");
                    self.passes
                        .hir_stmt_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_stmt_fields");
                }
                if let Some((source_len, token_buf, source_buf)) = literal_source {
                    self.passes.hir_literal_values.record_with_source(
                        &self.device,
                        ctx.encoder,
                        bufs,
                        &bufs.tree_active_dispatch_args,
                        source_len,
                        token_buf,
                        source_buf,
                    )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_literal_values");
                }
                self.passes
                    .hir_call_fields
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_fields");
                self.passes
                    .hir_call_spans
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_spans");
                self.passes
                    .hir_range_spans
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_range_spans");
                self.passes
                    .hir_call_arg_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_arg_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_call_fields_params,
                        &bufs.hir_call_arg_owner_a,
                        &bufs.hir_call_arg_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_call_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_compact_scatter",
                );
                self.passes
                    .hir_call_arg_ordinal_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_list_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_arg_ordinal_step");
                self.passes
                    .hir_call_arg_ordinal_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_ordinal_scatter",
                );
                self.passes
                    .hir_array_fields
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_fields");
                self.passes
                    .hir_array_element_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_array_fields_params,
                        &bufs.hir_array_element_owner_a,
                        &bufs.hir_array_element_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_array_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_compact_scatter",
                );
                self.passes
                    .hir_array_element_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_list_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_rank_step");
                self.passes
                    .hir_array_element_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_scatter");
                self.passes
                    .hir_match_arm_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_links");
                self.passes.hir_match_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_match_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_match_rank_prefix_blocks",
                );
                self.passes.hir_match_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_match_rank_compact_scatter",
                );
                self.passes.hir_match_arm_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_match_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_rank_step");
                self.passes
                    .hir_match_arm_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_scatter");
                self.passes
                    .hir_struct_fields
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_fields");
                self.passes
                    .hir_context_relations_init
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_context_relations_init");
                self.passes
                    .hir_context_relations_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_context_relations_step");
                self.passes
                    .hir_context_relations_scatter
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_context_relations_scatter",
                );
                self.passes
                    .hir_stmt_scope
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_stmt_scope");
                self.passes
                    .hir_struct_field_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_links");
                self.passes
                    .hir_struct_lit_spans
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_lit_spans");
                self.passes.hir_struct_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_struct_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_prefix_blocks",
                );
                self.passes.hir_struct_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_compact_scatter",
                );
                self.passes
                    .hir_struct_field_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_struct_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_rank_step");
                self.passes
                    .tree_prev_sibling_clear
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_lit_field_next_clear",
                );
                self.passes
                    .hir_struct_field_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_scatter");
                self.passes
                    .hir_item_decl_tokens
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_item_decl_tokens");
            }
        }
        Ok(())
    }
}
