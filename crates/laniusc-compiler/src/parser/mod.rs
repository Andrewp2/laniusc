//! GPU parser, parse tables, tree recovery, and HIR record construction.
//!
//! The parser consumes resident lexer token buffers and precomputed parse
//! tables, then produces parser token facts, packed production streams, tree
//! topology, semantic HIR topology, and typed HIR record arrays for type
//! checking and backend lowering.

/// Parser buffer models and GPU buffer allocation helpers.
pub mod buffers;

/// Debug buffer snapshots and parser debug output containers.
pub mod debug;

/// Resident GPU parser driver and high-level parser entry points.
pub mod driver;

/// Compact helpers for parser-owned HIR record words.
pub mod hir_records;

/// Parser compute pass wrappers grouped by pipeline stage.
pub mod passes;

/// Debug/readback conversion and parser-owned HIR validation.
pub mod readback;

/// Standalone syntax-checking entry points.
pub mod syntax;

/// Precomputed parser table data and CPU table oracles.
pub mod tables;

pub use driver::*;
