use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

pub struct ApplyBlockPrefixDownsweepPass {
    data: PassData,
}
impl ApplyBlockPrefixDownsweepPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "apply_block_prefix_downsweep",
            "apply_block_prefix_downsweep",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/apply_block_prefix_downsweep.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/apply_block_prefix_downsweep.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for ApplyBlockPrefixDownsweepPass {
    const NAME: &'static str = "apply_block_prefix_downsweep";

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
            ("block_prefix".into(), b.block_prefix.as_entire_binding()),
            ("f_final".into(), b.f_final.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.f_final.set_from_copy(
            device,
            encoder,
            &b.f_final,
            "dbg.f_final",
            b.f_final.byte_size,
        );
    }
}
