use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that records whether method signatures contain generic or where clauses.
pub struct HirMethodSignatureStatusPass {
    data: PassData,
}

/// Status bit set when a method signature contains generic parameters.
pub const HIR_METHOD_SIGNATURE_HAS_GENERICS: u32 = 1;
/// Status bit set when a method signature contains a where clause.
pub const HIR_METHOD_SIGNATURE_HAS_WHERE: u32 = 2;

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMethodSignatureStatusPass,
    label: "hir_method_signature_status",
    shader: "parser/hir/method/signature_status"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMethodSignatureStatusPass {
    const NAME: &'static str = "hir_method_signature_status";
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
                "gHirMethodSignatureStatus".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_fn_signature_function_owner".into(),
                b.hir_fn_signature_function_owner_a.as_entire_binding(),
            ),
            (
                "hir_method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
        ])
    }
}
