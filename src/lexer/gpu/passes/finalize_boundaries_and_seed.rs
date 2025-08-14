use std::collections::HashMap;

use anyhow::{Result, anyhow};

use super::{DispatchDim, Pass, PassData};
use crate::{
    lexer::gpu::{buffers::GpuBuffers, debug},
    reflection::{SlangReflection, get_thread_group_size, parse_reflection_from_bytes},
};

pub struct FinalizeBoundariesAndSeedPass {
    data: PassData,
}

impl FinalizeBoundariesAndSeedPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let spirv = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/finalize_boundaries_and_seed.spv"
        ));
        let reflection_json = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/finalize_boundaries_and_seed.reflect.json"
        ));

        let reflection: SlangReflection =
            parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;
        let thread_group_size = get_thread_group_size(&reflection).unwrap_or([1, 1, 1]);

        let owned_bgls = super::bgls_from_reflection(device, &reflection)?;
        if owned_bgls.is_empty() {
            return Err(anyhow!("finalize: no bind group layouts in reflection"));
        }
        let bgl_refs: Vec<&wgpu::BindGroupLayout> = owned_bgls.iter().collect();

        let pipeline = super::pipeline_from_spirv_and_bgls(
            device,
            "finalize_boundaries_and_seed",
            "finalize_boundaries_and_seed",
            spirv,
            &bgl_refs,
        );

        Ok(Self::from_data(PassData {
            pipeline: std::sync::Arc::new(pipeline),
            bind_group_layouts: owned_bgls.into_iter().map(std::sync::Arc::new).collect(),
            shader_id: "finalize_boundaries_and_seed".to_string(),
            thread_group_size,
            reflection: std::sync::Arc::new(reflection),
        }))
    }
}

impl Pass for FinalizeBoundariesAndSeedPass {
    const NAME: &'static str = "finalize_boundaries_and_seed";
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
        fn make_staging(
            device: &wgpu::Device,
            label: &'static str,
            byte_len: usize,
        ) -> wgpu::Buffer {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_len as u64,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        }

        let mut copy_into = |src: &wgpu::Buffer,
                             byte_len: usize,
                             dst_label: &'static str,
                             out_slot: &mut debug::DebugBuffer| {
            let staging = make_staging(device, dst_label, byte_len);
            encoder.copy_buffer_to_buffer(src, 0, &staging, 0, byte_len as u64);
            *out_slot = debug::DebugBuffer {
                label: dst_label,
                buffer: Some(staging),
                byte_len,
            };
        };

        let g = &mut dbg.gpu;

        copy_into(
            &bufs.tok_types,
            bufs.tok_types.byte_size,
            "dbg.tok_types",
            &mut g.tok_types,
        );
        copy_into(
            &bufs.end_excl_by_i,
            bufs.end_excl_by_i.byte_size,
            "dbg.end_excl_by_i",
            &mut g.end_excl_by_i,
        );
    }
}
