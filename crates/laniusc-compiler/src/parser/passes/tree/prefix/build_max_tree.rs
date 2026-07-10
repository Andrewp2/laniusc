use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassData, bind_group, plan_workgroups},
    parser::buffers::{ParserBuffers, TreePrefixMaxBuildStep},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for one tree-prefix max-tree build step.
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

/// Pass that builds the auxiliary max tree used by tree-prefix traversal.
pub struct TreePrefixMaxBuildPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrefixMaxBuildPass,
    label: "tree_prefix_04_build_max_tree",
    shader: "parser/tree/prefix/04_build_max_tree"
);

impl TreePrefixMaxBuildPass {
    /// Records all configured tree-prefix max-tree build steps.
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
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            &bind_group,
            "tree_prefix_04_build_max_tree",
            (gx, gy, gz),
        );
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
