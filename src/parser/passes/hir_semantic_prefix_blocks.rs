use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_blocks: u32,
    pub scan_step: u32,
}

pub struct HirSemanticPrefixBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticPrefixBlocksPass,
    label: "hir_semantic_prefix_01_blocks",
    shader: "hir_semantic_prefix_01_blocks"
);

impl HirSemanticPrefixBlocksPass {
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.hir_semantic_prefix_scan_steps {
            let prefix_in = if step.read_from_a {
                &buffers.hir_semantic_block_prefix_a
            } else {
                &buffers.hir_semantic_block_prefix_b
            };
            let prefix_out = if step.write_to_a {
                &buffers.hir_semantic_block_prefix_a
            } else {
                &buffers.hir_semantic_block_prefix_b
            };
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gHirSemanticBlocks".into(), step.params.as_entire_binding()),
                (
                    "hir_semantic_block_sum".into(),
                    buffers.hir_semantic_block_count.as_entire_binding(),
                ),
                (
                    "hir_semantic_block_prefix_in".into(),
                    prefix_in.as_entire_binding(),
                ),
                (
                    "hir_semantic_block_prefix_out".into(),
                    prefix_out.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("hir_semantic_prefix_01_blocks"),
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
                label: Some("hir_semantic_prefix_01_blocks"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.data.pipeline);
            pass.set_bind_group(0, Some(&bind_group), &[]);
            pass.dispatch_workgroups(gx, gy, gz);
        }
        Ok(())
    }
}
