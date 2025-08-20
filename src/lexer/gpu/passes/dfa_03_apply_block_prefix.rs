use std::collections::HashMap;

use super::PassData;
use crate::lexer::gpu::{
    buffers::GpuBuffers,
    debug::DebugOutput,
    passes::DispatchDim,
    util::compute_rounds,
};

pub struct Dfa03ApplyBlockPrefixPass {
    data: PassData,
}
impl Dfa03ApplyBlockPrefixPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "dfa_03_apply_block_prefix",
            "dfa_03_apply_block_prefix",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_03_apply_block_prefix.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_03_apply_block_prefix.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Dfa03ApplyBlockPrefixPass {
    const NAME: &'static str = "dfa_03_apply_block_prefix";
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
            let plane = if (rounds % 2) == 1 { "PONG" } else { "PING" };
            println!(
                "[dbg] {}: rounds={} -> last-writer={}",
                Self::NAME,
                rounds,
                plane
            );
        }

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
            ("next_u8".into(), b.next_u8.as_entire_binding()),
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
