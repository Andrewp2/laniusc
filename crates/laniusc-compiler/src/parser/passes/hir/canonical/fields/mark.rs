use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalFieldMarkPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalFieldMarkPass,
    label: "hir_canonical_field_mark",
    shader: "parser/hir/canonical/fields/mark"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalFieldMarkPass {
    const NAME: &'static str = "hir_canonical_field_mark";
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
                "decl_owner".into(),
                b.hir_struct_field_parent_struct.as_entire_binding(),
            ),
            (
                "literal_owner".into(),
                b.hir_struct_lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_field_family_flag.as_entire_binding(),
            ),
        ])
    }
}
