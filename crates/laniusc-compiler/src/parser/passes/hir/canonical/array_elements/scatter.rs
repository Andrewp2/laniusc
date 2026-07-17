use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalArrayElementScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalArrayElementScatterPass, label: "hir_canonical_array_element_scatter", shader: "parser/hir/canonical/array_elements/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput>
    for HirCanonicalArrayElementScatterPass
{
    const NAME: &'static str = "hir_canonical_array_element_scatter";
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
                b.hir_array_element_family_flag.as_entire_binding(),
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
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_anchor_owner".into(),
                b.hir_canonical_anchor_owner.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            (
                "expr_result_root".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "element_owner".into(),
                b.hir_array_element_parent_lit.as_entire_binding(),
            ),
            (
                "element_ordinal".into(),
                b.hir_array_element_ordinal.as_entire_binding(),
            ),
            (
                "array_element_start".into(),
                b.hir_array_compact_element_start.as_entire_binding(),
            ),
            (
                "array_element_count".into(),
                b.hir_array_compact_element_count.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_array_element_table_count.as_entire_binding(),
            ),
            (
                "hir_array_elements".into(),
                b.hir_array_element_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
