use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct CompactBoundariesAllPass {
    data: PassData,
}

impl CompactBoundariesAllPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "compact_boundaries_all",
            "compact_boundaries_all",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/compact_boundaries.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/compact_boundaries.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for CompactBoundariesAllPass {
    const NAME: &'static str = "compact_boundaries[ALL]";
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
            ("s_final".into(), b.s_all_final.as_entire_binding()),
            ("s_final_all".into(), b.s_all_final.as_entire_binding()),
            ("types_compact".into(), b.types_compact.as_entire_binding()),
            (
                "all_index_compact".into(),
                b.all_index_compact.as_entire_binding(),
            ),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            // For ALL: tok_types not used; bind a distinct buffer to avoid aliasing with end_positions
            ("tok_types".into(), b.flags_packed.as_entire_binding()),
            // Write ALL end_positions into the tok_types buffer to reuse memory
            ("end_positions".into(), b.tok_types.as_entire_binding()),
            // Sink ALL count into an unused buffer to preserve KEPT's token_count for tokens_build
            ("token_count".into(), b.dfa_02_pong.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.end_positions_all.set_from_copy(
            device,
            encoder,
            // end_positions_all reuses tok_types buffer
            &b.tok_types,
            "dbg.end_positions_all",
            b.tok_types.byte_size,
        );
        // ⬇️ point to the sink buffer you bound for ALL token_count
        dbg.gpu.token_count_all.set_from_copy(
            device,
            encoder,
            &b.dfa_02_pong,
            "dbg.token_count_all",
            b.dfa_02_pong.byte_size,
        );
    }
}
