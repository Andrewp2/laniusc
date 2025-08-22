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
    const NAME: &'static str = "dfa_03_apply_block_prefix"; // 🤖
    const DIM: DispatchDim = DispatchDim::D2; // 🤖 shader uses 2D tiling over blocks

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

        // 🤖 Pick last-writer of the block scan (dfa_02)
        let rounds = compute_rounds(b.nb_dfa);
        let block_prefix_binding: wgpu::BindingResource<'a> = if (rounds % 2) == 1 {
            b.dfa_02_pong.as_entire_binding()
        } else {
            b.dfa_02_ping.as_entire_binding()
        };
        debug_assert!(rounds == 0 || b.dfa_02_ping.count == b.dfa_02_pong.count);

        // 🤖 Bind exactly what the fused Slang shader declares
        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            ("block_prefix".into(), block_prefix_binding),
            ("token_map".into(), b.token_map.as_entire_binding()),
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            ("tok_types".into(), b.tok_types.as_entire_binding()),
            ("end_excl_by_i".into(), b.end_excl_by_i.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        // 🤖 Keep a useful tap: show which block-prefix (inclusive scan of block δ) was applied.
        let rounds = compute_rounds(b.nb_dfa);
        let last = if (rounds % 2) == 1 {
            &b.dfa_02_pong
        } else {
            &b.dfa_02_ping
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
