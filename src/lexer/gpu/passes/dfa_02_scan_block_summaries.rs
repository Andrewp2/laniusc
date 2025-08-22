use std::collections::HashMap;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::PassData;
use crate::{
    gpu::passes_core::{
        DispatchDim,
        bind_group::create_bind_group_from_reflection,
        validation_scopes_enabled,
    },
    lexer::gpu::{
        buffers::GpuBuffers,
        debug::DebugOutput,
        passes::ScanParams,
        util::compute_rounds,
    },
};

pub struct Dfa02ScanBlockSummariesPass {
    data: PassData,
}

impl Dfa02ScanBlockSummariesPass {
    pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "dfa_02_scan_block_summaries",
            "dfa_02_scan_block_summaries",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_02_scan_block_summaries.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/dfa_02_scan_block_summaries.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for Dfa02ScanBlockSummariesPass {
    const NAME: &'static str = "dfa_02_scan_block_summaries";
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

    fn record_pass<'a>(
        &self,
        ctx: &mut crate::gpu::passes_core::PassContext<'a, GpuBuffers, DebugOutput>,
        input: crate::gpu::passes_core::InputElements,
    ) -> anyhow::Result<(), anyhow::Error> {
        let device = ctx.device;
        let encoder = &mut ctx.encoder;
        let b = ctx.buffers;
        let maybe_timer = &mut ctx.maybe_timer;
        let maybe_dbg = &mut ctx.maybe_dbg;

        let use_scopes = validation_scopes_enabled();

        if use_scopes {
            device.push_error_scope(wgpu::ErrorFilter::Validation);
        }

        let n = match input {
            super::InputElements::Elements1D(n) => n,
            _ => unreachable!(),
        };

        let rounds = compute_rounds(n);

        let pd = self.data();

        let layout0 = &pd.bind_group_layouts[0];
        let pipeline = &pd.pipeline;
        let reflection = &pd.reflection;

        if let Some(dbg) = maybe_dbg.as_deref_mut() {
            dbg.gpu.func_scan_rounds.clear();
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
                label: Some(&format!("ScanParams[FUNC-BLOCKS][{r}]")),
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
                ("block_ping".into(), b.dfa_02_ping.as_entire_binding()),
                ("block_pong".into(), b.dfa_02_pong.as_entire_binding()),
            ]);

            let bg = create_bind_group_from_reflection(
                device,
                Some(&format!("func_blocks_bg[{r}]")),
                &layout0,
                &reflection,
                0,
                &res,
            )
            .expect("func_blocks_bg reflection");

            {
                // One workgroup per block. The group itself has N_STATES threads.
                // Tell the planner each “element” already maps 1:1 to a group.
                let (gx, gy, gz) = crate::gpu::passes_core::plan_workgroups(
                    crate::gpu::passes_core::DispatchDim::D1,
                    crate::gpu::passes_core::InputElements::Elements1D(n),
                    [1, 1, 1],
                )?;
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some(Self::NAME),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&pipeline);
                pass.set_bind_group(0, &bg, &[]);
                pass.dispatch_workgroups(gx, gy, gz);
            }

            #[cfg(feature = "gpu-debug")]
            if let Some(dbg) = maybe_dbg.as_deref_mut() {
                let per_round_bytes = (n as usize) * N_STATES * std::mem::size_of::<u32>();
                use crate::lexer::gpu::debug::make_staging;
                // TODO: block_ping and block_pong are both N_STATES * (nb_dfa as usize) as their count, with that times 4 being byte count.
                // for some reason we're copying n * N_STATES * 4 bytes, which is more than the size of the buffer.
                let last_writer = if use_ping_as_src != 0 {
                    &b.block_pong
                } else {
                    &b.block_ping
                };
                let staging = make_staging(device, "dbg.func_scan_round", per_round_bytes);
                encoder.copy_buffer_to_buffer(last_writer, 0, &staging, 0, per_round_bytes as u64);
                dbg.gpu
                    .func_scan_rounds
                    .push(crate::lexer::gpu::DebugBuffer {
                        label: "dbg.func_scan_round",
                        buffer: Some(staging),
                        byte_len: per_round_bytes,
                    });
            }
        }

        if let Some(t) = maybe_timer {
            t.stamp(encoder, Self::NAME.to_string());
        }

        if use_scopes {
            if let Some(err) = pollster::block_on(device.pop_error_scope()) {
                return Err(anyhow::anyhow!(
                    "validation in pass {}: {:?}",
                    Self::NAME,
                    err
                ));
            }
        }

        if let Some(d) = maybe_dbg.as_deref_mut() {
            (&self).record_debug(device, encoder, b, d);
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
            &b.dfa_02_ping,
            "dbg.block_ping",
            b.dfa_02_ping.byte_size,
        );
        dbg.gpu.block_pong.set_from_copy(
            device,
            encoder,
            &b.dfa_02_pong,
            "dbg.block_pong",
            b.dfa_02_pong.byte_size,
        );

        let rounds = compute_rounds(b.nb_dfa);

        let last = if (rounds % 2) == 1 {
            &b.dfa_02_pong
        } else {
            &b.dfa_02_ping
        };
        dbg.gpu.block_prefix.set_from_copy(
            device,
            encoder,
            last,
            "dbg.block_prefix",
            last.byte_size,
        );
    }
}
