use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that seeds function-signature owner links from HIR function syntax.
pub struct HirFnSignatureOwnerInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirFnSignatureOwnerInitPass,
    label: "hir_fn_signature_owner_init",
    shader: "parser/hir/fn/signature/owner/init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirFnSignatureOwnerInitPass {
    const NAME: &'static str = "hir_fn_signature_owner_init";
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
                "gHirFnSignatureOwner".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("parent".into(), b.parent.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_fn_signature_owner_link_a".into(),
                b.hir_fn_signature_owner_link_a.as_entire_binding(),
            ),
            (
                "hir_fn_signature_return_owner_a".into(),
                b.hir_fn_signature_return_owner_a.as_entire_binding(),
            ),
            (
                "hir_fn_signature_function_owner_a".into(),
                b.hir_fn_signature_function_owner_a.as_entire_binding(),
            ),
        ])
    }
}
