use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        BindGroupCache,
        DispatchDim,
        InputElements,
        Pass,
        PassData,
        plan_workgroups,
    },
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
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        for (index, step) in buffers.tree_prefix_max_build_steps.iter().enumerate() {
            self.record_step(device, encoder, buffers, cache, index, step)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        index: usize,
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
        let operation = "tree_prefix_04_build_max_tree";
        let invocation = format!("{operation}.{index}");
        let bind_group = cache
            .reflected_for_graph_invocation(
                device,
                &invocation,
                operation,
                &self.data,
                buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("tree-prefix max-tree pass must have one reflected bind group");
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(step.work_items),
            [tgsx, tgsy, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
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
