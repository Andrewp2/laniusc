use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates context relations through HIR parents.
pub struct HirContextRelationsStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirContextRelationsStepPass,
    label: "hir_context_relations_step",
    shader: "parser/hir/context/relations/step"
);

impl HirContextRelationsStepPass {
    /// Records all context relation propagation steps with indirect dispatch sizing.
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
                    &buffers.hir_stmt_context_link_b,
                    &buffers.hir_stmt_context_link_a,
                ),
                (
                    &buffers.hir_contextual_stmt_value_b,
                    &buffers.hir_contextual_stmt_value_a,
                ),
                (
                    &buffers.hir_nearest_stmt_value_b,
                    &buffers.hir_nearest_stmt_value_a,
                ),
                (
                    &buffers.hir_nearest_block_value_b,
                    &buffers.hir_nearest_block_value_a,
                ),
                (
                    &buffers.hir_nearest_enclosing_control_value_b,
                    &buffers.hir_nearest_enclosing_control_value_a,
                ),
                (
                    &buffers.hir_nearest_loop_value_b,
                    &buffers.hir_nearest_loop_value_a,
                ),
                (
                    &buffers.hir_nearest_fn_value_b,
                    &buffers.hir_nearest_fn_value_a,
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
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let (link_in, value_in, link_out, value_out) = if read_from_a {
            (
                &buffers.hir_stmt_context_link_a,
                &buffers.hir_contextual_stmt_value_a,
                &buffers.hir_stmt_context_link_b,
                &buffers.hir_contextual_stmt_value_b,
            )
        } else {
            (
                &buffers.hir_stmt_context_link_b,
                &buffers.hir_contextual_stmt_value_b,
                &buffers.hir_stmt_context_link_a,
                &buffers.hir_contextual_stmt_value_a,
            )
        };
        let (nearest_value_in, nearest_value_out) = if read_from_a {
            (
                &buffers.hir_nearest_stmt_value_a,
                &buffers.hir_nearest_stmt_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_stmt_value_b,
                &buffers.hir_nearest_stmt_value_a,
            )
        };
        let (nearest_block_in, nearest_block_out) = if read_from_a {
            (
                &buffers.hir_nearest_block_value_a,
                &buffers.hir_nearest_block_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_block_value_b,
                &buffers.hir_nearest_block_value_a,
            )
        };
        let (nearest_control_in, nearest_control_out) = if read_from_a {
            (
                &buffers.hir_nearest_enclosing_control_value_a,
                &buffers.hir_nearest_enclosing_control_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_enclosing_control_value_b,
                &buffers.hir_nearest_enclosing_control_value_a,
            )
        };
        let (nearest_fn_in, nearest_fn_out) = if read_from_a {
            (
                &buffers.hir_nearest_fn_value_a,
                &buffers.hir_nearest_fn_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_fn_value_b,
                &buffers.hir_nearest_fn_value_a,
            )
        };
        let (nearest_loop_in, nearest_loop_out) = if read_from_a {
            (
                &buffers.hir_nearest_loop_value_a,
                &buffers.hir_nearest_loop_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_loop_value_b,
                &buffers.hir_nearest_loop_value_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirContextRelations".into(),
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
                "hir_stmt_context_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_contextual_stmt_value_in".into(),
                value_in.as_entire_binding(),
            ),
            (
                "hir_nearest_stmt_value_in".into(),
                nearest_value_in.as_entire_binding(),
            ),
            (
                "hir_nearest_block_value_in".into(),
                nearest_block_in.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_value_in".into(),
                nearest_control_in.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_value_in".into(),
                nearest_loop_in.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_value_in".into(),
                nearest_fn_in.as_entire_binding(),
            ),
            (
                "hir_stmt_context_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_contextual_stmt_value_out".into(),
                value_out.as_entire_binding(),
            ),
            (
                "hir_nearest_stmt_value_out".into(),
                nearest_value_out.as_entire_binding(),
            ),
            (
                "hir_nearest_block_value_out".into(),
                nearest_block_out.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_value_out".into(),
                nearest_control_out.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_value_out".into(),
                nearest_loop_out.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_value_out".into(),
                nearest_fn_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_context_relations_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_context_relations_step"),
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
