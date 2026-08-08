use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalFieldScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalFieldScatterPass,
    label: "hir_canonical_field_scatter",
    shader: "parser/hir/canonical/fields/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalFieldScatterPass {
    const NAME: &'static str = "hir_canonical_field_scatter";
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
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_field_family_flag.as_entire_binding(),
            ),
            (
                "family_local_prefix".into(),
                b.hir_semantic_local_prefix.as_entire_binding(),
            ),
            (
                "family_block_prefix".into(),
                b.hir_semantic_block_prefix_a.as_entire_binding(),
            ),
            (
                "alias_to_hir".into(),
                b.hir_canonical_alias_to_dense.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "decl_owner".into(),
                b.hir_struct_field_parent_struct.as_entire_binding(),
            ),
            (
                "decl_ordinal".into(),
                b.hir_struct_field_ordinal.as_entire_binding(),
            ),
            (
                "decl_type".into(),
                b.hir_struct_field_type_node.as_entire_binding(),
            ),
            (
                "literal_owner".into(),
                b.hir_struct_lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "literal_ordinal".into(),
                b.hir_struct_lit_field_rank_a.as_entire_binding(),
            ),
            (
                "literal_value".into(),
                b.hir_struct_lit_field_value_node.as_entire_binding(),
            ),
            (
                "expr_result_root".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_field_table_count.as_entire_binding(),
            ),
            ("hir_fields".into(), b.hir_field_rows.as_entire_binding()),
            (
                "field_range_words".into(),
                b.hir_match_arm_ranges.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
