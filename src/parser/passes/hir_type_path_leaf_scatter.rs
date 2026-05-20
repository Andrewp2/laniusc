use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirTypePathLeafScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypePathLeafScatterPass,
    label: "hir_type_path_leaf_scatter",
    shader: "hir_type_path_leaf_scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypePathLeafScatterPass {
    const NAME: &'static str = "hir_type_path_leaf_scatter";
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
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_type_value_node".into(),
                b.hir_type_value_node.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_value_a".into(),
                b.hir_type_path_leaf_value_a.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_node".into(),
                b.hir_type_path_leaf_node.as_entire_binding(),
            ),
            (
                "hir_type_path_owner_by_leaf".into(),
                b.hir_type_path_leaf_link_b.as_entire_binding(),
            ),
        ])
    }
}
