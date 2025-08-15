use std::collections::HashMap;

use anyhow::Result;

use super::Pass;
use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    parser::gpu::buffers::ParserBuffers,
};

pub struct PackVarlenPass {
    data: PassData,
}

impl PackVarlenPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        // Built by build.rs into OUT_DIR/shaders
        let spirv = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/pack_varlen.spv"));
        let reflect = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/pack_varlen.reflect.json"
        ));

        let data =
            crate::gpu::passes_core::make_pass_data(device, "pack_varlen", "main", spirv, reflect)?;

        Ok(Self { data })
    }
}

impl Pass for PackVarlenPass {
    const NAME: &'static str = "pack_varlen";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        buffers: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        // TODO: replace with actual bindings

        HashMap::from([
            ("input_data".into(), buffers.input_data.as_entire_binding()),
            (
                "output_data".into(),
                buffers.output_data.as_entire_binding(),
            ),
        ])
    }
}
