use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that propagates expression result-root nodes.
pub struct HirExprResultRootStepPass {
    data: PassData,
}

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
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let steps = bounded_walk_step_capacity(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0, dispatch_args)?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            buffers.hir_expr_result_root_scratch_node.copy_to(
                encoder,
                0,
                &buffers.hir_expr_result_root_node,
                0,
                bytes,
            );
        }

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        read_from_root: bool,
        dispatch_args: &wgpu::Buffer,
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

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_expr_result_root_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            &bind_group,
            "hir_expr_result_root_step",
            dispatch_args,
        );
        Ok(())
    }
}
