use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirMatchRankCompactScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchRankCompactScatterPass,
    label: "hir_match_rank_compact_scatter",
    shader: "hir_match_rank_compact_scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchRankCompactScatterPass {
    const NAME: &'static str = "hir_match_rank_compact_scatter";
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
                "gHirMatch".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_match_rank_flag".into(),
                b.hir_match_rank_flag.as_entire_binding(),
            ),
            (
                "hir_match_rank_local_prefix".into(),
                b.hir_match_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_match_rank_block_prefix".into(),
                b.hir_match_rank_block_prefix_a.as_entire_binding(),
            ),
            (
                "hir_match_rank_node".into(),
                b.hir_match_rank_node.as_entire_binding(),
            ),
            (
                "hir_match_rank_count".into(),
                b.hir_match_rank_count.as_entire_binding(),
            ),
            (
                "hir_match_rank_dispatch_args".into(),
                b.hir_match_rank_dispatch_args.as_entire_binding(),
            ),
        ])
    }
}
