use std::collections::HashMap;

use super::PassData;
use crate::lexer::gpu::{
    buffers::GpuBuffers,
    debug::DebugOutput,
    passes::DispatchDim,
    util::compute_rounds,
};

pub struct ApplyBlockPrefixDownsweepPass {
    data: PassData,
}
impl ApplyBlockPrefixDownsweepPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "apply_block_prefix_downsweep",
            "apply_block_prefix_downsweep",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/apply_block_prefix_downsweep.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/apply_block_prefix_downsweep.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for ApplyBlockPrefixDownsweepPass {
    const NAME: &'static str = "apply_block_prefix_downsweep";
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

        let rounds = compute_rounds(b.nb_dfa);

        #[cfg(feature = "gpu-debug")]
        {
            // Seed was written to PING, then we toggle each round. Therefore:
            //   - last writer = PONG when rounds is odd
            //   - last writer = PING when rounds is even (including 0)
            let plane = if (rounds % 2) == 1 { "PONG" } else { "PING" };
            println!(
                "[dbg] {}: rounds={} -> last-writer={}",
                Self::NAME,
                rounds,
                plane
            );
        }

        // Correct parity: choose PONG when rounds is odd, otherwise PING.
        let block_prefix_binding: wgpu::BindingResource<'a> = if (rounds % 2) == 1 {
            b.block_pong.as_entire_binding()
        } else {
            b.block_ping.as_entire_binding()
        };
        debug_assert!(rounds == 0 || b.block_ping.count == b.block_pong.count);

        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            ("block_prefix".into(), block_prefix_binding),
            ("f_final".into(), b.f_final.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.f_final.set_from_copy(
            device,
            encoder,
            &b.f_final,
            "dbg.f_final",
            b.f_final.byte_size,
        );

        // NEW: mirror the parity logic used to pick the bound plane for this pass.
        let rounds = compute_rounds(b.nb_dfa);
        let last = if (rounds % 2) == 1 {
            &b.block_pong
        } else {
            &b.block_ping
        };
        dbg.gpu.block_prefix.set_from_copy(
            device,
            encoder,
            last,
            "dbg.block_prefix.applied",
            last.byte_size,
        );
    }
}
