use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalScatterPass,
    label: "hir_canonical_scatter",
    shader: "parser/hir/canonical/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalScatterPass {
    const NAME: &'static str = "hir_canonical_scatter";
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
                "canonical_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "canonical_local_prefix".into(),
                b.hir_semantic_local_prefix.as_entire_binding(),
            ),
            (
                "canonical_block_prefix".into(),
                b.hir_semantic_block_prefix_a.as_entire_binding(),
            ),
            (
                "canonical_prefix_before_raw".into(),
                b.hir_canonical_prefix_before_raw.as_entire_binding(),
            ),
            (
                "canonical_dense_to_raw".into(),
                b.hir_canonical_dense_to_raw.as_entire_binding(),
            ),
            (
                "canonical_raw_to_dense".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
            (
                "array_element_start".into(),
                b.hir_array_compact_element_start.as_entire_binding(),
            ),
            (
                "array_element_count".into(),
                b.hir_array_compact_element_count.as_entire_binding(),
            ),
            (
                "param_ranges".into(),
                b.hir_param_ranges.as_entire_binding(),
            ),
            (
                "type_arg_ranges".into(),
                b.hir_type_arg_ranges.as_entire_binding(),
            ),
            (
                "generic_param_ranges".into(),
                b.hir_generic_param_ranges.as_entire_binding(),
            ),
        ])
    }
}
