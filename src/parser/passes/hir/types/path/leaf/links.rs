use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirTypePathLeafLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypePathLeafLinksPass,
    label: "hir_type_path_leaf_links",
    shader: "parser/hir/type/path/leaf/links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypePathLeafLinksPass {
    const NAME: &'static str = "hir_type_path_leaf_links";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            (
                "hir_type_path_leaf_link_a".into(),
                b.hir_type_path_leaf_link_a.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_value_a".into(),
                b.hir_type_path_leaf_value_a.as_entire_binding(),
            ),
        ])
    }
}
