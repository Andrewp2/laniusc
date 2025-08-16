use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct Dfa01ScanInblockPass {
    data: PassData,
}

impl Dfa01ScanInblockPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "dfa_01_scan_inblock",
            "dfa_01_scan_inblock",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_01_scan_inblock.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_01_scan_inblock.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

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
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            (
                "block_summaries".into(),
                b.block_summaries.as_entire_binding(),
            ),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.block_summaries.set_from_copy(
            device,
            encoder,
            &bufs.block_summaries,
            "dbg.block_summaries",
            bufs.block_summaries.byte_size,
        );
    }
}
