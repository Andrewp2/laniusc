use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Seeds parallel nearest-match-arm propagation for nested patterns.
pub struct HirMatchArmOwnerInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmOwnerInitPass,
    label: "hir_match_arm_owner_init",
    shader: "parser/hir/match/arm/owner_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchArmOwnerInitPass {
    const NAME: &'static str = "hir_match_arm_owner_init";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
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
            (
                "hir_semantic_parent_link_a".into(),
                b.hir_semantic_parent_link_a.as_entire_binding(),
            ),
            (
                "hir_match_nearest_arm".into(),
                b.hir_match_pattern_owner_arm.as_entire_binding(),
            ),
        ])
    }
}
