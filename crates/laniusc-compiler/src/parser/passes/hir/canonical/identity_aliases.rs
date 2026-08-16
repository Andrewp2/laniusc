use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalIdentityAliasesPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalIdentityAliasesPass,
    label: "hir_canonical_identity_aliases",
    shader: "parser/hir/canonical/identity_aliases"
);
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalIdentityAliasesPass {
    const NAME: &'static str = "hir_canonical_identity_aliases";
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
                "canonical_anchor_owner".into(),
                b.hir_canonical_anchor_owner.as_entire_binding(),
            ),
            (
                "canonical_raw_to_dense".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_alias_to_dense.as_entire_binding(),
            ),
        ])
    }
}
