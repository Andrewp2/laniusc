use std::collections::HashMap;

use crate::{
    gpu::passes_core::{
        DispatchDim,
        InputElements,
        PassData,
        record_compiler_operation,
        validation_scopes_enabled,
    },
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

/// Second pair pass: prefix-scans per-block boundary totals.
pub struct Pair02ScanBlockTotalsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    Pair02ScanBlockTotalsPass,
    label: "pair_02_scan_block_totals",
    entry: "pair_02_scan_block_totals",
    shader: "lexer/pair/02_scan_block_totals"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Pair02ScanBlockTotalsPass {
    const NAME: &'static str = "pair_02_scan_block_totals";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }
    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a GpuBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gParams".into(),
                wgpu::BindingResource::Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("block_pair_ping".into(), b.dfa_02_ping.as_entire_binding()),
            ("block_pair_pong".into(), b.dfa_02_pong.as_entire_binding()),
        ])
    }

    fn record_pass<'a>(
        &self,
        ctx: &mut crate::gpu::passes_core::PassContext<'a, GpuBuffers, DebugOutput>,
        input: crate::gpu::passes_core::InputElements,
    ) -> anyhow::Result<(), anyhow::Error> {
        let device = ctx.device;
        let encoder = &mut ctx.encoder;
        let b = ctx.buffers;
        let maybe_dbg = &mut ctx.maybe_dbg;

        let use_scopes = validation_scopes_enabled();

        let validation_scope = crate::gpu::passes_core::validation_scope(device, use_scopes);

        let n = match input {
            InputElements::Elements1D(n) => n,
            _ => unreachable!(),
        };

        let pd = self.data();

        if let Some(dbg) = maybe_dbg.as_deref_mut() {
            dbg.gpu.pair_scan_rounds.clear();
        }

        // One block has its prefix already: pair_01 seeded it in ping.
        if super::block_total_scan_steps(n).is_empty() {
            if let Some(err) = crate::gpu::passes_core::pop_validation_scope(validation_scope) {
                return Err(anyhow::anyhow!(
                    "validation in pass {}: {:?}",
                    Self::NAME,
                    err
                ));
            }
            if let Some(d) = maybe_dbg.as_deref_mut() {
                (&self).record_debug(device, encoder, b, d);
            }
            return Ok(());
        }
        record_compiler_operation(Self::NAME);
        let res = self.create_resource_map(b);
        let bg = if let Some(cache) = ctx.bg_cache.as_deref_mut() {
            cache
                .reflected_for_graph_pass_data(device, Self::NAME, pd, b, &res, None)?
                .into_iter()
                .next()
                .expect("pair scan pass must have one reflected bind group")
        } else {
            crate::gpu::passes_core::CompilerGraphBuffers::validate_compiler_pass(
                b,
                Self::NAME,
                &res,
                None,
            )?;
            std::sync::Arc::new(
                crate::gpu::passes_core::bind_group::create_bind_group_from_reflection(
                    device,
                    Some(Self::NAME),
                    &pd.bind_group_layouts[0],
                    &pd.reflection,
                    0,
                    &res,
                )
                .expect("pair scan graph binding reflection"),
            )
        };
        // One workgroup scans every block (02_scan_block_totals.slang).
        let mut pass = crate::gpu::passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some(Self::NAME),
                timestamp_writes: None,
            },
        );
        pass.set_pipeline(&pd.pipeline);
        pass.set_bind_group(0, bg.as_ref(), &[]);
        crate::gpu::passes_core::record_compute_dispatch();
        if !crate::gpu::passes_core::debug_operation_skipped() {
            pass.dispatch_workgroups(1, 1, 1);
        }
        drop(pass);
        crate::gpu::timer::stamp_active_operation(encoder, Self::NAME.to_owned());

        if let Some(err) = crate::gpu::passes_core::pop_validation_scope(validation_scope) {
            return Err(anyhow::anyhow!(
                "validation in pass {}: {:?}",
                Self::NAME,
                err
            ));
        }

        if let Some(d) = maybe_dbg.as_deref_mut() {
            (&self).record_debug(device, encoder, b, d);
        }
        Ok(())
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.block_pair_ping.set_from_copy(
            device,
            encoder,
            &b.dfa_02_ping,
            "dbg.block_pair_ping",
            b.dfa_02_ping.byte_size,
        );
        dbg.gpu.block_pair_pong.set_from_copy(
            device,
            encoder,
            &b.dfa_02_pong,
            "dbg.block_pair_pong",
            b.dfa_02_pong.byte_size,
        );

        let last = if super::block_total_scan_last_writer_is_ping(b.nb_sum) {
            &b.dfa_02_ping
        } else {
            &b.dfa_02_pong
        };
        dbg.gpu.block_prefix_pair.set_from_copy(
            device,
            encoder,
            last,
            "dbg.block_prefix_pair",
            last.byte_size,
        );
    }
}
