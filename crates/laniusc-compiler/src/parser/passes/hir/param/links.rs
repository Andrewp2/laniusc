use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that seeds parameter ownership from the semantic HIR tree.
pub struct HirParamLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirParamLinksPass,
    label: "hir_param_links",
    shader: "parser/hir/param/links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirParamLinksPass {
    const NAME: &'static str = "hir_param_links";
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
                "gHirParam".into(),
                b.hir_param_fields_params.as_entire_binding(),
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
            (
                "hir_node_dense_id".into(),
                b.hir_node_dense_id.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_param_owner_a".into(),
                b.hir_param_owner_a.as_entire_binding(),
            ),
            (
                "hir_param_link_a".into(),
                b.hir_param_link_a.as_entire_binding(),
            ),
        ])
    }
}
