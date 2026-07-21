//! Backend lowering and source-pack codegen planning.
//!
//! `unit` owns target-independent source-pack unit, job, artifact, and shard
//! planning. `x86` and `wasm` own target backend recorders that consume parser
//! HIR plus retained type-check metadata after frontend status success.

pub(crate) mod functions;
mod link_byte_source;
pub(crate) mod link_layout;
pub(crate) mod lowering;
/// GPU-resident target-independent and target-specific lowering contracts.
pub mod lowering_ir;
pub(crate) mod lowering_pipeline;
pub(crate) mod scan;
pub(crate) mod schedule;
pub(crate) mod wasm_lowering;
pub(crate) mod wasm_module;
pub(crate) mod x86_artifact;
pub(crate) mod x86_lowering;
pub(crate) use link_byte_source::GpuLinkByteSource;

/// Target-independent source-pack unit, job, artifact, and shard planning.
pub mod unit;

/// GPU WASM backend recorder and backend status handling.
pub mod wasm;

/// GPU x86_64/ELF backend recorder, capacity model, and backend status handling.
pub mod x86;
