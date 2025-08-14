// Single entry-point version: we dispatch the same kernel twice, once for ALL and once for KEPT.
// This is the ALL stream binding.

use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

pub struct CompactBoundariesAllPass {
    data: PassData,
}

impl CompactBoundariesAllPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "compact_boundaries_all", // <-- label
            "compact_boundaries_all", // <-- entry point name in Slang
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/compact_boundaries.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/compact_boundaries.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for CompactBoundariesAllPass {
    const NAME: &'static str = "compact_boundaries[ALL]";

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
            // ⬇️ ALL stream must use end_flags (0/1 when ANY boundary happens)
            ("flags_packed".into(), b.flags_packed.as_entire_binding()),
            ("tok_types".into(), b.tok_types.as_entire_binding()),
            ("end_excl_by_i".into(), b.end_excl_by_i.as_entire_binding()),
            (
                "end_positions".into(),
                b.end_positions_all.as_entire_binding(),
            ),
            ("token_count".into(), b.token_count_all.as_entire_binding()),
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
            &b.end_positions_all,
            "dbg.end_positions_all",
            b.end_positions_all.byte_size,
        );
        dbg.gpu.token_count_all.set_from_copy(
            device,
            encoder,
            &b.token_count_all,
            "dbg.token_count_all",
            b.token_count_all.byte_size,
        );
    }
}
