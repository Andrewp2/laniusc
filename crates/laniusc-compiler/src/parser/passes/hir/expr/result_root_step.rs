use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates expression result-root nodes.
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
        self.record_steps_inner(device, encoder, buffers, Some(dispatch_args))
    }

    /// Records expression result-root propagation steps with direct dispatch.
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, None)
    }

    fn record_steps_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0, dispatch_args)?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            encoder.copy_buffer_to_buffer(
                &buffers.hir_expr_result_root_scratch_node.buffer,
                0,
                &buffers.hir_expr_result_root_node.buffer,
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
        dispatch_args: Option<&wgpu::Buffer>,
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

        if let Some(dispatch_args) = dispatch_args {
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder,
                &self.data,
                &bind_group,
                "hir_expr_result_root_step",
                dispatch_args,
            );
        } else {
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
                "hir_expr_result_root_step",
                groups,
            );
        }
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
