use std::path::{Path, PathBuf};

use super::package;
use crate::cli::{
    common::CliError,
    output::CliEmission,
    source_pack::{
        Options,
        compile_direct,
        compile_from_metadata,
        compile_library_manifest,
        compile_manifest,
        prepare_build_from_metadata_chunk_only,
        prepare_inputs_chunk_only,
        prepare_metadata_only,
    },
};

/// Compile dispatch result for source-pack mode selection.
pub(super) enum Action {
    /// The requested source-pack preparation step completed without target bytes.
    Done,
    /// A source-pack path produced CLI output.
    Emit(CliEmission),
    /// Source-pack mode was not requested; fall back to in-memory compile.
    NotRequested,
}

/// Selects the source-pack CLI action for a validated compile request.
pub(super) fn dispatch(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    package_manifest: Option<&Path>,
    package_lockfile: Option<&Path>,
    options: &Options,
    requested: bool,
) -> Result<Action, CliError> {
    if options.metadata_only {
        if let Some(package_manifest) = package_manifest {
            package::prepare_manifest_metadata_only(emit, package_manifest, options)?;
            return Ok(Action::Done);
        }
        if let Some(package_lockfile) = package_lockfile {
            package::prepare_lockfile_metadata_only(emit, package_lockfile, options)?;
            return Ok(Action::Done);
        }
        prepare_metadata_only(emit, stdlib_paths, inputs, options)?;
        return Ok(Action::Done);
    }
    if options.prepare_only {
        prepare_inputs_chunk_only(emit, stdlib_paths, inputs, options)?;
        return Ok(Action::Done);
    }
    if options.build_prepare_only {
        prepare_build_from_metadata_chunk_only(emit, options)?;
        return Ok(Action::Done);
    }

    if options.build_from_metadata {
        return Ok(Action::Emit(CliEmission::ContractDescriptorFile(
            compile_from_metadata(emit, options)?,
        )));
    }
    if options.library_manifest.is_some() {
        return Ok(Action::Emit(CliEmission::ContractDescriptorFile(
            compile_library_manifest(emit, options)?,
        )));
    }
    if options.manifest.is_some() {
        return Ok(Action::Emit(CliEmission::ContractDescriptorFile(
            compile_manifest(emit, options)?,
        )));
    }
    if !requested {
        return Ok(Action::NotRequested);
    }
    let _ = (stdlib_paths, inputs);
    Ok(Action::Emit(CliEmission::ContractDescriptorFile(
        compile_direct(emit, options)?,
    )))
}
