use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{InputElements, PassData, bind_group, plan_workgroups},
    parser::gpu::buffers::{LL1EmitPrefixScanStep, ParserBuffers},
};

pub struct LL1BlocksEmitPrefixScanPass {
    data: PassData,
}

impl LL1BlocksEmitPrefixScanPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let spirv = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/ll1_blocks_04_scan_emit_prefix.spv"
        ));
        let reflect = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/ll1_blocks_04_scan_emit_prefix.reflect.json"
        ));
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "ll1_blocks_04_scan_emit_prefix",
            "main",
            spirv,
            reflect,
        )?;
        Ok(Self { data })
    }

    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.ll1_emit_prefix_scan_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &LL1EmitPrefixScanStep,
    ) -> Result<()> {
        let prefix_in = if step.read_from_a {
            &buffers.ll1_emit_prefix_a
        } else {
            &buffers.ll1_emit_prefix_b
        };
        let prefix_out = if step.write_to_a {
            &buffers.ll1_emit_prefix_a
        } else {
            &buffers.ll1_emit_prefix_b
        };
        let status_summary_in = if step.read_from_a {
            &buffers.ll1_status_summary_a
        } else {
            &buffers.ll1_status_summary_b
        };
        let status_summary_out = if step.write_to_a {
            &buffers.ll1_status_summary_a
        } else {
            &buffers.ll1_status_summary_b
        };
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            (
                "seeded_status".into(),
                buffers.ll1_seeded_status.as_entire_binding(),
            ),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            (
                "status_summary_in".into(),
                status_summary_in.as_entire_binding(),
            ),
            (
                "status_summary_out".into(),
                status_summary_out.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("ll1_blocks_04_scan_emit_prefix"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            crate::gpu::passes_core::DispatchDim::D1,
            InputElements::Elements1D(buffers.ll1_n_blocks),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("ll1_blocks_04_scan_emit_prefix"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
