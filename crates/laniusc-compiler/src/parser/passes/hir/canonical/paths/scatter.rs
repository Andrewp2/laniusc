use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalPathScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalPathScatterPass, label: "hir_canonical_path_scatter", shader: "parser/hir/canonical/paths/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalPathScatterPass {
    const NAME: &'static str = "hir_canonical_path_scatter";
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
                b.hir_path_family_flag.as_entire_binding(),
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
                "segment_table_count".into(),
                b.hir_path_segment_table_count.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "segment_count_by_raw_owner".into(),
                b.hir_path_segment_count.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "family_count".into(),
                b.hir_path_table_count.as_entire_binding(),
            ),
            ("paths".into(), b.hir_path_rows.as_entire_binding()),
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
