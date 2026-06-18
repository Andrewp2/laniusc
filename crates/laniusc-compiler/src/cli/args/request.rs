use std::path::PathBuf;

use super::{
    command::CompileRequest,
    validation::{
        validate_check_mode,
        validate_descriptor_output,
        validate_emit_and_target,
        validate_language_edition,
        validate_package_mode,
        validate_source_pack_options,
        validate_source_pack_prepare_options,
    },
};
use crate::cli::{
    common::{
        CliError,
        LANIUS_DEFAULT_EMIT_TARGET,
        LANIUS_LANGUAGE_EDITION,
        canonical_directory_path,
        canonical_unique_directory_paths,
    },
    source_pack,
};

/// Mutable builder used while parsing compile/check flags.
///
/// The builder accepts options in CLI order and performs cross-option
/// validation only in `finish`, once all positional files and flags are known.
pub(super) struct CompileRequestBuilder {
    pub(super) inputs: Vec<PathBuf>,
    pub(super) stdlib_paths: Vec<PathBuf>,
    pub(super) stdlib_root: Option<PathBuf>,
    pub(super) source_roots: Vec<PathBuf>,
    pub(super) package_manifest: Option<PathBuf>,
    pub(super) package_lockfile: Option<PathBuf>,
    pub(super) output: Option<PathBuf>,
    pub(super) emit: String,
    pub(super) target_triple: Option<String>,
    pub(super) language_edition: String,
    pub(super) check_only: bool,
    pub(super) source_pack: source_pack::Options,
}

impl Default for CompileRequestBuilder {
    fn default() -> Self {
        Self {
            inputs: Vec::new(),
            stdlib_paths: Vec::new(),
            stdlib_root: None,
            source_roots: Vec::new(),
            package_manifest: None,
            package_lockfile: None,
            output: None,
            emit: LANIUS_DEFAULT_EMIT_TARGET.to_string(),
            target_triple: None,
            language_edition: LANIUS_LANGUAGE_EDITION.to_string(),
            check_only: false,
            source_pack: source_pack::Options::default(),
        }
    }
}

impl CompileRequestBuilder {
    /// Validates cross-option constraints and returns the immutable request.
    pub(super) fn finish(self) -> Result<CompileRequest, CliError> {
        let Self {
            inputs,
            stdlib_paths,
            stdlib_root,
            source_roots,
            package_manifest,
            package_lockfile,
            output,
            emit,
            target_triple,
            language_edition,
            check_only,
            source_pack,
        } = self;

        validate_emit_and_target(&emit, target_triple.as_deref())?;
        validate_language_edition(&language_edition)?;
        validate_source_pack_options(&source_pack)?;
        validate_package_mode(
            &inputs,
            &stdlib_paths,
            stdlib_root.as_deref(),
            &source_roots,
            package_manifest.as_deref(),
            package_lockfile.as_deref(),
            &source_pack,
        )?;
        validate_source_pack_prepare_options(
            &inputs,
            &stdlib_paths,
            stdlib_root.as_deref(),
            &source_roots,
            output.as_deref(),
            &source_pack,
        )?;

        let source_root_requested = !source_roots.is_empty() || stdlib_root.is_some();
        if source_root_requested && !stdlib_paths.is_empty() {
            return Err(
                "--source-root and --stdlib-root discover module-path imports; do not combine them with explicit --stdlib source files"
                    .into(),
            );
        }
        if source_root_requested && source_pack.conflicts_with_source_root_compile() {
            return Err(
                "--source-root and --stdlib-root currently use the in-memory source-pack path; omit descriptor/prepare/artifact-root flags or use --source-pack-library-manifest for bounded descriptor preparation"
                    .into(),
            );
        }
        if source_root_requested && inputs.len() != 1 {
            return Err("--source-root/--stdlib-root requires exactly one entry input file".into());
        }
        let source_roots = if source_root_requested {
            canonical_unique_directory_paths("source root", source_roots)?
        } else {
            source_roots
        };
        let stdlib_root = if source_root_requested {
            stdlib_root
                .map(|path| canonical_directory_path("stdlib root", path))
                .transpose()?
        } else {
            stdlib_root
        };

        let uses_source_pack =
            source_pack.uses_source_pack_compile_path(!stdlib_paths.is_empty(), inputs.len());
        let uses_package_metadata_prepare_path = (package_manifest.is_some()
            || package_lockfile.is_some())
            && source_pack.uses_package_metadata_prepare_path();
        if uses_source_pack
            && inputs.is_empty()
            && source_pack.manifest.is_none()
            && source_pack.library_manifest.is_none()
            && !source_pack.build_from_metadata
            && !uses_package_metadata_prepare_path
        {
            return Err("explicit source-pack compilation requires at least one input file".into());
        }
        validate_check_mode(
            check_only,
            output.as_deref(),
            &inputs,
            package_manifest.as_deref(),
            package_lockfile.as_deref(),
            &stdlib_paths,
            &source_pack,
        )?;
        validate_descriptor_output(uses_source_pack, &source_pack)?;

        Ok(CompileRequest {
            inputs,
            stdlib_paths,
            stdlib_root,
            source_roots,
            package_manifest,
            package_lockfile,
            output,
            emit,
            check_only,
            source_pack,
            uses_source_pack,
        })
    }
}
