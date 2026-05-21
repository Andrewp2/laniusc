use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirStructFieldLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStructFieldLinksPass,
    label: "hir_struct_field_links",
    shader: "hir_struct_field_links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStructFieldLinksPass {
    const NAME: &'static str = "hir_struct_field_links";
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
                "gHirStruct".into(),
                b.hir_struct_fields_params.as_entire_binding(),
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
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_struct_field_type_node".into(),
                b.hir_struct_field_type_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_head_node".into(),
                b.hir_struct_lit_head_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_value_node".into(),
                b.hir_struct_lit_field_value_node.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_a".into(),
                b.hir_struct_field_owner_a.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_a".into(),
                b.hir_struct_field_link_a.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_a".into(),
                b.hir_struct_field_rank_a.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_a".into(),
                b.hir_struct_lit_field_owner_a.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_a".into(),
                b.hir_struct_lit_field_link_a.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_a".into(),
                b.hir_struct_lit_field_rank_a.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_previous".into(),
                b.hir_struct_lit_field_previous.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_b".into(),
                b.hir_struct_field_owner_b.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_b".into(),
                b.hir_struct_field_link_b.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_b".into(),
                b.hir_struct_field_rank_b.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_b".into(),
                b.hir_struct_lit_field_owner_b.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_b".into(),
                b.hir_struct_lit_field_link_b.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_b".into(),
                b.hir_struct_lit_field_rank_b.as_entire_binding(),
            ),
        ])
    }
}
