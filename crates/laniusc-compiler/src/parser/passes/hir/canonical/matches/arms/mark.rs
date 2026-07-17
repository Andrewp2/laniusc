use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalMatchArmMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalMatchArmMarkPass, label: "hir_canonical_match_arm_mark", shader: "parser/hir/canonical/matches/arms/mark");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalMatchArmMarkPass {
    const NAME: &'static str = "hir_canonical_match_arm_mark";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "token_feature_flags".into(),
                b.token_feature_flags.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "arm_owner_match".into(),
                b.hir_match_payload_match_node.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_match_arm_family_flag.as_entire_binding(),
            ),
            (
                "raw_to_arm".into(),
                b.hir_match_arm_raw_to_row.as_entire_binding(),
            ),
        ])
    }
}
