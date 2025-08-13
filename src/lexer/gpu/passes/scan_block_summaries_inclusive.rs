use std::collections::HashMap;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::{Pass, PassData, ScanParams};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput};

pub struct ScanBlockSummariesInclusivePass {
    data: PassData,
}
impl ScanBlockSummariesInclusivePass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "scan_block_summaries_inclusive",
            "scan_block_summaries_inclusive",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/scan_block_summaries_inclusive.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/scan_block_summaries_inclusive.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for ScanBlockSummariesInclusivePass {
    const NAME: &'static str = "scan_block_summaries_inclusive";

    fn from_data(data: PassData) -> Self {
        Self { data }
    }
    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        _b: &'a GpuBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::new()
    }

    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        _dbg: &mut DebugOutput,
        input: super::InputElements,
    ) {
        let nblocks = match input {
            super::InputElements::Elements1D(n) => n,
            _ => unreachable!(),
        };

        let rounds = {
            let mut r = 0u32;
            let mut s = 1u32;
            while s < nblocks {
                r += 1;
                s <<= 1;
            }
            r
        };

        let byte_len = (nblocks as usize) * (crate::lexer::tables::dfa::N_STATES * 4) as usize;
        encoder.copy_buffer_to_buffer(&b.block_summaries, 0, &b.block_ping, 0, byte_len as u64);

        let layout0 = &self.data().bind_group_layouts[0];
        let pipeline = &self.data().pipeline;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(Self::NAME),
            timestamp_writes: None,
        });
        pass.set_pipeline(pipeline);

        for r in 0..rounds {
            let stride = 1u32 << r;
            let use_ping_as_src = if r % 2 == 0 { 1 } else { 0 };

            let mut ub = UniformBuffer::new(Vec::new());
            ub.write(&ScanParams {
                stride,
                use_ping_as_src,
            })
            .unwrap();
            let scan_params = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("ScanParams[blocks][{r}]")),
                contents: ub.as_ref(),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

            let entries = &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(b.params.as_entire_buffer_binding()),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Buffer(scan_params.as_entire_buffer_binding()),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: b.block_ping.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: b.block_pong.as_entire_binding(),
                },
            ];
            let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some(&format!("scan_blocks_bg[{r}]")),
                layout: layout0.as_ref(),
                entries,
            });

            pass.set_bind_group(0, &bg, &[]);
            pass.dispatch_workgroups(nblocks, 1, 1);
        }
        drop(pass);

        let last_write_pong = (rounds % 2) == 1;
        if last_write_pong {
            encoder.copy_buffer_to_buffer(&b.block_pong, 0, &b.block_prefix, 0, byte_len as u64);
        } else {
            encoder.copy_buffer_to_buffer(&b.block_ping, 0, &b.block_prefix, 0, byte_len as u64);
        }
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.block_ping.set_from_copy(
            device,
            encoder,
            &b.block_ping,
            "dbg.block_ping",
            b.block_ping.byte_size,
        );
        dbg.gpu.block_pong.set_from_copy(
            device,
            encoder,
            &b.block_pong,
            "dbg.block_pong",
            b.block_pong.byte_size,
        );
        dbg.gpu.block_prefix.set_from_copy(
            device,
            encoder,
            &b.block_prefix,
            "dbg.block_prefix",
            b.block_prefix.byte_size,
        );
    }
}
