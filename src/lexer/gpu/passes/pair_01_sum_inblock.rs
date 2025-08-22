use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct Pair01SumInblockPass {
    data: PassData,
}

impl Pair01SumInblockPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "pair_01_sum_inblock",
            "pair_01_sum_inblock",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/pair_01_sum_inblock.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/pair_01_sum_inblock.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Pair01SumInblockPass {
    const NAME: &'static str = "pair_01_sum_inblock";
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
        use wgpu::BindingResource::*;
        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            (
                "block_totals_pair".into(),
                // Reuse DFA block ping as pair ping
                b.dfa_02_ping.as_entire_binding(),
            ),
        ])
    }
    // fn record_debug(
    //     &self,
    //     device: &wgpu::Device,
    //     encoder: &mut wgpu::CommandEncoder,
    //     b: &GpuBuffers,
    //     dbg: &mut DebugOutput,
    // ) {
    //     dbg.gpu.block_totals_pair.set_from_copy(
    //         device,
    //         encoder,
    //         &b.block_totals_pair,
    //         "dbg.block_totals_pair",
    //         b.block_totals_pair.byte_size,
    //     );
    // }
}
