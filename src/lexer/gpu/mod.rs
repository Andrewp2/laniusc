//! GPU lexer module glue: just module wiring & re-exports.

mod buffers;
mod debug;
#[cfg(feature = "gpu-debug")]
mod debug_checks;
pub mod debug_host;
mod driver;
mod passes;
mod types;
mod util;

// Public API
pub use driver::{GpuLexer, lex_on_gpu};
// Keep these visible for submodules that refer to `super::LexParams`
pub(super) use types::LexParams;
pub use types::{GpuToken, Token};
// (Re-)export internal helpers for in-crate use (no implementations here)
pub(crate) use util::{env_flag_true, read_tokens_from_mapped, readback_enabled, u32_from_first_4};

pub use crate::gpu::{debug::DebugBuffer, passes_core::Pass};
