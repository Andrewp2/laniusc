use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalVariantScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalVariantScatterPass, label: "hir_canonical_variant_scatter", shader: "parser/hir/canonical/variants/scatter");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalVariantScatterPass {
    const NAME: &'static str = "hir_canonical_variant_scatter";
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
                b.hir_variant_family_flag.as_entire_binding(),
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
                "variant_parent_enum".into(),
                b.hir_variant_parent_enum.as_entire_binding(),
            ),
            (
                "variant_ordinal".into(),
                b.hir_variant_ordinal.as_entire_binding(),
            ),
            (
                "raw_to_variant".into(),
                b.hir_variant_raw_to_row.as_entire_binding(),
            ),
            (
                "variant_payload_start".into(),
                b.hir_variant_compact_payload_start.as_entire_binding(),
            ),
            (
                "variant_payload_count".into(),
                b.hir_variant_compact_payload_count.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_variant_table_count.as_entire_binding(),
            ),
            (
                "hir_variants".into(),
                b.hir_variant_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
