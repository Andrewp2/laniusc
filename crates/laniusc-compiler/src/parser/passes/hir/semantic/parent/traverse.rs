use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Finds each dense semantic row's nearest semantic parent: the last earlier
/// row whose dense subtree end lies past it, searched in the semantic-end heaps.
pub struct HirSemanticParentTraversePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticParentTraversePass,
    label: "hir_semantic_parent_traverse",
    shader: "parser/hir/semantic/parent/traverse"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticParentTraversePass {
    const NAME: &'static str = "hir_semantic_parent_traverse";
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
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
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
                "hir_semantic_end_local_max".into(),
                b.hir_semantic_end_local_max.as_entire_binding(),
            ),
            (
                "hir_semantic_end_blocks".into(),
                b.hir_semantic_end_blocks.as_entire_binding(),
            ),
            (
                "hir_semantic_end_top".into(),
                b.hir_semantic_end_top.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
        ])
    }
}
