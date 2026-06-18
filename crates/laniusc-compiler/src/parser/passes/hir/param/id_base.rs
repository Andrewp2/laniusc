use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that seeds base parameter IDs for each parameter-owning list.
pub struct HirParamIdBasePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirParamIdBasePass,
    label: "hir_param_id_base",
    shader: "parser/hir/param/id_base"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirParamIdBasePass {
    const NAME: &'static str = "hir_param_id_base";
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
                "gHirParam".into(),
                b.hir_param_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_param_owner_a".into(),
                b.hir_param_owner_a.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".into(),
                b.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                b.hir_list_rank_count.as_entire_binding(),
            ),
            (
                "hir_param_rank_b".into(),
                b.hir_param_rank_b.as_entire_binding(),
            ),
        ])
    }
}
