use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirSemanticChildIndexLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexLinksPass,
    label: "hir_semantic_child_index_links",
    shader: "parser/hir/semantic/child/index/links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexLinksPass {
    const NAME: &'static str = "hir_semantic_child_index_links";
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
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_next_sibling".into(),
                b.hir_semantic_next_sibling.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_link_a".into(),
                b.hir_semantic_child_index_link_a.as_entire_binding(),
            ),
            (
                "hir_semantic_child_index_rank_a".into(),
                b.hir_semantic_child_index_rank_a.as_entire_binding(),
            ),
        ])
    }
}
