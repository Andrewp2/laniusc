use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassData, bind_group, plan_workgroups},
    parser::buffers::{BracketsHistogramScanStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_layers: u32,
    pub scan_step: u32,
}

pub struct BracketsScanHistogramsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsScanHistogramsPass,
    label: "brackets_05_scan_histograms",
    shader: "brackets_05_scan_histograms"
);

impl BracketsScanHistogramsPass {
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.b05_scan_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &BracketsHistogramScanStep,
    ) -> Result<()> {
        let push_in = if step.read_from_offsets {
            &buffers.b_off_push
        } else {
            &buffers.b_cur_push
        };
        let pop_in = if step.read_from_offsets {
            &buffers.b_off_pop
        } else {
            &buffers.b_cur_pop
        };
        let push_out = if step.write_to_offsets {
            &buffers.b_off_push
        } else {
            &buffers.b_cur_push
        };
        let pop_out = if step.write_to_offsets {
            &buffers.b_off_pop
        } else {
            &buffers.b_cur_pop
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("hist_push".into(), buffers.b_hist_push.as_entire_binding()),
            ("hist_pop".into(), buffers.b_hist_pop.as_entire_binding()),
            ("prefix_push_in".into(), push_in.as_entire_binding()),
            ("prefix_pop_in".into(), pop_in.as_entire_binding()),
            ("prefix_push_out".into(), push_out.as_entire_binding()),
            ("prefix_pop_out".into(), pop_out.as_entire_binding()),
            ("out_valid".into(), buffers.valid_out.as_entire_binding()),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("brackets_05_scan_histograms"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.b_n_layers),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("brackets_05_scan_histograms"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsScanHistogramsPass {
    const NAME: &'static str = "brackets_05_scan_histograms";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }
    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            ("gParams".into(), b.b05_params.as_entire_binding()),
            ("hist_push".into(), b.b_hist_push.as_entire_binding()),
            ("hist_pop".into(), b.b_hist_pop.as_entire_binding()),
            ("prefix_push_in".into(), b.b_cur_push.as_entire_binding()),
            ("prefix_pop_in".into(), b.b_cur_pop.as_entire_binding()),
            ("prefix_push_out".into(), b.b_off_push.as_entire_binding()),
            ("prefix_pop_out".into(), b.b_off_pop.as_entire_binding()),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }
}
