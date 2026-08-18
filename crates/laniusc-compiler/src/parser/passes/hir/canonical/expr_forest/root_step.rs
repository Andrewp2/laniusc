use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{BindGroupCache, DispatchDim, InputElements, PassData, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

/// Resolves compact expression roots with bounded parallel parent walks.
pub struct HirCanonicalExprForestRootStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_canonical_expr_forest_root_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_canonical_expr_forest_root_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_canonical_expr_forest_root_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_canonical_expr_forest_root_step.finalize";

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
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = bounded_parent_walk_steps(buffers.hir_canonical_capacity);
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
            self.record_step(
                device,
                encoder,
                buffers,
                step,
                input,
                output,
                step % 2 == 0,
                step + 1 == steps && steps % 2 == 1,
                cache,
            )?;
        }

        if steps % 2 == 1 {
            buffers.record_finalizer(FINALIZE, encoder)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: u32,
        input: &LaniusBuffer<u32>,
        output: &LaniusBuffer<u32>,
        read_from_a: bool,
        final_unpaired_step: bool,
        cache: &mut BindGroupCache,
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
        let label = if final_unpaired_step {
            A_TO_B_FINAL
        } else if read_from_a {
            A_TO_B
        } else {
            B_TO_A
        };
        let invocation = format!("{label}.{step}");
        let bind_group = cache
            .reflected_for_graph_invocation(
                device,
                &invocation,
                label,
                &self.data,
                buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("canonical expression-root step must have one reflected bind group");
        let [x, y, _] = self.data.thread_group_size;
        let groups = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.hir_canonical_capacity),
            [x, y, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            label,
            groups,
        );
        Ok(())
    }

    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}

pub(in crate::parser) fn bounded_parent_walk_steps(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    while span < items.max(1) {
        span = span.saturating_mul(16);
        steps += 1;
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::bounded_parent_walk_steps;

    #[test]
    fn compact_expression_root_steps_cover_arbitrary_depth() {
        assert_eq!(bounded_parent_walk_steps(0), 0);
        assert_eq!(bounded_parent_walk_steps(1), 0);
        assert_eq!(bounded_parent_walk_steps(2), 1);
        assert_eq!(bounded_parent_walk_steps(257), 3);
        assert_eq!(bounded_parent_walk_steps(10_000_000), 6);
    }
}
