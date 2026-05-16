use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassData, bind_group, plan_workgroups},
    parser::buffers::{ParserBuffers, TreePrefixMaxBuildStep},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_blocks: u32,
    pub leaf_base: u32,
    pub start_node: u32,
    pub node_count: u32,
    pub mode: u32,
    pub _pad0: u32,
    pub _pad1: u32,
    pub _pad2: u32,
}

pub struct TreePrefixMaxBuildPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrefixMaxBuildPass,
    label: "tree_prefix_04_build_max_tree",
    shader: "tree_prefix_04_build_max_tree"
);

impl TreePrefixMaxBuildPass {
    pub fn record_build(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.tree_prefix_max_build_steps {
            self.record_step(device, encoder, buffers, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &TreePrefixMaxBuildStep,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gMaxTree".into(), step.params.as_entire_binding()),
            (
                "prefix_block_max".into(),
                buffers.tree_prefix_block_max.as_entire_binding(),
            ),
            (
                "prefix_block_max_tree".into(),
                buffers.tree_prefix_block_max_tree.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tree_prefix_04_build_max_tree"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(step.work_items),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tree_prefix_04_build_max_tree"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreePrefixMaxBuildPass {
    const NAME: &'static str = "tree_prefix_04_build_max_tree";
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
            (
                "gMaxTree".into(),
                b.tree_prefix_max_build_steps[0].params.as_entire_binding(),
            ),
            (
                "prefix_block_max".into(),
                b.tree_prefix_block_max.as_entire_binding(),
            ),
            (
                "prefix_block_max_tree".into(),
                b.tree_prefix_block_max_tree.as_entire_binding(),
            ),
        ])
    }
}
