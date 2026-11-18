use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput, util::compute_rounds},
};

/// Third DFA pass: applies block prefixes and emits token boundary flags.
pub struct MarkTokenBoundariesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    MarkTokenBoundariesPass,
    label: "mark_token_boundaries",
    entry: "mark_token_boundaries",
    shader: "lexer/mark_token_boundaries"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for MarkTokenBoundariesPass {
    const NAME: &'static str = "mark_token_boundaries";
    const DIM: DispatchDim = DispatchDim::D2; // shader uses 2D tiling over blocks

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

        // Bind exactly what the fused Slang shader declares
        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            (
                "source_file_start_flags".into(),
                b.source_file_start_flags.as_entire_binding(),
            ),
            (
                "source_file_end_flags".into(),
                b.source_file_end_flags.as_entire_binding(),
            ),
            ("block_prefix_ping".into(), b.dfa_ping.as_entire_binding()),
            ("block_prefix_pong".into(), b.dfa_pong.as_entire_binding()),
            (
                "chunk_summaries".into(),
                b.dfa_chunk_summaries.as_entire_binding(),
            ),
            ("token_map".into(), b.token_map.as_entire_binding()),
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            ("tok_types".into(), b.tok_types.as_entire_binding()),
            (
                "lex_error_offset".into(),
                b.lex_error_offset.as_entire_binding(),
            ),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        // Keep a useful tap: show which block-prefix (inclusive scan of block delta) was applied.
        let rounds = compute_rounds(b.nb_dfa);
        let last = if (rounds % 2) == 1 {
            &b.dfa_pong
        } else {
            &b.dfa_ping
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
