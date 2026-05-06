use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassData, bind_group, plan_workgroups},
    parser::gpu::buffers::{BracketsBlockPrefixScanStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_blocks: u32,
    pub scan_step: u32,
}

pub struct BracketsScanBlockPrefixPass {
    data: PassData,
}

impl BracketsScanBlockPrefixPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "brackets_02_scan_block_prefix",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_02_scan_block_prefix.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_02_scan_block_prefix.reflect.json"
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
        for step in &buffers.b02_scan_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &BracketsBlockPrefixScanStep,
    ) -> Result<()> {
        let sum_in = if step.read_from_a {
            &buffers.b_block_prefix_sum_a
        } else {
            &buffers.b_block_prefix_sum_b
        };
        let min_in = if step.read_from_a {
            &buffers.b_block_prefix_min_a
        } else {
            &buffers.b_block_prefix_min_b
        };
        let sum_out = if step.write_to_a {
            &buffers.b_block_prefix_sum_a
        } else {
            &buffers.b_block_prefix_sum_b
        };
        let min_out = if step.write_to_a {
            &buffers.b_block_prefix_min_a
        } else {
            &buffers.b_block_prefix_min_b
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("block_sum".into(), buffers.b_block_sum.as_entire_binding()),
            (
                "block_minpref".into(),
                buffers.b_block_minpref.as_entire_binding(),
            ),
            ("prefix_sum_in".into(), sum_in.as_entire_binding()),
            ("prefix_min_in".into(), min_in.as_entire_binding()),
            ("prefix_sum_out".into(), sum_out.as_entire_binding()),
            ("prefix_min_out".into(), min_out.as_entire_binding()),
            (
                "block_prefix".into(),
                buffers.b_block_prefix.as_entire_binding(),
            ),
            ("out_depths".into(), buffers.depths_out.as_entire_binding()),
            ("out_valid".into(), buffers.valid_out.as_entire_binding()),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("brackets_02_scan_block_prefix"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.b_n_blocks),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("brackets_02_scan_block_prefix"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for BracketsScanBlockPrefixPass {
    const NAME: &'static str = "brackets_02_scan_block_prefix";
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
            ("gParams".into(), b.b02_params.as_entire_binding()),
            ("block_sum".into(), b.b_block_sum.as_entire_binding()),
            (
                "block_minpref".into(),
                b.b_block_minpref.as_entire_binding(),
            ),
            (
                "prefix_sum_in".into(),
                b.b_block_prefix_sum_b.as_entire_binding(),
            ),
            (
                "prefix_min_in".into(),
                b.b_block_prefix_min_b.as_entire_binding(),
            ),
            (
                "prefix_sum_out".into(),
                b.b_block_prefix_sum_a.as_entire_binding(),
            ),
            (
                "prefix_min_out".into(),
                b.b_block_prefix_min_a.as_entire_binding(),
            ),
            ("block_prefix".into(), b.b_block_prefix.as_entire_binding()),
            ("out_depths".into(), b.depths_out.as_entire_binding()),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }
}
