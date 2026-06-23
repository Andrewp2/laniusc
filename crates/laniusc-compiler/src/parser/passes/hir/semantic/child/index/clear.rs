use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that clears semantic child-index intermediate and output rows.
pub struct HirSemanticChildIndexClearPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexClearPass,
    label: "hir_semantic_child_index_clear",
    shader: "parser/hir/semantic/child/index/clear"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexClearPass {
    const NAME: &'static str = "hir_semantic_child_index_clear";
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
                "hir_semantic_child_index_link_a".into(),
                b.hir_semantic_child_index_link_a.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_a".into(),
                b.hir_semantic_child_index_rank_a.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index".into(),
                b.hir_semantic_child_index.as_entire_binding(),
            ),
        ])
    }
}
