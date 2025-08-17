// src/parser/gpu/debug.rs
#![allow(dead_code)]

use crate::gpu::debug::DebugBuffer;

/// GPU-side debug snapshots for parser passes.
/// We mirror the style used by `src/lexer/gpu/debug.rs`.
#[derive(Default)]
pub struct DebugGpuBuffers {
    // llp_pairs
    pub out_headers: DebugBuffer,

    // pack_varlen
    pub sc_offsets: DebugBuffer,
    pub emit_offsets: DebugBuffer,
    pub out_sc: DebugBuffer,
    pub out_emit: DebugBuffer,

    // brackets_match
    pub match_for_index: DebugBuffer,
    pub depths_out: DebugBuffer,
    pub valid_out: DebugBuffer,
}

#[derive(Default)]
pub struct DebugOutput {
    pub gpu: DebugGpuBuffers,
}
