//! GPU lexer module glue: just module wiring & re-exports.

pub mod buffers;
pub mod debug;
#[cfg(feature = "gpu-debug")]
pub mod debug_checks;
pub mod debug_host;
pub mod driver;
pub mod passes;
pub mod types;
pub mod util;

// Public API
pub use driver::{GpuLexer, lex_on_gpu};
// Keep these visible for submodules that refer to `super::LexParams`
pub(super) use types::LexParams;
pub use types::{GpuToken, Token};

pub use crate::gpu::{debug::DebugBuffer, passes_core::Pass};
