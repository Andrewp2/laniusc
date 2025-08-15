use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct SumApplyBlockPrefixDownsweepPairsPass {
    data: PassData,
}

impl SumApplyBlockPrefixDownsweepPairsPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "sum_apply_block_prefix_downsweep_pairs",
            "sum_apply_block_prefix_downsweep",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/sum_apply_block_prefix_downsweep_pairs.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/sum_apply_block_prefix_downsweep_pairs.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput>
    for SumApplyBlockPrefixDownsweepPairsPass
{
    const NAME: &'static str = "sum_apply_block_prefix_downsweep_pairs";
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
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            (
                "block_prefix_pair".into(),
                b.block_prefix_pair.as_entire_binding(),
            ),
            ("s_all_final".into(), b.s_all_final.as_entire_binding()),
            ("s_keep_final".into(), b.s_keep_final.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _buffers: &GpuBuffers,
        _debug: &mut DebugOutput,
    ) {
        // No debug output for this pass
    }
}
