use std::collections::HashMap;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::{Pass, PassData, ScanParams};
use crate::lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput, timer::GpuTimer};

pub struct SumScanBlockTotalsInclusivePass {
    data: PassData,
}
impl SumScanBlockTotalsInclusivePass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = super::make_pass_data(
            device,
            "sum_scan_block_totals_inclusive",
            "sum_scan_block_totals_inclusive",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/sum_scan_block_totals_inclusive.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/sum_scan_block_totals_inclusive.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass for SumScanBlockTotalsInclusivePass {
    const NAME: &'static str = "sum_scan_block_totals_inclusive";

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
        maybe_timer: Option<&mut GpuTimer>,
    ) {
        let nblocks = match input {
            super::InputElements::Elements1D(n) => n,
            _ => unreachable!(),
        };

        // Rounds = ceil_log2(nblocks)
        let rounds = {
            let mut r = 0u32;
            let mut s = 1u32;
            while s < nblocks {
                r += 1;
                s <<= 1;
            }
            r
        };

        // Copy totals -> ping
        let byte_len = (nblocks as usize) * 8; // uint2 per block
        encoder.copy_buffer_to_buffer(
            &b.block_totals_pair,
            0,
            &b.block_pair_ping,
            0,
            byte_len as u64,
        );

        let layout0 = &self.data().bind_group_layouts[0];
        let pipeline = &self.data().pipeline;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(Self::NAME),
            timestamp_writes: None,
        });
        pass.set_pipeline(pipeline);

        for r in 0..rounds {
            let stride = 1u32 << r;
            let use_ping_as_src = if r % 2 == 0 { 1u32 } else { 0u32 };

            let mut ub = UniformBuffer::new(Vec::new());
            ub.write(&ScanParams {
                stride,
                use_ping_as_src,
            })
            .unwrap();
            let scan_params = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("ScanParams[SUM-BLOCKS][{r}]")),
                contents: ub.as_ref(),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

            let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some(&format!("sum_blocks_bg[{r}]")),
                layout: layout0.as_ref(),
                // TODO: switch to using reflection instead of manual bindings
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::Buffer(
                            b.params.as_entire_buffer_binding(),
                        ),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::Buffer(
                            scan_params.as_entire_buffer_binding(),
                        ),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: b.block_pair_ping.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: b.block_pair_pong.as_entire_binding(),
                    },
                ],
            });

            pass.set_bind_group(0, &bg, &[]);
            pass.dispatch_workgroups(nblocks, 1, 1);
            // TODO: time every round?
        }
        drop(pass);

        // Write the inclusive block prefix into its final buffer
        let last_write_pong = (rounds % 2) == 1;
        if last_write_pong {
            encoder.copy_buffer_to_buffer(
                &b.block_pair_pong,
                0,
                &b.block_prefix_pair,
                0,
                byte_len as u64,
            );
        } else {
            encoder.copy_buffer_to_buffer(
                &b.block_pair_ping,
                0,
                &b.block_prefix_pair,
                0,
                byte_len as u64,
            );
        }

        if let Some(t) = maybe_timer {
            t.stamp(encoder, Self::NAME.to_string());
        }
    }
}
