use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scatters propagated context relations into compact HIR records.
pub struct HirContextRelationsScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirContextRelationsScatterPass,
    label: "hir_context_relations_scatter",
    shader: "parser/hir/context/relations/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirContextRelationsScatterPass {
    const NAME: &'static str = "hir_context_relations_scatter";
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
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
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
                "hir_nearest_stmt_node".into(),
                b.hir_nearest_stmt_node.as_entire_binding(),
            ),
            (
                "hir_nearest_block_node".into(),
                b.hir_nearest_block_node.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_node".into(),
                b.hir_nearest_enclosing_control_node.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_node".into(),
                b.hir_nearest_loop_node.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_node".into(),
                b.hir_nearest_fn_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node".into(),
                b.hir_struct_lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_array_lit_context_stmt_node".into(),
                b.hir_array_lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_call_context_stmt_node".into(),
                b.hir_call_context_stmt_node.as_entire_binding(),
            ),
        ])
    }
}
