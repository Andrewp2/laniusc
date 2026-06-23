use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scatters ranked struct fields into struct-local ranges.
pub struct HirStructFieldScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStructFieldScatterPass,
    label: "hir_struct_field_scatter",
    shader: "parser/hir/struct/field/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStructFieldScatterPass {
    const NAME: &'static str = "hir_struct_field_scatter";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "hir_struct_field_owner_a".into(),
                b.hir_struct_field_owner_a.as_entire_binding(),
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
                "hir_struct_lit_field_rank_a".into(),
                b.hir_struct_lit_field_rank_a.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_previous".into(),
                b.hir_struct_lit_field_previous.as_entire_binding(),
            ),
            (
                "hir_struct_field_parent_struct".into(),
                b.hir_struct_field_parent_struct.as_entire_binding(),
            ),
            (
                "hir_struct_field_ordinal".into(),
                b.hir_struct_field_ordinal.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_start".into(),
                b.hir_struct_decl_field_start.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_count".into(),
                b.hir_struct_decl_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_start".into(),
                b.hir_struct_lit_field_start.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_count".into(),
                b.hir_struct_lit_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit".into(),
                b.hir_struct_lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_next".into(),
                b.hir_struct_lit_field_next.as_entire_binding(),
            ),
        ])
    }
}
