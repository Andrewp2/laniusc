//! Shared GPU infrastructure for Lanius compiler

/// Typed buffer wrappers and allocation helpers.
pub mod buffers;
/// Logical compiler-pass ownership, access, and lifetime graph.
pub mod compiler_graph;
/// Optional debug readback buffer helpers.
pub mod debug;
/// Global device, queue, and pipeline-cache management.
pub mod device;
/// Environment flag parsing helpers for GPU infrastructure.
pub mod env;
/// Compiler-wide registry of reflected pipelines prepared before job timing.
pub(crate) mod kernels;
/// Reusable data-parallel operations assembled from reflected kernels.
pub(crate) mod operations;
/// Compute pass construction, bind groups, dispatch, and submission helpers.
pub mod passes_core;
/// Fixed-width readback decoders.
pub mod readback;
/// Name-keyed resources used to construct reflected compiler operations.
pub(crate) mod resource_registry;
/// Shared ping/pong prefix-scan planning helpers.
pub mod scan;
/// GPU timestamp-query helper.
pub mod timer;
/// Chrome/Perfetto trace event collection.
pub mod trace;
/// Checked phase-liveness planning for reusable whole-buffer workspace slots.
pub mod workspace;
