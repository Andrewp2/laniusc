use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that compacts semantic HIR nodes into dense semantic-node arrays.
pub struct HirSemanticCompactScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticCompactScatterPass,
    label: "hir_semantic_compact_scatter",
    shader: "parser/hir/semantic/compact_scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticCompactScatterPass {
    const NAME: &'static str = "hir_semantic_compact_scatter";
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
            (
                "hir_semantic_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "hir_semantic_local_prefix".into(),
                b.hir_semantic_local_prefix.as_entire_binding(),
            ),
            (
                "hir_semantic_block_prefix".into(),
                b.hir_semantic_block_prefix_a.as_entire_binding(),
            ),
            (
                "hir_node_dense_id".into(),
                b.hir_node_dense_id.as_entire_binding(),
            ),
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
        ])
    }
}
