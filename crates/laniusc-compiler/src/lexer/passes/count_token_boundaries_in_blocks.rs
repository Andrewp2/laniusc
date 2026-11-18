use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

/// First pair pass: counts all and kept token boundaries inside each block.
pub struct CountTokenBoundariesInBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    CountTokenBoundariesInBlocksPass,
    label: "count_token_boundaries_in_blocks",
    entry: "count_token_boundaries_in_blocks",
    shader: "lexer/count_token_boundaries_in_blocks"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for CountTokenBoundariesInBlocksPass {
    const NAME: &'static str = "count_token_boundaries_in_blocks";
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
                b.dfa_ping.as_entire_binding(),
            ),
        ])
    }
}
