// src/lexer/gpu/debug.rs
#![allow(dead_code)]

use wgpu::BufferUsages;

/// CPU-side holder for a staged GPU buffer.
#[derive(Clone, Default)]
pub struct DebugBuffer {
    pub label: &'static str,
    pub buffer: Option<wgpu::Buffer>,
    pub byte_len: usize,
}

impl DebugBuffer {
    pub fn is_some(&self) -> bool {
        self.buffer.is_some()
    }

    pub fn read_bytes(&self) -> Option<Vec<u8>> {
        let buf = self.buffer.as_ref()?;
        let view = buf.slice(..).get_mapped_range();
        Some(view.to_vec())
    }

    pub fn read_u32s(&self) -> Option<Vec<u32>> {
        self.read_bytes().map(|v| {
            let mut out = Vec::with_capacity(v.len() / 4);
            for chunk in v.chunks_exact(4) {
                out.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            out
        })
    }
}

#[derive(Default)]
pub struct DebugGpuBuffers {
    pub in_bytes: DebugBuffer,

    pub block_summaries: DebugBuffer,
    pub block_ping: DebugBuffer,
    pub block_pong: DebugBuffer,
    pub block_prefix: DebugBuffer,
    pub f_final: DebugBuffer,

    pub tok_types: DebugBuffer,
    pub filtered_flags: DebugBuffer,
    pub end_excl_by_i: DebugBuffer,
    pub s_all_seed: DebugBuffer,
    pub s_keep_seed: DebugBuffer,

    pub s_all_final: DebugBuffer,
    pub s_keep_final: DebugBuffer,

    pub end_positions_all: DebugBuffer,
    pub token_count_all: DebugBuffer,
    pub end_positions: DebugBuffer,
    pub types_compact: DebugBuffer,
    pub all_index_compact: DebugBuffer,
    pub token_count: DebugBuffer,
    pub tokens_out: DebugBuffer,
}

#[derive(Default)]
pub struct DebugOutput {
    pub gpu: DebugGpuBuffers,
}

fn make_staging(device: &wgpu::Device, label: &'static str, byte_len: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len as u64,
        usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
