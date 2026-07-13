use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that links match arm nodes to their owning match expression.
pub struct HirMatchArmLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmLinksPass,
    label: "hir_match_arm_links",
    shader: "parser/hir/match/arm/links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchArmLinksPass {
    const NAME: &'static str = "hir_match_arm_links";
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
                "gHirMatch".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
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
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_match_scrutinee_node".into(),
                b.hir_match_scrutinee_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_pattern_node".into(),
                b.hir_match_arm_pattern_node.as_entire_binding(),
            ),
            (
                "hir_match_pattern_owner_arm".into(),
                b.hir_match_pattern_owner_arm.as_entire_binding(),
            ),
            (
                "hir_match_arm_result_node".into(),
                b.hir_match_arm_result_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_a".into(),
                b.hir_match_arm_owner_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_a".into(),
                b.hir_match_arm_link_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_a".into(),
                b.hir_match_arm_rank_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_previous".into(),
                b.hir_match_arm_previous.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_a".into(),
                b.hir_match_payload_owner_a.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_a".into(),
                b.hir_match_payload_link_a.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_a".into(),
                b.hir_match_payload_rank_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_b".into(),
                b.hir_match_arm_owner_b.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_b".into(),
                b.hir_match_arm_link_b.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_b".into(),
                b.hir_match_arm_rank_b.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_b".into(),
                b.hir_match_payload_owner_b.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_b".into(),
                b.hir_match_payload_link_b.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_b".into(),
                b.hir_match_payload_rank_b.as_entire_binding(),
            ),
        ])
    }
}
