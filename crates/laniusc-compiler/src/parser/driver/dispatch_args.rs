use super::*;

impl GpuParser {
    /// Records feature-specific tree dispatch arguments for enums, matches, and structs.
    pub(super) fn record_tree_feature_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        bufs.dispatch_operations.record_tree_features(encoder)
    }

    /// Records indirect dispatch arguments for active adjacent parser token pairs.
    pub(super) fn record_active_pair_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        bufs.dispatch_operations.record_active_pair(encoder)
    }

    /// Records the minimal parser sequence needed to project tree capacity/status.
    pub(super) fn record_resident_partial_parse_status(
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
        self.passes.pack_totals_blocks.record_pass(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            ctx.bg_cache
                .as_deref_mut()
                .expect("resident parser requires a bind-group cache"),
        )?;
        self.passes.pack_totals_reduce.record_reduce(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            ctx.bg_cache
                .as_deref_mut()
                .expect("resident parser requires a bind-group cache"),
        )?;
        self.passes.pack_totals_status.record_pass(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            ctx.bg_cache
                .as_deref_mut()
                .expect("resident parser requires a bind-group cache"),
        )?;
        Ok(())
    }
}
