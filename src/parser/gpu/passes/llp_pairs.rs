use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
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
        let spirv = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/llp_pairs.spv"));
        let reflect = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/llp_pairs.reflect.json"));
        let data =
            crate::gpu::passes_core::make_pass_data(device, "llp_pairs", "main", spirv, reflect)?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for LLPPairsPass {
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
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            ("token_kinds".into(), b.token_kinds.as_entire_binding()),
            ("action_table".into(), b.action_table.as_entire_binding()),
            ("out_headers".into(), b.out_headers.as_entire_binding()),
            ("gParams".into(), b.params_llp.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        dbg: &mut crate::parser::gpu::debug::DebugOutput,
    ) {
        dbg.gpu.out_headers.set_from_copy(
            device,
            encoder,
            &b.out_headers,
            "parser.dbg.out_headers",
            b.out_headers.byte_size,
        );
    }
}
