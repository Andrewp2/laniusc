use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that computes each semantic node's index within its parent.
pub struct HirSemanticChildIndexRankStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexRankStepPass,
    label: "hir_semantic_child_index_rank_step",
    shader: "parser/hir/semantic/child/index/rank_step"
);

impl HirSemanticChildIndexRankStepPass {
    /// Records all semantic child-index propagation steps with indirect dispatch sizing.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0, dispatch_args)?;
        }

        if steps % 2 == 1 {
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_semantic_child_index_link_b,
                    &buffers.hir_semantic_child_index_link_a,
                ),
                (
                    &buffers.hir_semantic_child_index_rank_b,
                    &buffers.hir_semantic_child_index_rank_a,
                ),
            ] {
                encoder.copy_buffer_to_buffer(&src.buffer, 0, &dst.buffer, 0, bytes);
            }
        }

        encoder.copy_buffer_to_buffer(
            &buffers.hir_semantic_child_index_rank_a.buffer,
            0,
            &buffers.hir_semantic_child_index.buffer,
            0,
            u64::from(buffers.tree_capacity) * 4,
        );

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        read_from_a: bool,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let (link_in, rank_in, link_out, rank_out) = if read_from_a {
            (
                &buffers.hir_semantic_child_index_link_a,
                &buffers.hir_semantic_child_index_rank_a,
                &buffers.hir_semantic_child_index_link_b,
                &buffers.hir_semantic_child_index_rank_b,
            )
        } else {
            (
                &buffers.hir_semantic_child_index_link_b,
                &buffers.hir_semantic_child_index_rank_b,
                &buffers.hir_semantic_child_index_link_a,
                &buffers.hir_semantic_child_index_rank_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirSemantic".into(),
                buffers.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.projected_status.as_entire_binding()
                } else {
                    buffers.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_count".into(),
                buffers.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_in".into(),
                rank_in.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_out".into(),
                rank_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_semantic_child_index_rank_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_semantic_child_index_rank_step"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups_indirect(dispatch_args, 0);
        Ok(())
    }
}

fn pointer_jump_steps_for_items(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    let target = items.max(1);
    while span < target {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}
