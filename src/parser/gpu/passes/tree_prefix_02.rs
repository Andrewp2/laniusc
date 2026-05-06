use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassData, bind_group, plan_workgroups},
    parser::gpu::buffers::{ParserBuffers, TreePrefixScanStep},
};

pub struct TreePrefixScanBlocksPass {
    data: PassData,
}

impl TreePrefixScanBlocksPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_prefix_02_scan_blocks",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_02_scan_blocks.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_02_scan_blocks.reflect.json"
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
        for step in &buffers.tree_prefix_scan_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &TreePrefixScanStep,
    ) -> Result<()> {
        let prefix_in = if step.read_from_a {
            &buffers.tree_block_prefix_a
        } else {
            &buffers.tree_block_prefix_b
        };
        let prefix_out = if step.write_to_a {
            &buffers.tree_block_prefix_a
        } else {
            &buffers.tree_block_prefix_b
        };
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gTree".into(), step.params.as_entire_binding()),
            (
                "block_sum".into(),
                buffers.tree_block_sum.as_entire_binding(),
            ),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            (
                "block_prefix".into(),
                buffers.tree_block_prefix.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tree_prefix_02_scan_blocks"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_n_node_blocks),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tree_prefix_02_scan_blocks"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreePrefixScanBlocksPass {
    const NAME: &'static str = "tree_prefix_02_scan_blocks";
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
            ("gTree".into(), b.tree_prefix_params.as_entire_binding()),
            ("block_sum".into(), b.tree_block_sum.as_entire_binding()),
            (
                "prefix_in".into(),
                b.tree_block_prefix_b.as_entire_binding(),
            ),
            (
                "prefix_out".into(),
                b.tree_block_prefix_a.as_entire_binding(),
            ),
            (
                "block_prefix".into(),
                b.tree_block_prefix.as_entire_binding(),
            ),
        ])
    }
}
