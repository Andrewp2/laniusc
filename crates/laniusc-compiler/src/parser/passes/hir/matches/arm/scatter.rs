use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirMatchArmScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmScatterPass,
    label: "hir_match_arm_scatter",
    shader: "parser/hir/match/arm/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchArmScatterPass {
    const NAME: &'static str = "hir_match_arm_scatter";
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
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "hir_match_arm_owner_a".into(),
                b.hir_match_arm_owner_a.as_entire_binding(),
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
                "hir_match_payload_rank_a".into(),
                b.hir_match_payload_rank_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_start".into(),
                b.hir_match_arm_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_count".into(),
                b.hir_match_arm_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_next".into(),
                b.hir_match_arm_next.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_start".into(),
                b.hir_match_arm_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_count".into(),
                b.hir_match_arm_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_arm".into(),
                b.hir_match_payload_owner_arm.as_entire_binding(),
            ),
            (
                "hir_match_payload_match_node".into(),
                b.hir_match_payload_match_node.as_entire_binding(),
            ),
            (
                "hir_match_payload_ordinal".into(),
                b.hir_match_payload_ordinal.as_entire_binding(),
            ),
        ])
    }
}
