use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct TokensFileIdsPass {
    data: PassData,
}

impl TokensFileIdsPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tokens_file_ids",
            "tokens_file_ids",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/tokens_file_ids.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tokens_file_ids.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for TokensFileIdsPass {
    const NAME: &'static str = "tokens_file_ids";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a GpuBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            ("token_count".into(), b.token_count.as_entire_binding()),
            ("tokens_out".into(), b.tokens_out.as_entire_binding()),
            (
                "source_file_count".into(),
                b.source_file_count.as_entire_binding(),
            ),
            (
                "source_file_start".into(),
                b.source_file_start.as_entire_binding(),
            ),
            (
                "source_file_len".into(),
                b.source_file_len.as_entire_binding(),
            ),
            ("token_file_id".into(), b.token_file_id.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _b: &GpuBuffers,
        _dbg: &mut DebugOutput,
    ) {
    }
}
