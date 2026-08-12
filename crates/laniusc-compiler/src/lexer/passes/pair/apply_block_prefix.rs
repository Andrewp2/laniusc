use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

/// Third pair pass: applies boundary prefixes and writes compact ranks.
pub struct Pair03ApplyBlockPrefixPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    Pair03ApplyBlockPrefixPass,
    label: "pair_03_apply_block_prefix",
    entry: "pair_03_apply_block_prefix",
    shader: "lexer/pair/03_apply_block_prefix"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Pair03ApplyBlockPrefixPass {
    const NAME: &'static str = "pair_03_apply_block_prefix";
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
                "block_prefix_pair_ping".into(),
                b.dfa_02_ping.as_entire_binding(),
            ),
            (
                "block_prefix_pair_pong".into(),
                b.dfa_02_pong.as_entire_binding(),
            ),
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

        let last = if super::block_total_scan_last_writer_is_ping(b.nb_sum) {
            &b.dfa_02_ping
        } else {
            &b.dfa_02_pong
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
