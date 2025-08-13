// Single entry-point version: we dispatch the same kernel twice, once for ALL and once for KEPT.
// This is the KEPT stream binding.

use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

pub struct CompactBoundariesKeptPass {
    data: PassData,
}

impl CompactBoundariesKeptPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "compact_boundaries",
            "compact_boundaries",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/compact_boundaries.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/compact_boundaries.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for CompactBoundariesKeptPass {
    const NAME: &'static str = "compact_boundaries[KEPT]";

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
            (
                "filtered_flags".into(),
                b.filtered_flags.as_entire_binding(),
            ),
            ("tok_types".into(), b.tok_types.as_entire_binding()),
            ("end_excl_by_i".into(), b.end_excl_by_i.as_entire_binding()),
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
