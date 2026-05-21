use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirSemanticDepthInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticDepthInitPass,
    label: "hir_semantic_depth_init",
    shader: "hir_semantic_depth_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticDepthInitPass {
    const NAME: &'static str = "hir_semantic_depth_init";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_link_a".into(),
                b.hir_semantic_depth_link_a.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_value_a".into(),
                b.hir_semantic_depth_value_a.as_entire_binding(),
            ),
        ])
    }
}
