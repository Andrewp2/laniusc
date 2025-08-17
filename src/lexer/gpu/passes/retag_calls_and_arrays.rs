use std::collections::HashMap;

use super::PassData;
use crate::{
    gpu::passes_core::DispatchDim,
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

pub struct RetagCallsAndArraysPass {
    data: PassData,
}

impl RetagCallsAndArraysPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "retag_calls_and_arrays",
            "retag_calls_and_arrays",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/retag_calls_and_arrays.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/retag_calls_and_arrays.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for RetagCallsAndArraysPass {
    const NAME: &'static str = "retag_calls_and_arrays";
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
            ("token_count".into(), b.token_count.as_entire_binding()),
            ("types_compact".into(), b.types_compact.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.types_compact.set_from_copy(
            device,
            encoder,
            &b.types_compact,
            "dbg.types_compact.after_retag",
            b.types_compact.byte_size,
        );
    }
}
