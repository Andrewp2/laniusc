use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalArrayElementMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalArrayElementMarkPass, label: "hir_canonical_array_element_mark", shader: "parser/hir/canonical/array_elements/mark");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalArrayElementMarkPass {
    const NAME: &'static str = "hir_canonical_array_element_mark";
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
            (
                "element_owner".into(),
                b.hir_array_element_parent_lit.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_array_element_family_flag.as_entire_binding(),
            ),
        ])
    }
}
