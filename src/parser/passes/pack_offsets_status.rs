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

pub struct PackOffsetsStatusPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackOffsetsStatusPass,
    label: "pack_offsets_status",
    shader: "pack_offsets_status"
);

impl PackOffsetsStatusPass {
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        let params: LaniusBuffer<Params> =
            uniform_from_val(device, "pack.offset_status.params", &Params { n_pairs });
        let read_from_a = buffers
            .pack_offset_scan_steps
            .last()
            .map(|step| step.read_from_a)
            .unwrap_or(true);
        let sc_prefix = if read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_prefix = if read_from_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            ("sc_prefix".into(), sc_prefix.as_entire_binding()),
            ("emit_prefix".into(), emit_prefix.as_entire_binding()),
            (
                "projected_status".into(),
                buffers.projected_status.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_offsets_status"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(n_pairs.max(1)),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("pack_offsets_status"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
