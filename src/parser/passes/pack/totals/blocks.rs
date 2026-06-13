use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_pairs: u32,
}

pub struct PackTotalsBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackTotalsBlocksPass,
    label: "pack_totals_blocks",
    shader: "parser/pack/totals/blocks"
);

impl PackTotalsBlocksPass {
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        let params: LaniusBuffer<Params> =
            uniform_from_val(device, "pack.totals_blocks.params", &Params { n_pairs });
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
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
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_totals_blocks"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let pair_blocks = n_pairs.div_ceil(256).max(1);
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(pair_blocks.saturating_mul(256)),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("pack_totals_blocks"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
