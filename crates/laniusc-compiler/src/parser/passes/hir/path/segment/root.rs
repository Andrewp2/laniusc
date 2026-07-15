use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirPathSegmentRootPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirPathSegmentRootPass, label: "hir_path_segment_root", shader: "parser/hir/path/segment/root");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirPathSegmentRootPass {
    const NAME: &'static str = "hir_path_segment_root";
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
                "gHirPath".into(),
                b.hir_type_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_type_value_node".into(),
                b.hir_type_value_node.as_entire_binding(),
            ),
            (
                "hir_item_path_node".into(),
                b.hir_item_path_node.as_entire_binding(),
            ),
            (
                "hir_path_root_owner".into(),
                b.hir_path_root_owner.as_entire_binding(),
            ),
            (
                "hir_path_segment_owner_a".into(),
                b.hir_path_segment_owner_a.as_entire_binding(),
            ),
            (
                "hir_path_segment_rank_a".into(),
                b.hir_path_segment_rank_a.as_entire_binding(),
            ),
            (
                "hir_path_segment_count".into(),
                b.hir_path_segment_count.as_entire_binding(),
            ),
        ])
    }
}
