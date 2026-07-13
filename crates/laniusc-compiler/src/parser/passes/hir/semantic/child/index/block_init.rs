use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Compresses bounded previous-sibling blocks before global pointer jumping.
pub struct HirSemanticChildIndexBlockInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexBlockInitPass,
    label: "hir_semantic_child_index_block_init",
    shader: "parser/hir/semantic/child/index/block_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexBlockInitPass {
    const NAME: &'static str = "hir_semantic_child_index_block_init";
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
                "hir_semantic_child_index_link_in".into(),
                b.hir_semantic_child_index_link_a.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_in".into(),
                b.hir_semantic_child_index_rank_a.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_link_out".into(),
                b.hir_semantic_child_index_link_b.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_out".into(),
                b.hir_semantic_child_index_rank_b.as_entire_binding(),
            ),
        ])
    }
}
