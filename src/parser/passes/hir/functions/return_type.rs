use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirFnReturnTypePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirFnReturnTypePass,
    label: "hir_fn_return_type",
    shader: "parser/hir/fn/return_type"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirFnReturnTypePass {
    const NAME: &'static str = "hir_fn_return_type";
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
            ("gHirFnReturnType".into(), b.hir_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_fn_signature_return_owner".into(),
                b.hir_fn_signature_return_owner_a.as_entire_binding(),
            ),
            (
                "hir_fn_signature_function_owner".into(),
                b.hir_fn_signature_function_owner_a.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node".into(),
                b.hir_fn_return_type_node.as_entire_binding(),
            ),
        ])
    }
}
