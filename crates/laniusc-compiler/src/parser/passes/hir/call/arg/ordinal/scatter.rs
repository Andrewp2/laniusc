use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scatters call argument ordinals and compact argument ranges.
pub struct HirCallArgOrdinalScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCallArgOrdinalScatterPass,
    label: "hir_call_arg_ordinal_scatter",
    shader: "parser/hir/call/arg/ordinal/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCallArgOrdinalScatterPass {
    const NAME: &'static str = "hir_call_arg_ordinal_scatter";
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
                "gHirCall".into(),
                b.hir_call_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_call_arg_owner_a".into(),
                b.hir_call_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_call_arg_rank_a".into(),
                b.hir_call_arg_rank_a.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call".into(),
                b.hir_call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal".into(),
                b.hir_call_arg_ordinal.as_entire_binding(),
            ),
            (
                "hir_call_arg_count".into(),
                b.hir_call_arg_count.as_entire_binding(),
            ),
        ])
    }
}
