use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that propagates context relations through HIR parents.
pub struct HirContextRelationsStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_context_relations_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_context_relations_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_context_relations_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_context_relations_step.finalize";

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
        read_from_a: bool,
        final_unpaired_step: bool,
        cache: &mut BindGroupCache,
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
        let (nearest_array_element_in, nearest_array_element_out) = if read_from_a {
            (
                &buffers.hir_nearest_array_element_value_a,
                &buffers.hir_nearest_array_element_value_b,
            )
        } else {
            (
                &buffers.hir_nearest_array_element_value_b,
                &buffers.hir_nearest_array_element_value_a,
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
                    buffers.partial_parse_status.as_entire_binding()
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
                "hir_nearest_array_element_value_in".into(),
                nearest_array_element_in.as_entire_binding(),
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
            (
                "hir_nearest_array_element_value_out".into(),
                nearest_array_element_out.as_entire_binding(),
            ),
        ]);

        let label = if final_unpaired_step {
            A_TO_B_FINAL
        } else if read_from_a {
            A_TO_B
        } else {
            B_TO_A
        };
        let invocation = format!("{label}.{step}");
        let dispatch_args = &buffers.hir_semantic_relation_dispatch_args;
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
            .expect("context-relation step must have one reflected bind group");

        crate::gpu::passes_core::record_or_defer_compute_indirect_offset(
            encoder,
            &self.data,
            bind_group.as_ref(),
            label,
            dispatch_args,
            u64::from(step) * 3 * std::mem::size_of::<u32>() as u64,
        );
        Ok(())
    }

    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}
