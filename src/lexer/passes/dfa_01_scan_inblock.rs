use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct Dfa01ScanInblockPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    Dfa01ScanInblockPass,
    label: "dfa_01_scan_inblock",
    entry: "dfa_01_scan_inblock",
    shader: "dfa_01_scan_inblock"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Dfa01ScanInblockPass {
    const NAME: &'static str = "dfa_01_scan_inblock";
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
    ) -> std::collections::HashMap<String, wgpu::BindingResource<'a>> {
        use wgpu::BindingResource::*;
        HashMap::from([
            (
                "gParams".into(),
                Buffer(b.params.as_entire_buffer_binding()),
            ),
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            (
                "source_file_count".into(),
                b.source_file_count.as_entire_binding(),
            ),
            (
                "source_file_start".into(),
                b.source_file_start.as_entire_binding(),
            ),
            ("next_u8".into(), b.next_u8.as_entire_binding()),
            ("block_summaries".into(), b.dfa_02_ping.as_entire_binding()),
            (
                "chunk_summary_out".into(),
                b.dfa_chunk_summaries.as_entire_binding(),
            ),
        ])
    }

    // fn record_debug(
    //     &self,
    //     device: &wgpu::Device,
    //     encoder: &mut wgpu::CommandEncoder,
    //     bufs: &GpuBuffers,
    //     dbg: &mut DebugOutput,
    // ) {
    //     dbg.gpu.block_summaries.set_from_copy(
    //         device,
    //         encoder,
    //         &bufs.block_summaries,
    //         "dbg.block_summaries",
    //         bufs.block_summaries.byte_size,
    //     );
    // }
}
