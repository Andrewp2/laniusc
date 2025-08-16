// src/lexer/gpu/passes/sum_scan_block_totals_inclusive.rs
use std::collections::HashMap;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::PassData;
use crate::{
    gpu::{debug::DebugBuffer, passes_core::DispatchDim, timer::GpuTimer},
    lexer::gpu::{
        buffers::GpuBuffers,
        debug::{DebugOutput, make_staging},
        passes::ScanParams,
        util::compute_rounds,
    },
};

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

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for SumScanBlockTotalsInclusivePass {
    const NAME: &'static str = "sum_scan_block_totals_inclusive";
    const DIM: DispatchDim = DispatchDim::D1;

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
        panic!(
            "we implement this in record_pass to deal with uniforms, which is actually hacky and bad but whatever"
        );
    }

    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        input: super::InputElements,
        maybe_timer: &mut Option<&mut GpuTimer>,
        maybe_dbg: &mut Option<&mut DebugOutput>,
    ) -> Result<(), anyhow::Error> {
        device.push_error_scope(wgpu::ErrorFilter::Validation);

        let nblocks = match input {
            super::InputElements::Elements1D(n) => n,
            _ => unreachable!(),
        };

        // 1) Seed ping from per-block totals
        let per_round_bytes_u64 = (nblocks as usize * 2 * std::mem::size_of::<u32>()) as u64; // uint2 per block
        encoder.copy_buffer_to_buffer(
            &b.block_totals_pair,
            0,
            &b.block_pair_ping,
            0,
            per_round_bytes_u64,
        );

        // 2) Number of rounds
        let rounds = compute_rounds(nblocks);

        let layout0 = &self.data().bind_group_layouts[0];
        let pipeline = &self.data().pipeline;
        let reflection = &self.data().reflection;

        // If we’re capturing debug, reset the per-round vector for this run.
        if let Some(dbg) = maybe_dbg.as_deref_mut() {
            dbg.gpu.pair_scan_rounds.clear();
        }

        for r in 0..rounds {
            let stride = 1u32 << r;
            let use_ping_as_src = if r % 2 == 0 { 1u32 } else { 0u32 };

            let mut ub = UniformBuffer::new(Vec::new());
            ub.write(&ScanParams {
                stride,
                use_ping_as_src,
            })
            .expect("write ScanParams");
            let scan_params = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("ScanParams[PAIR-BLOCKS][{r}]")),
                contents: ub.as_ref(),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

            let res = HashMap::from([
                (
                    "gParams".into(),
                    wgpu::BindingResource::Buffer(b.params.as_entire_buffer_binding()),
                ),
                (
                    "gScan".into(),
                    wgpu::BindingResource::Buffer(scan_params.as_entire_buffer_binding()),
                ),
                (
                    "block_pair_ping".into(),
                    b.block_pair_ping.as_entire_binding(),
                ),
                (
                    "block_pair_pong".into(),
                    b.block_pair_pong.as_entire_binding(),
                ),
            ]);

            let bg = super::bind_group::create_bind_group_from_reflection(
                device,
                Some(&format!("pair_blocks_bg[{r}]")),
                layout0,
                reflection,
                0,
                &res,
            )
            .expect("pair_blocks_bg reflection");

            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some(Self::NAME),
                    timestamp_writes: None,
                });
                pass.set_pipeline(pipeline);
                pass.set_bind_group(0, &bg, &[]);
                pass.dispatch_workgroups(nblocks, 1, 1);
            }

            // Per-round debug snapshots opt-in only.
            #[cfg(feature = "gpu-debug")]
            if let Some(dbg) = maybe_dbg.as_deref_mut() {
                use crate::lexer::gpu::debug::make_staging;
                let last_writer = if use_ping_as_src != 0 {
                    &b.block_pair_pong
                } else {
                    &b.block_pair_ping
                };
                let staging =
                    make_staging(device, "dbg.pair_scan_round", per_round_bytes_u64 as usize);
                encoder.copy_buffer_to_buffer(last_writer, 0, &staging, 0, per_round_bytes_u64);
                dbg.gpu.pair_scan_rounds.push(DebugBuffer {
                    label: "dbg.pair_scan_round",
                    buffer: Some(staging),
                    byte_len: per_round_bytes_u64 as usize,
                });
            }
        }

        if let Some(t) = maybe_timer {
            t.stamp(encoder, Self::NAME.to_string());
        }

        if let Some(err) = pollster::block_on(device.pop_error_scope()) {
            return Err(anyhow::anyhow!(
                "validation in pass {}: {:?}",
                Self::NAME,
                err
            ));
        }

        // Keep the final planes as before.
        if let Some(d) = maybe_dbg.as_deref_mut() {
            self.record_debug(device, encoder, b, d);
        }
        Ok(())
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        dbg: &mut DebugOutput,
    ) {
        dbg.gpu.block_pair_ping.set_from_copy(
            device,
            encoder,
            &b.block_pair_ping,
            "dbg.block_pair_ping",
            b.block_pair_ping.byte_size,
        );
        dbg.gpu.block_pair_pong.set_from_copy(
            device,
            encoder,
            &b.block_pair_pong,
            "dbg.block_pair_pong",
            b.block_pair_pong.byte_size,
        );

        // NEW: copy the last-writer plane as "block_prefix_pair".
        let rounds = compute_rounds(b.nb_sum);
        let last = if (rounds % 2) == 1 {
            &b.block_pair_pong
        } else {
            &b.block_pair_ping
        };
        dbg.gpu.block_prefix_pair.set_from_copy(
            device,
            encoder,
            last,
            "dbg.block_prefix_pair",
            last.byte_size,
        );
    }
}
