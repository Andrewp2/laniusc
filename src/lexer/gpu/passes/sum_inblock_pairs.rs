// src/lexer/gpu/passes/sum_inblock_pairs.rs
use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct SumInblockPairsPass {
    data: PassData,
}

impl SumInblockPairsPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "sum_inblock_pairs",
            "sum_inblock_pairs",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/sum_inblock_pairs.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/sum_inblock_pairs.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for SumInblockPairsPass {
    const NAME: &'static str = "sum_inblock_pairs";
    const DIM: DispatchDim = DispatchDim::D2;

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
        use wgpu::BindingResource::*;
        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            ("block_prefix".into(), b.block_prefix.as_entire_binding()),
            ("f_final".into(), b.f_final.as_entire_binding()),
        ])
    }
}
