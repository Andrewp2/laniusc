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

pub struct BracketsHistogramLayersPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsHistogramLayersPass,
    label: "brackets_04_histogram_layers",
    shader: "brackets_04_histogram_layers"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsHistogramLayersPass {
    const NAME: &'static str = "brackets_04_histogram_layers";
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
            ("gParams".into(), b.b04_params.as_entire_binding()),
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            ("layer".into(), b.b_layer.as_entire_binding()),
            ("hist_push".into(), b.b_hist_push.as_entire_binding()),
            ("hist_pop".into(), b.b_hist_pop.as_entire_binding()),
            (
                "match_for_index".into(),
                b.match_for_index.as_entire_binding(),
            ),
        ])
    }
}
