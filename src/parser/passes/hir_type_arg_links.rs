use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirTypeArgLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeArgLinksPass,
    label: "hir_type_arg_links",
    shader: "hir_type_arg_links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeArgLinksPass {
    const NAME: &'static str = "hir_type_arg_links";
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
                "gHirType".into(),
                b.hir_type_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_type_path_leaf_node".into(),
                b.hir_type_path_leaf_node.as_entire_binding(),
            ),
            (
                "hir_type_path_owner_by_leaf".into(),
                b.hir_type_path_leaf_link_b.as_entire_binding(),
            ),
            (
                "hir_type_arg_owner_a".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_link_a".into(),
                b.hir_type_arg_link_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank_a".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_previous".into(),
                b.hir_type_arg_previous.as_entire_binding(),
            ),
        ])
    }
}
