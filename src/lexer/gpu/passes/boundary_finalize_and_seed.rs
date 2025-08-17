use std::collections::HashMap;

use anyhow::Result;

use super::PassData;
use crate::{
    gpu::passes_core::{DispatchDim, make_pass_data},
    lexer::gpu::{
        buffers::GpuBuffers,
        debug::{self, DebugOutput},
    },
};

pub struct BoundaryFinalizeAndSeedPass {
    data: PassData,
}

impl BoundaryFinalizeAndSeedPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = make_pass_data(
            device,
            "boundary_finalize_and_seed",
            "boundary_finalize_and_seed",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/boundary_finalize_and_seed.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/boundary_finalize_and_seed.reflect.json"
            )),
        )?;

        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for BoundaryFinalizeAndSeedPass {
    const NAME: &'static str = "boundary_finalize_and_seed";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        buffers: &'a GpuBuffers,
    ) -> std::collections::HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            ("gParams".into(), buffers.params.as_entire_binding()),
            ("in_bytes".into(), buffers.in_bytes.as_entire_binding()),
            ("token_map".into(), buffers.token_map.as_entire_binding()),
            ("f_final".into(), buffers.f_final.as_entire_binding()),
            ("next_emit".into(), buffers.next_emit.as_entire_binding()),
            (
                "flags_packed".into(),
                buffers.flags_packed.as_entire_binding(),
            ),
            ("tok_types".into(), buffers.tok_types.as_entire_binding()),
            (
                "end_excl_by_i".into(),
                buffers.end_excl_by_i.as_entire_binding(),
            ),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &GpuBuffers,
        dbg: &mut debug::DebugOutput,
    ) {
        let g = &mut dbg.gpu;

        g.tok_types.set_from_copy(
            device,
            encoder,
            &bufs.tok_types,
            "dbg.tok_types",
            bufs.tok_types.byte_size,
        );
        g.end_excl_by_i.set_from_copy(
            device,
            encoder,
            &bufs.end_excl_by_i,
            "dbg.end_excl_by_i",
            bufs.end_excl_by_i.byte_size,
        );
        g.flags_packed.set_from_copy(
            device,
            encoder,
            &bufs.flags_packed,
            "dbg.flags_packed",
            bufs.flags_packed.byte_size,
        );
    }
}
