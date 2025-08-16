// src/lexer/gpu/debug.rs
#![allow(dead_code)]

use wgpu::BufferUsages;

use crate::gpu::debug::DebugBuffer;

#[derive(Default)]
pub struct DebugGpuBuffers {
    pub in_bytes: DebugBuffer,

    pub block_summaries: DebugBuffer,
    pub block_ping: DebugBuffer,
    pub block_pong: DebugBuffer,
    pub block_prefix: DebugBuffer,
    pub f_final: DebugBuffer,

    pub tok_types: DebugBuffer,
    pub end_excl_by_i: DebugBuffer,

    // Single packed flags buffer in use
    pub flags_packed: DebugBuffer,

    // Pair-sum hierarchy
    pub block_totals_pair: DebugBuffer,
    pub block_pair_ping: DebugBuffer,
    pub block_pair_pong: DebugBuffer,
    pub block_prefix_pair: DebugBuffer,

    pub s_all_final: DebugBuffer,
    pub s_keep_final: DebugBuffer,

    pub end_positions_all: DebugBuffer,
    pub token_count_all: DebugBuffer,
    pub end_positions: DebugBuffer,
    pub types_compact: DebugBuffer,
    pub all_index_compact: DebugBuffer,
    pub token_count: DebugBuffer,
    pub tokens_out: DebugBuffer,

    // NEW: per-round snapshots for a single `lex` run
    // One DebugBuffer per round, in order (r = 0..rounds-1)
    pub func_scan_rounds: Vec<DebugBuffer>, // scan_block_summaries_inclusive (uint[N_STATES] per block)
    pub pair_scan_rounds: Vec<DebugBuffer>, // sum_scan_block_totals_inclusive (uint2 per block)
}

#[derive(Default)]
pub struct DebugOutput {
    pub gpu: DebugGpuBuffers,
}

pub(crate) fn make_staging(
    device: &wgpu::Device,
    label: &'static str,
    byte_len: usize,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len as u64,
        usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
