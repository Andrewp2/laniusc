use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

/// Pointer-jumps compact expression roots to convergence.
pub struct HirCanonicalExprForestRootStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalExprForestRootStepPass,
    label: "hir_canonical_expr_forest_root_step",
    shader: "parser/hir/canonical/expr_forest/root_step"
);

impl HirCanonicalExprForestRootStepPass {
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        let steps = pointer_jump_steps(buffers.hir_canonical_capacity);
        for step in 0..steps {
            let (input, output) = if step % 2 == 0 {
                (
                    &buffers.hir_canonical_expr_root,
                    &buffers.hir_canonical_expr_root_scratch,
                )
            } else {
                (
                    &buffers.hir_canonical_expr_root_scratch,
                    &buffers.hir_canonical_expr_root,
                )
            };
            self.record_step(device, encoder, buffers, input, output)?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            encoder.copy_buffer_to_buffer(
                &buffers.hir_canonical_expr_root_scratch.buffer,
                0,
                &buffers.hir_canonical_expr_root.buffer,
                0,
                u64::from(buffers.hir_canonical_capacity) * 4,
            );
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        input: &LaniusBuffer<u32>,
        output: &LaniusBuffer<u32>,
    ) -> Result<()> {
        let resources = HashMap::from([
            (
                "gCanonical".into(),
                buffers.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                buffers.hir_canonical_count.as_entire_binding(),
            ),
            ("expr_root_in".into(), input.as_entire_binding()),
            ("expr_root_out".into(), output.as_entire_binding()),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_canonical_expr_forest_root_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [x, y, _] = self.data.thread_group_size;
        let groups = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.hir_canonical_capacity),
            [x, y, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            &bind_group,
            "hir_canonical_expr_forest_root_step",
            groups,
        );
        Ok(())
    }
}

fn pointer_jump_steps(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    while span < items.max(1) {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::pointer_jump_steps;

    #[test]
    fn compact_expression_root_steps_cover_arbitrary_depth() {
        assert_eq!(pointer_jump_steps(0), 0);
        assert_eq!(pointer_jump_steps(1), 0);
        assert_eq!(pointer_jump_steps(2), 1);
        assert_eq!(pointer_jump_steps(257), 9);
        assert_eq!(pointer_jump_steps(10_000_000), 24);
    }
}
