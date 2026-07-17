use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::{buffers::ParserBuffers, passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN},
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
        self.record_steps_for_buffers(
            device,
            encoder,
            buffers,
            &buffers.hir_semantic_parent_link_a,
            &buffers.hir_semantic_parent_value_a,
            &buffers.hir_semantic_parent_link_b,
            &buffers.hir_semantic_parent_value_b,
            "hir_semantic_parent_step",
        )
    }

    /// Propagates one nearest-ancestor relation through caller-selected
    /// phase-local link/value slots.
    pub fn record_steps_for_buffers(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        link_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        link_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        label: &'static str,
    ) -> Result<()> {
        let steps = pointer_jump_steps_after_local_span(buffers.tree_capacity);
        for step in 0..steps {
            let (link_in, value_in, link_out, value_out) = if step % 2 == 0 {
                (link_a, value_a, link_b, value_b)
            } else {
                (link_b, value_b, link_a, value_a)
            };
            self.record_step(
                device, encoder, buffers, link_in, value_in, link_out, value_out, label,
            )?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [(link_b, link_a), (value_b, value_a)] {
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
        link_in: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_in: &crate::gpu::buffers::LaniusBuffer<u32>,
        link_out: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_out: &crate::gpu::buffers::LaniusBuffer<u32>,
        label: &'static str,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirSemantic".into(),
                buffers.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.partial_parse_status.as_entire_binding()
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
            Some(label),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let groups = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_capacity),
            [tgsx, tgsy, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            &bind_group,
            label,
            groups,
        );
        Ok(())
    }
}

pub(crate) fn pointer_jump_steps_after_local_span(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    let target = items.max(1).div_ceil(SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN);
    while span < target {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::pointer_jump_steps_after_local_span;

    #[test]
    fn local_walk_reduces_global_pointer_jump_rounds_without_losing_depth_coverage() {
        assert_eq!(pointer_jump_steps_after_local_span(1), 0);
        assert_eq!(pointer_jump_steps_after_local_span(32), 0);
        assert_eq!(pointer_jump_steps_after_local_span(33), 1);
        assert_eq!(pointer_jump_steps_after_local_span(64), 1);
        assert_eq!(pointer_jump_steps_after_local_span(65), 2);
        assert_eq!(pointer_jump_steps_after_local_span(1_687_524), 16);
    }
}
