use std::path::Path;

use crate::{
    cli::{
        common::{CliError, package_compile_cli_error, package_metadata_cli_error},
        output::CliEmission,
        source_pack::{self, Options},
    },
    compiler::{
        PackageLockfile,
        PackageManifest,
        compile_entry_to_wasm_with_source_roots,
        compile_entry_to_x86_64_with_source_roots,
        type_check_entry_with_source_roots,
    },
};

pub(super) fn compile_manifest(
    manifest_path: &Path,
    check_only: bool,
    emit: &str,
) -> Result<CliEmission, CliError> {
    let package = PackageManifest::load_json_file(manifest_path)
        .map_err(|err| package_metadata_cli_error("--package-manifest", manifest_path, err))?;
    let roots = package.to_entry_source_roots();
    if check_only {
        pollster::block_on(type_check_entry_with_source_roots(&package.entry, &roots))
            .map_err(|err| package_compile_cli_error("--package-manifest", manifest_path, err))?;
        Ok(CliEmission::Bytes(Vec::new()))
    } else if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_wasm_with_source_roots(
                &package.entry,
                &roots,
            ))
            .map_err(|err| package_compile_cli_error("--package-manifest", manifest_path, err))?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_x86_64_with_source_roots(
                &package.entry,
                &roots,
            ))
            .map_err(|err| package_compile_cli_error("--package-manifest", manifest_path, err))?,
        ))
    }
}

pub(super) fn compile_lockfile(
    lockfile_path: &Path,
    check_only: bool,
    emit: &str,
) -> Result<CliEmission, CliError> {
    let package = PackageLockfile::load_json_file(lockfile_path)
        .map_err(|err| package_metadata_cli_error("--package-lockfile", lockfile_path, err))?;
    let roots = package.to_entry_source_roots();
    if check_only {
        pollster::block_on(type_check_entry_with_source_roots(&package.entry, &roots))
            .map_err(|err| package_compile_cli_error("--package-lockfile", lockfile_path, err))?;
        Ok(CliEmission::Bytes(Vec::new()))
    } else if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_wasm_with_source_roots(
                &package.entry,
                &roots,
            ))
            .map_err(|err| package_compile_cli_error("--package-lockfile", lockfile_path, err))?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_x86_64_with_source_roots(
                &package.entry,
                &roots,
            ))
            .map_err(|err| package_compile_cli_error("--package-lockfile", lockfile_path, err))?,
        ))
    }
}

pub(super) fn prepare_manifest_metadata_only(
    emit: &str,
    manifest_path: &Path,
    source_pack_options: &Options,
) -> Result<(), CliError> {
    ensure_package_metadata_artifact_root(source_pack_options)?;
    let package = PackageManifest::load_json_file(manifest_path)
        .map_err(|err| package_metadata_cli_error("--package-manifest", manifest_path, err))?;
    let path_manifest = package
        .load_path_manifest()
        .map_err(|err| package_metadata_cli_error("--package-manifest", manifest_path, err))?;
    source_pack::prepare_path_manifest_metadata_only(
        emit,
        path_manifest,
        source_pack_options,
        "--package-manifest",
        manifest_path,
    )
    .map_err(CliError::from)
}

pub(super) fn prepare_lockfile_metadata_only(
    emit: &str,
    lockfile_path: &Path,
    source_pack_options: &Options,
) -> Result<(), CliError> {
    ensure_package_metadata_artifact_root(source_pack_options)?;
    let package = PackageLockfile::load_json_file(lockfile_path)
        .map_err(|err| package_metadata_cli_error("--package-lockfile", lockfile_path, err))?;
    let path_manifest = package
        .load_path_manifest()
        .map_err(|err| package_metadata_cli_error("--package-lockfile", lockfile_path, err))?;
    source_pack::prepare_path_manifest_metadata_only(
        emit,
        path_manifest,
        source_pack_options,
        "--package-lockfile",
        lockfile_path,
    )
    .map_err(CliError::from)
}

fn ensure_package_metadata_artifact_root(source_pack_options: &Options) -> Result<(), CliError> {
    if source_pack_options.artifact_root.is_some() {
        return Ok(());
    }
    Err("--source-pack-metadata-only requires --source-pack-artifact-root".into())
}
