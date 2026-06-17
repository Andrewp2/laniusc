use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirParamIdClearPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirParamIdClearPass,
    label: "hir_param_id_clear",
    shader: "parser/hir/param/id_clear"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirParamIdClearPass {
    const NAME: &'static str = "hir_param_id_clear";
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
                "hir_param_rank_b".into(),
                b.hir_param_rank_b.as_entire_binding(),
            ),
        ])
    }
}
