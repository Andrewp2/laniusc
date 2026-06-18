use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that maps source-tree subtree ends into dense semantic-node ranges.
pub struct HirSemanticSubtreeEndPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticSubtreeEndPass,
    label: "hir_semantic_subtree_end",
    shader: "parser/hir/semantic/subtree_end"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticSubtreeEndPass {
    const NAME: &'static str = "hir_semantic_subtree_end";
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
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            (
                "hir_semantic_prefix_before_node".into(),
                b.hir_semantic_prefix_before_node.as_entire_binding(),
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
        ])
    }
}
