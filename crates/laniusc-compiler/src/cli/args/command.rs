use std::path::PathBuf;

use crate::cli::source_pack;

/// Parsed top-level CLI command after global argument handling.
pub(crate) enum Command {
    /// Print full CLI help and exit successfully.
    Help,
    /// Print compiler/tooling version metadata and exit successfully.
    Version,
    /// Forward remaining args to `laniusc fmt`.
    Fmt(Vec<String>),
    /// Forward remaining args to `laniusc doctor`.
    Doctor(Vec<String>),
    /// Forward remaining args to `laniusc daemon`.
    Daemon(Vec<String>),
    /// Forward remaining args to `laniusc package`.
    Package(Vec<String>),
    /// Forward remaining args to `laniusc lsp`.
    Lsp(Vec<String>),
    /// Forward remaining args to `laniusc diagnostics`.
    Diagnostics(Vec<String>),
    /// Compile or check source using the parsed compile request.
    Compile(CompileRequest),
}

/// Fully validated compile/check request.
///
/// This is the CLI boundary object passed into compile dispatch. It records the
/// selected input mode, target mode, output path, and source-pack controls; it
/// does not contain compiler semantic results.
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
