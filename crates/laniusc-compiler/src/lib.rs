//! GPU-resident compiler for the Lanius language.
//!
//! The crate is organized around the same phase boundaries used by the runtime
//! compiler: source loading, lexing, parsing/HIR construction, resident GPU type
//! checking, backend lowering, and source-pack planning/execution. The
//! maintainer guide for those boundaries lives in `docs/compiler/`.

/// Command-line entry points, argument validation, and user-facing command
/// output.
pub mod cli;

/// Backend lowering and source-pack unit planning.
pub mod codegen;

/// Public compile/check APIs, diagnostics, source-pack manifests, and
/// cross-phase orchestration.
pub mod compiler;

/// Development helpers and generated-workload support.
pub mod dev;

/// Source formatter support.
pub mod formatter;

/// Shared GPU device, buffer, pass, readback, scan, timing, and tracing
/// utilities.
pub mod gpu;

/// GPU lexer driver, buffers, token records, and lexer table integration.
pub mod lexer;

/// GPU parser driver, LL tables, HIR records, and parser readback helpers.
pub mod parser;

/// Slang reflection parsing and bind-layout interpretation.
pub mod reflection;

/// Generated shader artifact catalog used by runtime pass construction.
#[allow(dead_code)]
pub(crate) mod shader_artifacts;

/// Resident GPU type checking and retained semantic metadata for codegen.
pub mod type_checker;
