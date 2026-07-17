use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalGenericParamFinalizePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalGenericParamFinalizePass,
    label: "hir_canonical_generic_param_finalize",
    shader: "parser/hir/canonical/generic_params/finalize"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput>
    for HirCanonicalGenericParamFinalizePass
{
    const NAME: &'static str = "hir_canonical_generic_param_finalize";
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
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "owner_value".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_generic_param_family_flag.as_entire_binding(),
            ),
        ])
    }
}
