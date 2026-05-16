use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_sc: u32,
    pub n_layers: u32,
}

pub struct BracketsScatterByLayerPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsScatterByLayerPass,
    label: "brackets_06_scatter_by_layer",
    shader: "brackets_06_scatter_by_layer"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsScatterByLayerPass {
    const NAME: &'static str = "brackets_06_scatter_by_layer";
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
            ("gParams".into(), b.b06_params.as_entire_binding()),
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            ("layer".into(), b.b_layer.as_entire_binding()),
            ("off_push".into(), b.b_off_push.as_entire_binding()),
            ("off_pop".into(), b.b_off_pop.as_entire_binding()),
            ("cur_push".into(), b.b_cur_push.as_entire_binding()),
            ("cur_pop".into(), b.b_cur_pop.as_entire_binding()),
            (
                "pushes_by_layer".into(),
                b.b_pushes_by_layer.as_entire_binding(),
            ),
            (
                "pops_by_layer".into(),
                b.b_pops_by_layer.as_entire_binding(),
            ),
            (
                "slot_for_index".into(),
                b.b_slot_for_index.as_entire_binding(),
            ),
        ])
    }
}
