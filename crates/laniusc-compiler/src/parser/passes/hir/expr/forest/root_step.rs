use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that resolves expression-forest roots.
pub struct HirExprForestRootStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirExprForestRootStepPass,
    label: "hir_expr_forest_root_step",
    shader: "parser/hir/expr/forest/root_step"
);

impl HirExprForestRootStepPass {
    /// Records enough indirect pointer-jump passes for the full tree capacity.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_schedule: &wgpu::Buffer,
    ) -> Result<()> {
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(
                device,
                encoder,
                buffers,
                step % 2 == 0,
                dispatch_schedule,
                u64::from(step) * 3 * std::mem::size_of::<u32>() as u64,
            )?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            encoder.copy_buffer_to_buffer(
                &buffers.hir_expr_result_root_scratch_node.buffer,
                0,
                &buffers.hir_expr_forest_root_node.buffer,
                0,
                u64::from(buffers.tree_capacity) * 4,
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
        dispatch_schedule: &wgpu::Buffer,
        dispatch_offset: u64,
    ) -> Result<()> {
        let (root_in, root_out) = if read_from_root {
            (
                &buffers.hir_expr_forest_root_node,
                &buffers.hir_expr_result_root_scratch_node,
            )
        } else {
            (
                &buffers.hir_expr_result_root_scratch_node,
                &buffers.hir_expr_forest_root_node,
            )
        };
        let resources = HashMap::from([
            (
                "gHirExprForest".into(),
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
                "hir_expr_forest_root_in".into(),
                root_in.as_entire_binding(),
            ),
            (
                "hir_expr_forest_root_out".into(),
                root_out.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_expr_forest_root_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        crate::gpu::passes_core::record_or_defer_compute_indirect_offset(
            encoder,
            &self.data,
            &bind_group,
            "hir_expr_forest_root_step",
            dispatch_schedule,
            dispatch_offset,
        );
        Ok(())
    }
}

fn pointer_jump_steps_for_items(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    while span < items.max(1) {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}
