// src/lexer/gpu/passes/retag_calls_and_arrays.rs
use std::collections::HashMap;

use super::{Pass, PassData};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

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

impl Pass for RetagCallsAndArraysPass {
    const NAME: &'static str = "retag_calls_and_arrays";

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
            // Read how many KEPT tokens there are
            ("token_count".into(), b.token_count.as_entire_binding()),
            // Rewrite kinds in-place before build_tokens runs
            ("types_compact".into(), b.types_compact.as_entire_binding()),
        ])
    }

    // We can over-dispatch safely; the shader returns when k >= token_count[0].
    // So just reuse the default group sizing.
    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        // Optional: snapshot the retagged kinds
        dbg.gpu.types_compact.set_from_copy(
            device,
            encoder,
            &b.types_compact,
            "dbg.types_compact.after_retag",
            b.types_compact.byte_size,
        );
    }
}
