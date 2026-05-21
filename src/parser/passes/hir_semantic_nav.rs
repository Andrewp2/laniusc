use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirSemanticNavPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticNavPass,
    label: "hir_semantic_nav",
    shader: "hir_semantic_nav"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticNavPass {
    const NAME: &'static str = "hir_semantic_nav";
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
                "hir_semantic_subtree_end".into(),
                b.hir_semantic_subtree_end.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_semantic_first_child".into(),
                b.hir_semantic_first_child.as_entire_binding(),
            ),
            (
                "hir_semantic_next_sibling".into(),
                b.hir_semantic_next_sibling.as_entire_binding(),
            ),
        ])
    }
}
