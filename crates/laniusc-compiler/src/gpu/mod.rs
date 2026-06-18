//! Shared GPU infrastructure for Lanius compiler

/// Typed buffer wrappers and allocation helpers.
pub mod buffers;
/// Optional debug readback buffer helpers.
pub mod debug;
/// Global device, queue, and pipeline-cache management.
pub mod device;
/// Environment flag parsing helpers for GPU infrastructure.
pub mod env;
/// Compute pass construction, bind groups, dispatch, and submission helpers.
pub mod passes_core;
/// Fixed-width readback decoders.
pub mod readback;
/// Shared ping/pong prefix-scan planning helpers.
pub mod scan;
/// GPU timestamp-query helper.
pub mod timer;
/// Chrome/Perfetto trace event collection.
pub mod trace;
