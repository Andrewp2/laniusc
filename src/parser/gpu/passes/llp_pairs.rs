use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use super::Pass;
use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    parser::gpu::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct LLPParams {
    pub n_tokens: u32,
    pub n_kinds: u32,
}

pub struct LLPPairsPass {
    data: PassData,
}

impl LLPPairsPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        // Built by build.rs into OUT_DIR/shaders
        let spirv = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/llp_pairs.spv"));
        let reflect = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/llp_pairs.reflect.json"));

        let data =
            crate::gpu::passes_core::make_pass_data(device, "llp_pairs", "main", spirv, reflect)?;

        Ok(Self { data })
    }
}

impl Pass for LLPPairsPass {
    const NAME: &'static str = "llp_pairs";
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
    ) -> std::collections::HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "token_kinds".into(),
                buffers.token_kinds.as_entire_binding(),
            ),
            (
                "action_table".into(),
                buffers.action_table.as_entire_binding(),
            ),
            (
                "out_headers".into(),
                buffers.out_headers.as_entire_binding(),
            ),
            ("Params".into(), buffers.params_llp.as_entire_binding()),
        ])
    }
}
