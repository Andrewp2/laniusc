use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scatters ranked type arguments into owner-local compact ranges.
pub struct HirTypeArgScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeArgScatterPass,
    label: "hir_type_arg_scatter",
    shader: "parser/hir/type/arg/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeArgScatterPass {
    const NAME: &'static str = "hir_type_arg_scatter";
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
                "gHirType".into(),
                b.hir_type_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_type_arg_owner_a".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank_a".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_previous".into(),
                b.hir_type_arg_previous.as_entire_binding(),
            ),
            (
                "hir_type_arg_start".into(),
                b.hir_type_arg_start.as_entire_binding(),
            ),
            (
                "hir_type_arg_count".into(),
                b.hir_type_arg_count.as_entire_binding(),
            ),
            (
                "hir_type_arg_next".into(),
                b.hir_type_arg_next.as_entire_binding(),
            ),
        ])
    }
}
