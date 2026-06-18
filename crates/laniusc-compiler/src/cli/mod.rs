//! Command-line interface for `laniusc`.
//!
//! This module owns argument parsing, CLI validation, diagnostic rendering
//! selection, command dispatch, no-run metadata commands, source-pack command
//! plumbing, and output writing. Compiler semantics stay in `crate::compiler`
//! and phase modules.

mod args;
mod common;
mod compile;
mod diagnostics;
mod dispatch;
mod doctor;
mod entry;
mod fmt;
mod help;
mod lsp;
mod output;
mod package;
mod source_pack;

pub use entry::run_from_env;
