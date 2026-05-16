use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct CompactBoundariesKeptPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    CompactBoundariesKeptPass,
    label: "compact_boundaries_kept",
    entry: "compact_boundaries_kept",
    shader: "compact_boundaries"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for CompactBoundariesKeptPass {
    const NAME: &'static str = "compact_boundaries[KEPT]";
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
            ("s_final".into(), b.s_keep_final.as_entire_binding()),
            ("s_final_all".into(), b.s_all_final.as_entire_binding()),
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            ("tok_types".into(), b.tok_types.as_entire_binding()),
            // Write kept end positions to dedicated buffer
            ("end_positions".into(), b.end_positions.as_entire_binding()),
            ("types_compact".into(), b.types_compact.as_entire_binding()),
            (
                "all_index_compact".into(),
                b.all_index_compact.as_entire_binding(),
            ),
            ("token_count".into(), b.token_count.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.end_positions.set_from_copy(
            device,
            encoder,
            &b.end_positions,
            "dbg.end_positions",
            b.end_positions.byte_size,
        );
        dbg.gpu.types_compact.set_from_copy(
            device,
            encoder,
            &b.types_compact,
            "dbg.types_compact",
            b.types_compact.byte_size,
        );
        dbg.gpu.all_index_compact.set_from_copy(
            device,
            encoder,
            &b.all_index_compact,
            "dbg.all_index_compact",
            b.all_index_compact.byte_size,
        );
        dbg.gpu.token_count.set_from_copy(
            device,
            encoder,
            &b.token_count,
            "dbg.token_count",
            b.token_count.byte_size,
        );
    }
}
