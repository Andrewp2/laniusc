use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that propagates expression result-root nodes.
pub struct HirExprResultRootStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_expr_result_root_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_expr_result_root_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_expr_result_root_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_expr_result_root_step.finalize";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirExprResultRootStepPass,
    label: "hir_expr_result_root_step",
    shader: "parser/hir/expr/result_root_step"
);

impl HirExprResultRootStepPass {
    /// Records expression result-root propagation steps with indirect dispatch.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = bounded_walk_step_capacity(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(
                device,
                encoder,
                buffers,
                step,
                step % 2 == 0,
                step + 1 == steps && steps % 2 == 1,
                dispatch_args,
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
        read_from_root: bool,
        final_unpaired_step: bool,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let (root_in, root_out) = if read_from_root {
            (
                &buffers.hir_expr_result_root_node,
                &buffers.hir_expr_result_root_scratch_node,
            )
        } else {
            (
                &buffers.hir_expr_result_root_scratch_node,
                &buffers.hir_expr_result_root_node,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirExprResultRoot".into(),
                buffers.hir_expr_fields_params.as_entire_binding(),
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
                "hir_expr_result_root_in".into(),
                root_in.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_out".into(),
                root_out.as_entire_binding(),
            ),
        ]);

        let label = if final_unpaired_step {
            A_TO_B_FINAL
        } else if read_from_root {
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
                Some(dispatch_args),
            )?
            .into_iter()
            .next()
            .expect("expression result-root step must have one reflected bind group");

        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            bind_group.as_ref(),
            label,
            dispatch_args,
        );
        Ok(())
    }

    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}
