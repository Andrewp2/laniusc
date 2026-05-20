use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirSemanticDispatchArgsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticDispatchArgsPass,
    label: "hir_semantic_dispatch_args",
    shader: "hir_semantic_dispatch_args"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticDispatchArgsPass {
    const NAME: &'static str = "hir_semantic_dispatch_args";
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
                "gHirSemanticDispatch".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_dispatch_args".into(),
                b.hir_semantic_dispatch_args.as_entire_binding(),
            ),
        ])
    }
}
