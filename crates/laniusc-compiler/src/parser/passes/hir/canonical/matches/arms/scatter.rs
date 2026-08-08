use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalMatchArmScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalMatchArmScatterPass, label: "hir_canonical_match_arm_scatter", shader: "parser/hir/canonical/matches/arms/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalMatchArmScatterPass {
    const NAME: &'static str = "hir_canonical_match_arm_scatter";
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
                b.hir_match_arm_family_flag.as_entire_binding(),
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
                b.hir_canonical_alias_to_dense.as_entire_binding(),
            ),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "expr_result_root".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "arm_owner_match".into(),
                b.hir_match_payload_match_node.as_entire_binding(),
            ),
            (
                "arm_pattern".into(),
                b.hir_match_arm_pattern_node.as_entire_binding(),
            ),
            (
                "arm_result".into(),
                b.hir_match_arm_result_node.as_entire_binding(),
            ),
            (
                "arm_ordinal".into(),
                b.hir_match_payload_ordinal.as_entire_binding(),
            ),
            (
                "raw_to_arm".into(),
                b.hir_match_arm_raw_to_row.as_entire_binding(),
            ),
            (
                "payload_start".into(),
                b.hir_match_compact_payload_start.as_entire_binding(),
            ),
            (
                "payload_count".into(),
                b.hir_match_compact_payload_count.as_entire_binding(),
            ),
            (
                "match_arm_range_words".into(),
                b.hir_match_arm_ranges.as_entire_binding(),
            ),
            (
                "match_pattern_to_arm".into(),
                b.hir_match_pattern_to_arm.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_match_arm_table_count.as_entire_binding(),
            ),
            (
                "hir_match_arms".into(),
                b.hir_match_arm_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
