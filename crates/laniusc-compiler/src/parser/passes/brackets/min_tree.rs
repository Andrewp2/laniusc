use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, DispatchDim, InputElements, PassData, plan_workgroups},
    parser::buffers::{ParserBuffers, TreePrefixMaxBuildStep},
};

/// Builds the block-minimum tree used by stack-effect PSE validation.
pub struct BracketsMinTreePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsMinTreePass,
    label: "brackets_04_build_min_tree",
    shader: "parser/brackets/04_build_min_tree"
);

impl BracketsMinTreePass {
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }

    pub fn record_build(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        for (index, step) in buffers.b_min_tree_steps.iter().enumerate() {
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
            ("gMinTree".into(), step.params.as_entire_binding()),
            (
                "block_row_min".into(),
                buffers.b_block_row_min.as_entire_binding(),
            ),
            (
                "block_prefix".into(),
                buffers.b_block_prefix.as_entire_binding(),
            ),
            ("min_tree".into(), buffers.b_min_tree.as_entire_binding()),
        ]);
        let operation = "brackets_04_build_min_tree";
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
            .expect("bracket min-tree pass must have one reflected bind group");
        let [x, y, _] = self.data.thread_group_size;
        let groups = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(step.work_items),
            [x, y, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
            groups,
        );
        Ok(())
    }
}
