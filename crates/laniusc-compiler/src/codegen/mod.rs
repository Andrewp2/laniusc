//! Backend lowering and source-pack codegen planning.
//!
//! `unit` owns target-independent source-pack unit, job, artifact, and shard
//! planning. `x86` and `wasm` own target backend recorders that consume parser
//! HIR plus retained type-check metadata after frontend status success.

mod link_byte_source;
pub(crate) mod link_layout;
pub(crate) use link_byte_source::GpuLinkByteSource;

/// Target-independent source-pack unit, job, artifact, and shard planning.
pub mod unit;

/// GPU WASM backend recorder and backend status handling.
pub mod wasm;

/// GPU x86_64/ELF backend recorder, capacity model, and backend status handling.
pub mod x86;
