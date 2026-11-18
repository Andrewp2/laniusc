pub(crate) mod counted_scans;
pub(crate) mod dispatch_sizing;
pub(crate) mod function_ranges;
#[doc(hidden)]
pub mod input_capture;
/// GPU-resident target-independent and target-specific lowering contracts.
pub mod lowering_ir;
pub(crate) mod optimization;
pub(crate) mod optimization_ir;
pub(crate) mod pipeline;
pub(crate) mod scheduling;
pub(crate) mod semantics;
pub(crate) mod target_pages;
/// Wasm instruction selection, modules, and object projection.
pub(crate) mod wasm;
/// x86 instruction selection, emission, and object projection.
pub(crate) mod x86;
