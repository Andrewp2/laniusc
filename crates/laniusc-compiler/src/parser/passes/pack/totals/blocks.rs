use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, DispatchDim, InputElements, PassData, plan_workgroups},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for block-level packed stream totals.
pub struct Params {
    pub n_pairs: u32,
}

/// Pass that computes per-block stack-change and emit totals for packed parser pairs.
pub struct PackTotalsBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackTotalsBlocksPass,
    label: "pack_totals_blocks",
    shader: "parser/pack/totals/blocks"
);

impl PackTotalsBlocksPass {
    pub(in crate::parser) fn data(&self) -> &PassData {
        &self.data
    }

    /// Records the block-total pass over parser pair outputs.
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.pack_totals_blocks_params.as_entire_binding(),
            ),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            (
                "out_headers".into(),
                buffers.out_headers.as_entire_binding(),
            ),
            (
                "sc_block_sum".into(),
                buffers.pack_sc_prefix_a.as_entire_binding(),
            ),
            (
                "emit_block_sum".into(),
                buffers.pack_emit_prefix_a.as_entire_binding(),
            ),
        ]);
        let bind_group = cache
            .reflected_for_graph_pass_data(
                device,
                crate::parser::compiler_graph::PACK_TOTALS_BLOCKS,
                &self.data,
                buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("pack totals block pass must have one reflected bind group");
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let pair_blocks = n_pairs.div_ceil(256).max(1);
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(pair_blocks.saturating_mul(256)),
            [tgsx, tgsy, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            crate::parser::compiler_graph::PACK_TOTALS_BLOCKS,
            (gx, gy, gz),
        );
        Ok(())
    }
}
