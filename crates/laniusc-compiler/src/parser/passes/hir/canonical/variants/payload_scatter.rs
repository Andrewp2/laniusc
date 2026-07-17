use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalVariantPayloadScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalVariantPayloadScatterPass, label: "hir_canonical_variant_payload_scatter", shader: "parser/hir/canonical/variants/payload_scatter");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput>
    for HirCanonicalVariantPayloadScatterPass
{
    const NAME: &'static str = "hir_canonical_variant_payload_scatter";
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
                b.hir_variant_payload_family_flag.as_entire_binding(),
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
                "payload_owner_raw".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
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
                b.hir_variant_payload_table_count.as_entire_binding(),
            ),
            (
                "hir_variant_payloads".into(),
                b.hir_variant_payload_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
