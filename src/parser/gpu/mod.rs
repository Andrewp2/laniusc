use anyhow::Result;
use buffers::ParserBuffers;

use crate::{gpu::passes_core::InputElements, parser::gpu::passes::Pass};
pub mod buffers;
pub mod passes;

pub struct GpuParser {
    device: wgpu::Device,
    queue: wgpu::Queue,
    p_llp_pairs: passes::llp_pairs::LLPPairsPass,
}

impl GpuParser {
    pub async fn new() -> Result<Self, anyhow::Error> {
        let instance = wgpu::Instance::default();
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions::default())
            .await
            .map_err(|_| anyhow::anyhow!("no adapter for parser"))?;
        let mut limits = wgpu::Limits::defaults();
        // ... why are my comments missing here...
        // they were explaining why we chose these values from the web3d survey...
        limits.max_storage_buffers_per_shader_stage = 10;
        limits.max_storage_buffer_binding_size = 2_147_483_644;
        limits.max_buffer_size = 2_147_483_644;

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("Lanius Parser Device"),
                required_features: wgpu::Features::SPIRV_SHADER_PASSTHROUGH,
                required_limits: limits,
                memory_hints: wgpu::MemoryHints::default(),
                trace: wgpu::Trace::default(),
            })
            .await?;

        let p_llp_pairs = passes::llp_pairs::LLPPairsPass::new(&device)?;

        Ok(Self {
            device,
            queue,
            p_llp_pairs,
        })
    }

    pub async fn llp_headers_mvp(
        &self,
        token_kinds_u32: &[u32],
        action_table_bytes: &[u8],
        n_kinds: u32,
    ) -> Result<LLPHeadersResult> {
        if token_kinds_u32.len() < 2 {
            return Ok(LLPHeadersResult::default());
        }

        let bufs = ParserBuffers::new(&self.device, token_kinds_u32, action_table_bytes, n_kinds);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser-enc"),
            });

        self.p_llp_pairs.record_pass(
            &self.device,
            &mut encoder,
            &bufs,
            InputElements::Elements1D(bufs.n_tokens),
        )?;
        self.queue.submit(Some(encoder.finish()));

        let n_pairs = (bufs.n_tokens - 1) as usize;
        let byte_len = n_pairs * std::mem::size_of::<buffers::ActionHeader>();
        let slice = bufs.out_headers.slice(0..byte_len as u64);

        let (tx, rx) = futures_intrusive::channel::shared::oneshot_channel();
        slice.map_async(wgpu::MapMode::Read, move |r| {
            let _ = tx.send(r);
        });

        self.device.poll(wgpu::PollType::Wait);
        let _ = rx.receive().await;

        let mapped = slice.get_mapped_range();
        let headers: Vec<buffers::ActionHeader> = read_action_headers(&mapped);
        drop(mapped);
        bufs.out_headers.unmap();

        let mut push_offsets = Vec::with_capacity(n_pairs);
        let mut emit_offsets = Vec::with_capacity(n_pairs);
        let mut acc_push = 0u32;
        let mut acc_emit = 0u32;

        for h in &headers {
            push_offsets.push(acc_push);
            emit_offsets.push(acc_emit);
            acc_push += h.push_len;
            acc_emit += h.emit_len;
        }

        Ok(LLPHeadersResult {
            headers,
            push_offsets,
            emit_offsets,
            total_push: acc_push,
            total_emit: acc_emit,
        })
    }
}

// Replace `bytemuck::cast_slice` with an explicit, endian-stable parser.
fn read_action_headers(bytes: &[u8]) -> Vec<buffers::ActionHeader> {
    const SIZE: usize = std::mem::size_of::<buffers::ActionHeader>();
    debug_assert_eq!(SIZE, 16);

    let mut out = Vec::with_capacity(bytes.len() / SIZE);
    for chunk in bytes.chunks_exact(SIZE) {
        let push_len = u32::from_le_bytes(chunk[0..4].try_into().unwrap());
        let emit_len = u32::from_le_bytes(chunk[4..8].try_into().unwrap());
        let pop_tag = u32::from_le_bytes(chunk[8..12].try_into().unwrap());
        let pop_count = u32::from_le_bytes(chunk[12..16].try_into().unwrap());
        out.push(buffers::ActionHeader {
            push_len,
            emit_len,
            pop_tag,
            pop_count,
        });
    }
    out
}

#[derive(Default)]
pub struct LLPHeadersResult {
    pub headers: Vec<buffers::ActionHeader>,
    pub push_offsets: Vec<u32>,
    pub emit_offsets: Vec<u32>,
    pub total_push: u32,
    pub total_emit: u32,
}
