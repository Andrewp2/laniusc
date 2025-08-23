use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
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

impl BracketsHistogramLayersPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "brackets_04_histogram_layers",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_04_histogram_layers.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_04_histogram_layers.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for BracketsHistogramLayersPass {
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
        ])
    }
}
