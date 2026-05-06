use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::gpu::buffers::{PackOffsetScanStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_pairs: u32,
    pub scan_step: u32,
}

pub struct PackOffsetsScanPass {
    data: PassData,
}

impl PackOffsetsScanPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "pack_offsets_scan",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/pack_offsets_scan.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/pack_offsets_scan.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }

    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.pack_offset_scan_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &PackOffsetScanStep,
    ) -> Result<()> {
        let sc_prefix_in = if step.read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let sc_prefix_out = if step.write_to_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_prefix_in = if step.read_from_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };
        let emit_prefix_out = if step.write_to_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            (
                "out_headers".into(),
                buffers.out_headers.as_entire_binding(),
            ),
            ("sc_prefix_in".into(), sc_prefix_in.as_entire_binding()),
            ("emit_prefix_in".into(), emit_prefix_in.as_entire_binding()),
            ("sc_prefix_out".into(), sc_prefix_out.as_entire_binding()),
            (
                "emit_prefix_out".into(),
                emit_prefix_out.as_entire_binding(),
            ),
            ("sc_offsets".into(), buffers.sc_offsets.as_entire_binding()),
            (
                "emit_offsets".into(),
                buffers.emit_offsets.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_offsets_scan"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.n_tokens.saturating_sub(1)),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("pack_offsets_scan"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
