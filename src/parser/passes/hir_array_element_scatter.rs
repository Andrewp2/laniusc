use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirArrayElementScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirArrayElementScatterPass,
    label: "hir_array_element_scatter",
    shader: "hir_array_element_scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirArrayElementScatterPass {
    const NAME: &'static str = "hir_array_element_scatter";
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
                "gHirArray".into(),
                b.hir_array_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_array_element_owner_a".into(),
                b.hir_array_element_owner_a.as_entire_binding(),
            ),
            (
                "hir_array_element_rank_a".into(),
                b.hir_array_element_rank_a.as_entire_binding(),
            ),
            (
                "hir_array_element_previous".into(),
                b.hir_array_element_previous.as_entire_binding(),
            ),
            (
                "hir_array_lit_first_element".into(),
                b.hir_array_lit_first_element.as_entire_binding(),
            ),
            (
                "hir_array_lit_element_count".into(),
                b.hir_array_lit_element_count.as_entire_binding(),
            ),
            (
                "hir_array_element_parent_lit".into(),
                b.hir_array_element_parent_lit.as_entire_binding(),
            ),
            (
                "hir_array_element_ordinal".into(),
                b.hir_array_element_ordinal.as_entire_binding(),
            ),
            (
                "hir_array_element_next".into(),
                b.hir_array_element_next.as_entire_binding(),
            ),
        ])
    }
}
