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
    pub n_layers: u32,
}

pub struct BracketsScanHistogramsPass {
    data: PassData,
}

impl BracketsScanHistogramsPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "brackets_05_scan_histograms",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_05_scan_histograms.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_05_scan_histograms.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for BracketsScanHistogramsPass {
    const NAME: &'static str = "brackets_05_scan_histograms";
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
            ("gParams".into(), b.b05_params.as_entire_binding()),
            ("hist_push".into(), b.b_hist_push.as_entire_binding()),
            ("hist_pop".into(), b.b_hist_pop.as_entire_binding()),
            ("off_push".into(), b.b_off_push.as_entire_binding()),
            ("off_pop".into(), b.b_off_pop.as_entire_binding()),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }
}
