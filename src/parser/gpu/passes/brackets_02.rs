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
    pub n_blocks: u32,
}

pub struct BracketsScanBlockPrefixPass {
    data: PassData,
}

impl BracketsScanBlockPrefixPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "brackets_02_scan_block_prefix",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_02_scan_block_prefix.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/brackets_02_scan_block_prefix.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for BracketsScanBlockPrefixPass {
    const NAME: &'static str = "brackets_02_scan_block_prefix";
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
            ("gParams".into(), b.b02_params.as_entire_binding()),
            ("block_sum".into(), b.b_block_sum.as_entire_binding()),
            (
                "block_minpref".into(),
                b.b_block_minpref.as_entire_binding(),
            ),
            ("block_prefix".into(), b.b_block_prefix.as_entire_binding()),
            ("out_depths".into(), b.depths_out.as_entire_binding()),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }
}
