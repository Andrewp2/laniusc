use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::{PackTotalReduceStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for one packed-total reduction step.
pub struct Params {
    pub item_count: u32,
}

/// Pass that reduces packed stream totals across scan blocks.
pub struct PackTotalsReducePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackTotalsReducePass,
    label: "pack_totals_reduce",
    shader: "parser/pack/totals/reduce_pass"
);

impl PackTotalsReducePass {
    /// Records all configured packed-total reduction steps.
    pub fn record_reduce(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.pack_total_reduce_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &PackTotalReduceStep,
    ) -> Result<()> {
        let sc_in = if step.read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let sc_out = if step.write_to_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_in = if step.read_from_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };
        let emit_out = if step.write_to_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("sc_in".into(), sc_in.as_entire_binding()),
            ("emit_in".into(), emit_in.as_entire_binding()),
            ("sc_out".into(), sc_out.as_entire_binding()),
            ("emit_out".into(), emit_out.as_entire_binding()),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_totals_reduce"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let output_items = step.item_count.div_ceil(256).max(1);
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(output_items.saturating_mul(256)),
            [tgsx, tgsy, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            &bind_group,
            "pack_totals_reduce",
            (gx, gy, gz),
        );
        Ok(())
    }
}
