use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that computes local match expression rank prefixes.
pub struct HirMatchRankPrefixLocalPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchRankPrefixLocalPass,
    label: "hir_match_rank_prefix_00_local",
    shader: "parser/hir/match/rank/prefix_00_local"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchRankPrefixLocalPass {
    const NAME: &'static str = "hir_match_rank_prefix_00_local";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "hir_match_rank_flag".into(),
                b.hir_match_rank_flag.as_entire_binding(),
            ),
            (
                "hir_match_rank_local_prefix".into(),
                b.hir_match_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_match_rank_block_sum".into(),
                b.hir_match_rank_block_sum.as_entire_binding(),
            ),
        ])
    }
}
