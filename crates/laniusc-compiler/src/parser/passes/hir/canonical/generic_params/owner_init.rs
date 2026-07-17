use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalGenericParamOwnerInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalGenericParamOwnerInitPass,
    label: "hir_canonical_generic_param_owner_init",
    shader: "parser/hir/canonical/generic_params/owner_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput>
    for HirCanonicalGenericParamOwnerInitPass
{
    const NAME: &'static str = "hir_canonical_generic_param_owner_init";
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
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_generic_param_family_flag.as_entire_binding(),
            ),
            (
                "owner_link_a".into(),
                b.hir_semantic_parent_link_a.as_entire_binding(),
            ),
            (
                "owner_value_a".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
        ])
    }
}
