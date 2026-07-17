use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalTypeArgScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalTypeArgScatterPass, label: "hir_canonical_type_arg_scatter", shader: "parser/hir/canonical/type_args/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalTypeArgScatterPass {
    const NAME: &'static str = "hir_canonical_type_arg_scatter";
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
                b.hir_type_arg_family_flag.as_entire_binding(),
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
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            (
                "hir_type_arg_owner".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_type_arg_table_count.as_entire_binding(),
            ),
            (
                "hir_type_args".into(),
                b.hir_type_arg_rows.as_entire_binding(),
            ),
            (
                "type_arg_ranges".into(),
                b.hir_type_arg_ranges.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
