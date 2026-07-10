use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Largest semantic-HIR capacity handled by one cooperative workgroup.
pub const HIR_CONTEXT_RELATIONS_SMALL_CAPACITY: u32 = 8192;

/// Cooperative small-table pointer-jump pass.
pub struct HirContextRelationsStepSmallPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirContextRelationsStepSmallPass,
    label: "hir_context_relations_step_small",
    shader: "parser/hir/context/relations/step_small"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirContextRelationsStepSmallPass {
    const NAME: &'static str = "hir_context_relations_step_small";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gHirContextRelations".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_stmt_context_link_a".into(),
                b.hir_stmt_context_link_a.as_entire_binding(),
            ),
            (
                "hir_contextual_stmt_value_a".into(),
                b.hir_contextual_stmt_value_a.as_entire_binding(),
            ),
            (
                "hir_nearest_stmt_value_a".into(),
                b.hir_nearest_stmt_value_a.as_entire_binding(),
            ),
            (
                "hir_nearest_block_value_a".into(),
                b.hir_nearest_block_value_a.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_value_a".into(),
                b.hir_nearest_enclosing_control_value_a.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_value_a".into(),
                b.hir_nearest_loop_value_a.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_value_a".into(),
                b.hir_nearest_fn_value_a.as_entire_binding(),
            ),
            (
                "hir_stmt_context_link_b".into(),
                b.hir_stmt_context_link_b.as_entire_binding(),
            ),
            (
                "hir_contextual_stmt_value_b".into(),
                b.hir_contextual_stmt_value_b.as_entire_binding(),
            ),
            (
                "hir_nearest_stmt_value_b".into(),
                b.hir_nearest_stmt_value_b.as_entire_binding(),
            ),
            (
                "hir_nearest_block_value_b".into(),
                b.hir_nearest_block_value_b.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_value_b".into(),
                b.hir_nearest_enclosing_control_value_b.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_value_b".into(),
                b.hir_nearest_loop_value_b.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_value_b".into(),
                b.hir_nearest_fn_value_b.as_entire_binding(),
            ),
        ])
    }
}
