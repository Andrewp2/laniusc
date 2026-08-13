use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Computes each semantic row's sibling index with a local predecessor walk.
pub struct HirSemanticChildIndexTraversePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexTraversePass,
    label: "hir_semantic_child_index_traverse",
    shader: "parser/hir/semantic/child/index/traverse"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexTraversePass {
    const NAME: &'static str = "hir_semantic_child_index_traverse";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
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
                "hir_semantic_first_child".into(),
                b.hir_semantic_first_child.as_entire_binding(),
            ),
            (
                "hir_semantic_next_sibling".into(),
                b.hir_semantic_next_sibling.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index".into(),
                b.hir_semantic_child_index.as_entire_binding(),
            ),
        ])
    }
}
