use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates nearest semantic parent records.
pub struct HirSemanticParentStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticParentStepPass,
    label: "hir_semantic_parent_step",
    shader: "parser/hir/semantic/parent/step"
);

impl HirSemanticParentStepPass {
    /// Records all semantic parent propagation steps with direct dispatch sizing.
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0)?;
        }

        if steps % 2 == 1 {
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_semantic_parent_link_b,
                    &buffers.hir_semantic_parent_link_a,
                ),
                (
                    &buffers.hir_semantic_parent_value_b,
                    &buffers.hir_semantic_parent_value_a,
                ),
            ] {
                encoder.copy_buffer_to_buffer(&src.buffer, 0, &dst.buffer, 0, bytes);
            }
        }

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        read_from_a: bool,
    ) -> Result<()> {
        let (link_in, value_in, link_out, value_out) = if read_from_a {
            (
                &buffers.hir_semantic_parent_link_a,
                &buffers.hir_semantic_parent_value_a,
                &buffers.hir_semantic_parent_link_b,
                &buffers.hir_semantic_parent_value_b,
            )
        } else {
            (
                &buffers.hir_semantic_parent_link_b,
                &buffers.hir_semantic_parent_value_b,
                &buffers.hir_semantic_parent_link_a,
                &buffers.hir_semantic_parent_value_a,
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
                "hir_semantic_parent_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_semantic_parent_value_in".into(),
                value_in.as_entire_binding(),
            ),
            (
                "hir_semantic_parent_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_semantic_parent_value_out".into(),
                value_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_semantic_parent_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_semantic_parent_step"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_capacity),
            [tgsx, tgsy, 1],
        )?;
        pass.dispatch_workgroups(gx, gy, gz);
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
