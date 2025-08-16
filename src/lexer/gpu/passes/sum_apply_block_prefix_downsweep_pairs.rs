use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput, util::compute_rounds},
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

        // rounds over nb_sum pair blocks
        let rounds = compute_rounds(b.nb_sum);

        #[cfg(feature = "gpu-debug")]
        {
            // Same parity rule as above: seed in PING, toggle each round.
            let plane = if (rounds % 2) == 1 { "PONG" } else { "PING" };
            println!(
                "[dbg] {}: rounds={} -> last-writer={}",
                Self::NAME,
                rounds,
                plane
            );
        }

        // Correct parity: choose PONG when rounds is odd, otherwise PING.
        let block_prefix_pair_binding: wgpu::BindingResource<'a> = if (rounds % 2) == 1 {
            b.block_pair_pong.as_entire_binding()
        } else {
            b.block_pair_ping.as_entire_binding()
        };

        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            ("block_prefix_pair".into(), block_prefix_pair_binding),
            ("s_all_final".into(), b.s_all_final.as_entire_binding()),
            ("s_keep_final".into(), b.s_keep_final.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.s_all_final.set_from_copy(
            device,
            encoder,
            &b.s_all_final,
            "dbg.s_all_final",
            b.s_all_final.byte_size,
        );
        dbg.gpu.s_keep_final.set_from_copy(
            device,
            encoder,
            &b.s_keep_final,
            "dbg.s_keep_final",
            b.s_keep_final.byte_size,
        );

        // NEW: show the pair plane the apply pass bound.
        let rounds = compute_rounds(b.nb_sum);
        let last = if (rounds % 2) == 1 {
            &b.block_pair_pong
        } else {
            &b.block_pair_ping
        };
        dbg.gpu.block_prefix_pair.set_from_copy(
            device,
            encoder,
            last,
            "dbg.block_prefix_pair.applied",
            last.byte_size,
        );
    }
}
