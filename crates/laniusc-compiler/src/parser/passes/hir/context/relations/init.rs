use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that seeds HIR context relation propagation.
pub struct HirContextRelationsInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirContextRelationsInitPass,
    label: "hir_context_relations_init",
    shader: "parser/hir/context/relations/init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirContextRelationsInitPass {
    const NAME: &'static str = "hir_context_relations_init";
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
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_stmt_record".into(),
                b.hir_stmt_record.as_entire_binding(),
            ),
            (
                "hir_array_element_parent_lit".into(),
                b.hir_array_element_parent_lit.as_entire_binding(),
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
                "hir_nearest_array_element_value_a".into(),
                b.hir_nearest_array_element_value_a.as_entire_binding(),
            ),
        ])
    }
}
