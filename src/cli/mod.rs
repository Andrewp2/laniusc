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

pub(crate) use entry::run_from_env;
