use super::*;

impl GpuParser {
    pub(super) fn record_tree_active_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gTree".into(), bufs.tree_prefix_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                bufs.ll1_status.as_entire_binding(),
            ),
            (
                "tree_active_dispatch_args".into(),
                bufs.tree_active_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tree_active_dispatch_args"),
            &self.tree_active_dispatch_args.bind_group_layouts[0],
            &self.tree_active_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tree_active_dispatch_args,
            &bind_group,
            "parser.tree_active_dispatch_args",
            1,
        )
    }

    pub(super) fn record_tree_feature_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gTree".into(), bufs.tree_prefix_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                bufs.ll1_status.as_entire_binding(),
            ),
            (
                "token_feature_flags".into(),
                bufs.token_feature_flags.as_entire_binding(),
            ),
            (
                "tree_enum_dispatch_args".into(),
                bufs.tree_enum_dispatch_args.as_entire_binding(),
            ),
            (
                "tree_match_dispatch_args".into(),
                bufs.tree_match_dispatch_args.as_entire_binding(),
            ),
            (
                "tree_struct_dispatch_args".into(),
                bufs.tree_struct_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tree_feature_dispatch_args"),
            &self.tree_feature_dispatch_args.bind_group_layouts[0],
            &self.tree_feature_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tree_feature_dispatch_args,
            &bind_group,
            "parser.tree_feature_dispatch_args",
            1,
        )
    }

    pub(super) fn record_active_pair_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), bufs.params_llp.as_entire_binding()),
            ("token_count".into(), bufs.token_count.as_entire_binding()),
            (
                "active_pair_thread_dispatch_args".into(),
                bufs.active_pair_thread_dispatch_args.as_entire_binding(),
            ),
            (
                "active_pair_group_dispatch_args".into(),
                bufs.active_pair_group_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_active_pair_dispatch_args"),
            &self.active_pair_dispatch_args.bind_group_layouts[0],
            &self.active_pair_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.active_pair_dispatch_args,
            &bind_group,
            "parser.active_pair_dispatch_args",
            1,
        )
    }

    pub(super) fn record_resident_projected_status(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
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
        self.passes
            .llp_pairs
            .record_pass_indirect(&mut ctx, &bufs.active_pair_thread_dispatch_args)?;
        self.passes
            .pack_totals_blocks
            .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
        self.passes
            .pack_totals_reduce
            .record_reduce(ctx.device, ctx.encoder, ctx.buffers)?;
        self.passes
            .pack_totals_status
            .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
        Ok(())
    }
}
