use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that computes local enum declaration rank prefixes.
pub struct HirEnumRankPrefixLocalPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirEnumRankPrefixLocalPass,
    label: "hir_enum_rank_prefix_00_local",
    shader: "parser/hir/enum/rank/prefix_00_local"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirEnumRankPrefixLocalPass {
    const NAME: &'static str = "hir_enum_rank_prefix_00_local";
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
                "gHirEnum".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_enum_rank_flag".into(),
                b.hir_enum_rank_flag.as_entire_binding(),
            ),
            (
                "hir_enum_rank_local_prefix".into(),
                b.hir_enum_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_enum_rank_block_sum".into(),
                b.hir_enum_rank_block_sum.as_entire_binding(),
            ),
        ])
    }
}
