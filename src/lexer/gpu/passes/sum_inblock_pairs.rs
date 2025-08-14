// src/lexer/gpu/passes/sum_inblock_pairs.rs
use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::buffers::GpuBuffers;

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

impl Pass for SumInblockPairsPass {
    const NAME: &'static str = "sum_inblock_pairs";

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
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            (
                "block_totals_pair".into(),
                b.block_totals_pair.as_entire_binding(),
            ),
        ])
    }
}
