use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalMatchArmLocalPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalMatchArmLocalPass, label: "hir_canonical_match_arm_local", shader: "parser/hir/canonical/matches/arms/local");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalMatchArmLocalPass {
    const NAME: &'static str = "hir_canonical_match_arm_local";
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
                "family_block_sum".into(),
                b.hir_semantic_block_count.as_entire_binding(),
            ),
        ])
    }
}
