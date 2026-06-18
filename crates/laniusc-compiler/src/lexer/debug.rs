// src/lexer/debug.rs
#![allow(dead_code)]

use wgpu::BufferUsages;

use crate::gpu::debug::DebugBuffer;

#[derive(Default)]
/// Optional debug readback buffers for one lexer run.
pub struct DebugGpuBuffers {
    /// Source byte snapshot.
    pub in_bytes: DebugBuffer,

    /// DFA block summaries.
    pub block_summaries: DebugBuffer,
    /// DFA/pair ping scratch snapshot.
    pub block_ping: DebugBuffer,
    /// DFA/pair pong scratch snapshot.
    pub block_pong: DebugBuffer,
    /// Applied DFA block-prefix snapshot.
    pub block_prefix: DebugBuffer,
    /// Final DFA state snapshot.
    pub f_final: DebugBuffer,

    /// Raw token kinds by byte boundary.
    pub tok_types: DebugBuffer,
    /// Legacy end-position tap retained for debug consumers.
    pub end_excl_by_i: DebugBuffer,

    /// Single packed boundary/keep flags buffer.
    pub flags_packed: DebugBuffer,

    /// Pair-scan per-block totals.
    pub block_totals_pair: DebugBuffer,
    /// Pair-scan ping snapshot.
    pub block_pair_ping: DebugBuffer,
    /// Pair-scan pong snapshot.
    pub block_pair_pong: DebugBuffer,
    /// Applied pair block-prefix snapshot.
    pub block_prefix_pair: DebugBuffer,

    /// Compact ranks for all token boundaries.
    pub s_all_final: DebugBuffer,
    /// Compact ranks for kept token boundaries.
    pub s_keep_final: DebugBuffer,

    /// End positions for all token boundaries.
    pub end_positions_all: DebugBuffer,
    /// Count for all token boundaries.
    pub token_count_all: DebugBuffer,
    /// End positions for kept tokens.
    pub end_positions: DebugBuffer,
    /// Token kinds compacted to kept-token order.
    pub types_compact: DebugBuffer,
    /// Mapping from kept-token order to all-boundary order.
    pub all_index_compact: DebugBuffer,
    /// Kept token count.
    pub token_count: DebugBuffer,
    /// Final token records.
    pub tokens_out: DebugBuffer,

    /// Per-round DFA block-summary scan snapshots.
    pub func_scan_rounds: Vec<DebugBuffer>,
    /// Per-round pair-total scan snapshots.
    pub pair_scan_rounds: Vec<DebugBuffer>,
}

#[derive(Default)]
/// Root debug output object threaded through lexer pass recording.
pub struct DebugOutput {
    /// GPU buffer snapshots.
    pub gpu: DebugGpuBuffers,
}

/// Creates a map-readable staging buffer for lexer debug snapshots.
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
