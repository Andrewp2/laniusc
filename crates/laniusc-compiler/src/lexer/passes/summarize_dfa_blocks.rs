use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

/// First DFA pass: scans byte transitions inside each block.
pub struct SummarizeDfaBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    SummarizeDfaBlocksPass,
    label: "summarize_dfa_blocks",
    entry: "summarize_dfa_blocks",
    shader: "lexer/summarize_dfa_blocks"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for SummarizeDfaBlocksPass {
    const NAME: &'static str = "summarize_dfa_blocks";
    const DIM: DispatchDim = DispatchDim::D2;

    fn data(&self) -> &PassData {
        &self.data
    }

    fn from_data(data: PassData) -> Self {
        Self { data }
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
            (
                "source_file_start_flags".into(),
                b.source_file_start_flags.as_entire_binding(),
            ),
            ("next_u8".into(), b.next_u8.as_entire_binding()),
            ("block_summaries".into(), b.dfa_ping.as_entire_binding()),
            (
                "chunk_summary_out".into(),
                b.dfa_chunk_summaries.as_entire_binding(),
            ),
        ])
    }
}
