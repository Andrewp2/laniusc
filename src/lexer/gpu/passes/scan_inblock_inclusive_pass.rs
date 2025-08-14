use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

pub struct ScanInblockInclusivePass {
    data: PassData,
}
impl ScanInblockInclusivePass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "scan_inblock_inclusive",
            "scan_inblock_inclusive",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/scan_inblock_inclusive.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/scan_inblock_inclusive.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for ScanInblockInclusivePass {
    const NAME: &'static str = "scan_inblock_inclusive";

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
            ("in_bytes".into(), b.in_bytes.as_entire_binding()),
            ("next_emit".into(), b.next_emit.as_entire_binding()),
            (
                "block_summaries".into(),
                b.block_summaries.as_entire_binding(),
            ),
        ])
    }

    fn get_dispatch_size_1d(&self, nblocks: u32) -> (u32, u32, u32) {
        (nblocks, 1, 1)
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
