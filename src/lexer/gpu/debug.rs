// src/lexer/gpu/debug.rs
#![allow(dead_code)]

use crate::gpu::debug::DebugBuffer;
use wgpu::BufferUsages;

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

pub(crate) fn make_staging(device: &wgpu::Device, label: &'static str, byte_len: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len as u64,
        usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
