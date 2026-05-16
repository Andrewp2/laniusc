pub mod buffers;
pub mod debug;
pub mod driver;
pub mod passes;
pub mod tables;
pub mod types;
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
