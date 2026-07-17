use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalPathSegmentScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalPathSegmentScatterPass, label: "hir_canonical_path_segment_scatter", shader: "parser/hir/canonical/paths/segments/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalPathSegmentScatterPass {
    const NAME: &'static str = "hir_canonical_path_segment_scatter";
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
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_path_segment_family_flag.as_entire_binding(),
            ),
            (
                "family_local_prefix".into(),
                b.hir_semantic_local_prefix.as_entire_binding(),
            ),
            (
                "family_block_prefix".into(),
                b.hir_semantic_block_prefix_a.as_entire_binding(),
            ),
            (
                "path_segment_owner".into(),
                b.hir_path_segment_owner_a.as_entire_binding(),
            ),
            (
                "path_segment_rank".into(),
                b.hir_path_segment_rank_a.as_entire_binding(),
            ),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_path_segment_table_count.as_entire_binding(),
            ),
            (
                "path_segments".into(),
                b.hir_path_segment_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
