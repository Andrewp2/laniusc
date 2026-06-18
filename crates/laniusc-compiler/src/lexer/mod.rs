//! GPU lexer phase.
//!
//! The lexer owns compact DFA table loading, source byte upload, source-pack
//! file metadata, the GPU pass sequence that emits token boundaries, and the
//! resident token buffers consumed by parser and compile paths.

/// Resident lexer buffer model.
pub mod buffers;
/// Optional lexer debug readback buffers.
pub mod debug;
/// GPU lexer driver and global lexer entry points.
pub mod driver;
/// GPU shader pass declarations for lexing.
pub mod passes;
/// Lexer DFA and token tables.
pub mod tables;
/// Host and GPU token record types.
pub mod types;
/// Small lexer helpers shared by driver and tests.
pub mod util;

pub use driver::{GpuLexer, lex_on_gpu};
pub(super) use types::LexParams;
pub use types::{GpuToken, Token};

pub use crate::gpu::{debug::DebugBuffer, passes_core::Pass};

/// TEST-ONLY CPU lexer oracle.
///
/// This module exists for integration tests and fuzz-test tooling that compare
/// GPU lexer output against an intentionally named host oracle. Compiler code
/// must not call it or use it as a fallback.
#[doc(hidden)]
pub mod test_cpu;
