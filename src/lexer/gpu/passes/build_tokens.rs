use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct BuildTokensPass {
    data: PassData,
}
impl BuildTokensPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "build_tokens",
            "build_tokens",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/build_tokens.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/build_tokens.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for BuildTokensPass {
    const NAME: &'static str = "build_tokens";
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
            ("end_positions".into(), b.end_positions.as_entire_binding()),
            ("types_compact".into(), b.types_compact.as_entire_binding()),
            (
                "all_index_compact".into(),
                b.all_index_compact.as_entire_binding(),
            ),
            (
                "end_positions_all".into(),
                b.end_positions_all.as_entire_binding(),
            ),
            ("tokens_out".into(), b.tokens_out.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.tokens_out.set_from_copy(
            device,
            encoder,
            &b.tokens_out,
            "dbg.tokens_out",
            b.tokens_out.byte_size,
        );
    }
}
