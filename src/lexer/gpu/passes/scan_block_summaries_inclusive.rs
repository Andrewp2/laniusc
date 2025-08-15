use std::collections::HashMap;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::PassData;
use crate::{
    gpu::{passes_core::DispatchDim, timer::GpuTimer},
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput, passes::ScanParams},
};

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

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for ScanBlockSummariesInclusivePass {
    const NAME: &'static str = "scan_block_summaries_inclusive";
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
        HashMap::new()
    }

    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &GpuBuffers,
        input: super::InputElements,
        maybe_timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<(), anyhow::Error> {
        device.push_error_scope(wgpu::ErrorFilter::Validation);
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

        // Start with block_summaries -> block_ping
        let byte_len = (nblocks as usize) * (crate::lexer::tables::dfa::N_STATES * 4);
        encoder.copy_buffer_to_buffer(&b.block_summaries, 0, &b.block_ping, 0, byte_len as u64);

        let layout0 = &self.data().bind_group_layouts[0];
        let pipeline = &self.data().pipeline;
        let reflection = &self.data().reflection;

        // 2D tiling to respect 65,535-per-dimension limit.
        const MAX_PER_DIM: u32 = 65_535;
        let gx = nblocks.min(MAX_PER_DIM);
        let gy = if nblocks == 0 {
            1
        } else {
            (nblocks + MAX_PER_DIM - 1) / MAX_PER_DIM
        };

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
            .expect("failed to write scan params");

            let scan_params = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("ScanParams[blocks][{r}]")),
                contents: ub.as_ref(),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

            // reflection-based bind group, not hard-coded indices
            let mut res = HashMap::new();
            res.insert(
                "gParams".into(),
                wgpu::BindingResource::Buffer(b.params.as_entire_buffer_binding()),
            );
            res.insert(
                "scan_params".into(),
                wgpu::BindingResource::Buffer(scan_params.as_entire_buffer_binding()),
            );
            res.insert(
                "gScan".into(),
                wgpu::BindingResource::Buffer(scan_params.as_entire_buffer_binding()),
            );
            res.insert("block_ping".into(), b.block_ping.as_entire_binding());
            res.insert("block_pong".into(), b.block_pong.as_entire_binding());

            let bg = super::bind_group::create_bind_group_from_reflection(
                device,
                Some(&format!("scan_blocks_bg[{r}]")),
                layout0,
                reflection,
                0,
                &res,
            )
            .expect("scan_blocks_bg: reflection binding failed");

            pass.set_bind_group(0, &bg, &[]);
            // Dispatch a tiled 2D grid; the Slang kernel linearizes (x,y).
            pass.dispatch_workgroups(gx, gy, 1);
        }
        drop(pass);

        let last_write_pong = (rounds % 2) == 1;
        if last_write_pong {
            encoder.copy_buffer_to_buffer(&b.block_pong, 0, &b.block_prefix, 0, byte_len as u64);
        } else {
            encoder.copy_buffer_to_buffer(&b.block_ping, 0, &b.block_prefix, 0, byte_len as u64);
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
        Ok(())
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
