use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalVariantMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalVariantMarkPass, label: "hir_canonical_variant_mark", shader: "parser/hir/canonical/variants/mark");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalVariantMarkPass {
    const NAME: &'static str = "hir_canonical_variant_mark";
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
                "variant_parent_enum".into(),
                b.hir_variant_parent_enum.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_variant_family_flag.as_entire_binding(),
            ),
            (
                "raw_to_variant".into(),
                b.hir_variant_raw_to_row.as_entire_binding(),
            ),
        ])
    }
}
