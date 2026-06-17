use std::path::PathBuf;

use crate::cli::source_pack;

pub(crate) enum Command {
    Help,
    Version,
    Fmt(Vec<String>),
    Doctor(Vec<String>),
    Package(Vec<String>),
    Lsp(Vec<String>),
    Diagnostics(Vec<String>),
    Compile(CompileRequest),
}

pub(crate) struct CompileRequest {
    pub(crate) inputs: Vec<PathBuf>,
    pub(crate) stdlib_paths: Vec<PathBuf>,
    pub(crate) stdlib_root: Option<PathBuf>,
    pub(crate) source_roots: Vec<PathBuf>,
    pub(crate) package_manifest: Option<PathBuf>,
    pub(crate) package_lockfile: Option<PathBuf>,
    pub(crate) output: Option<PathBuf>,
    pub(crate) emit: String,
    pub(crate) check_only: bool,
    pub(crate) source_pack: source_pack::Options,
    pub(crate) uses_source_pack: bool,
}
