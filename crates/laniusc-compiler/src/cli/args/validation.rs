use std::path::{Path, PathBuf};

use crate::cli::{
    common::{
        CliError,
        LANIUS_EDITION_POLICY,
        LANIUS_EMIT_TARGETS,
        LANIUS_LANGUAGE_EDITION,
        LANIUS_TARGET_TRIPLES,
        LANIUS_X86_64_SUPPORT,
        incompatible_cli_options_error,
        missing_cli_argument_error,
        missing_cli_option_value_error,
        parse_usize_value,
        unsupported_cli_option_value_error,
    },
    source_pack,
};

/// Parses an optional numeric value for a CLI limit flag.
pub(super) fn parse_usize_cli_arg(flag: &str, value: Option<String>) -> Result<usize, CliError> {
    let value =
        value.ok_or_else(|| missing_cli_option_value_error(flag, "a non-negative integer"))?;
    parse_usize_cli_value(flag, &value)
}

/// Parses a numeric CLI limit flag from a string value.
pub(super) fn parse_usize_cli_value(flag: &str, value: &str) -> Result<usize, CliError> {
    parse_usize_value(flag, value).map_err(|err| {
        unsupported_cli_option_value_error(flag, value, "a non-negative integer", Some(err))
    })
}

/// Validates `--emit` and `--target` compatibility.
pub(super) fn validate_emit_and_target(
    emit: &str,
    target_triple: Option<&str>,
) -> Result<(), CliError> {
    if emit != "wasm" && emit != "x86_64" {
        return Err(unsupported_cli_option_value_error(
            "--emit",
            emit,
            LANIUS_EMIT_TARGETS,
            Some(format!("x86_64 currently supports {LANIUS_X86_64_SUPPORT}")),
        ));
    }
    if let Some(target_triple) = target_triple {
        let target_emit = emit_for_target_triple(target_triple).ok_or_else(|| {
            unsupported_cli_option_value_error(
                "--target",
                target_triple,
                LANIUS_TARGET_TRIPLES,
                Some("unsupported target triple".to_string()),
            )
        })?;
        if target_emit != emit {
            return Err(unsupported_cli_option_value_error(
                "--target",
                target_triple,
                LANIUS_TARGET_TRIPLES,
                Some(format!(
                    "--target {target_triple:?} requires --emit {target_emit}; requested --emit {emit}"
                )),
            ));
        }
    }
    Ok(())
}

/// Validates the requested language edition.
pub(super) fn validate_language_edition(language_edition: &str) -> Result<(), CliError> {
    if language_edition == LANIUS_LANGUAGE_EDITION {
        return Ok(());
    }
    Err(unsupported_cli_option_value_error(
        "--edition",
        language_edition,
        LANIUS_LANGUAGE_EDITION,
        Some(format!(
            "unsupported language edition; {LANIUS_EDITION_POLICY}"
        )),
    ))
}

/// Validates source-pack mode flags that are mutually exclusive by shape.
pub(super) fn validate_source_pack_options(
    source_pack: &source_pack::Options,
) -> Result<(), CliError> {
    if source_pack.manifest.is_some() && source_pack.library_manifest.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-manifest",
            "--source-pack-library-manifest",
            "choose either a whole source-pack manifest or one library manifest, not both",
        ));
    }
    Ok(())
}

/// Validates package manifest/lockfile mode against explicit source inputs.
pub(super) fn validate_package_mode(
    inputs: &[PathBuf],
    stdlib_paths: &[PathBuf],
    stdlib_root: Option<&Path>,
    source_roots: &[PathBuf],
    package_manifest: Option<&Path>,
    package_lockfile: Option<&Path>,
    source_pack: &source_pack::Options,
) -> Result<(), CliError> {
    if package_manifest.is_some()
        && (!inputs.is_empty()
            || !stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty())
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--package-manifest",
            "positional input files, --stdlib, --stdlib-root, or --source-root",
            "--package-manifest describes the entry, source roots, and stdlib root; do not also pass positional input files, --stdlib, --stdlib-root, or --source-root",
        ));
    }
    if package_lockfile.is_some()
        && (!inputs.is_empty()
            || !stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty()
            || package_manifest.is_some())
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--package-lockfile",
            "positional input files, --package-manifest, --stdlib, --stdlib-root, or --source-root",
            "--package-lockfile describes the resolved entry, source roots, and stdlib root; do not also pass positional input files, --package-manifest, --stdlib, --stdlib-root, or --source-root",
        ));
    }
    if package_lockfile.is_some() && source_pack.uses_source_pack_mode_flag() {
        if source_pack.uses_package_metadata_prepare_path() {
            return Ok(());
        }
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--package-lockfile",
            "final source-pack descriptor, build, or link output flags",
            "--package-lockfile currently supports source-pack metadata preparation only with --source-pack-metadata-only; final source-pack descriptor, build, and link output remain unsupported for package lockfiles",
        ));
    }
    if package_manifest.is_some() && source_pack.uses_source_pack_mode_flag() {
        if source_pack.uses_package_metadata_prepare_path() {
            return Ok(());
        }
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--package-manifest",
            "final source-pack descriptor, build, or link output flags",
            "--package-manifest currently supports source-pack metadata preparation only with --source-pack-metadata-only; final source-pack descriptor, build, and link output remain unsupported for package manifests",
        ));
    }
    Ok(())
}

/// Validates source-pack preparation and persisted-build option combinations.
pub(super) fn validate_source_pack_prepare_options(
    inputs: &[PathBuf],
    stdlib_paths: &[PathBuf],
    stdlib_root: Option<&Path>,
    source_roots: &[PathBuf],
    output: Option<&Path>,
    source_pack: &source_pack::Options,
) -> Result<(), CliError> {
    if source_pack.metadata_only && source_pack.build_from_metadata {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-metadata-only",
            "--source-pack-build-from-metadata",
            "choose either metadata preparation from source-pack inputs or build execution from persisted metadata, not both",
        ));
    }
    if source_pack.prepare_only && source_pack.metadata_only {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-prepare-only",
            "--source-pack-metadata-only",
            "choose one bounded preparation stage: prepare metadata-only library inputs or run the next queued source-pack preparation chunk",
        ));
    }
    if source_pack.prepare_only && source_pack.build_prepare_only {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-prepare-only",
            "--source-pack-build-prepare-only",
            "choose one bounded preparation stage: prepare source-pack inputs or prepare build work from persisted metadata",
        ));
    }
    if source_pack.prepare_only && source_pack.build_from_metadata {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-prepare-only",
            "--source-pack-build-from-metadata",
            "--source-pack-prepare-only prepares from source-pack inputs; use --source-pack-build-from-metadata --source-pack-build-prepare-only for persisted metadata",
        ));
    }
    if source_pack.build_from_metadata
        && (source_pack.manifest.is_some()
            || source_pack.library_manifest.is_some()
            || !stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty()
            || !inputs.is_empty())
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-build-from-metadata",
            "source-pack input flags or positional source files",
            "--source-pack-build-from-metadata reads persisted metadata from --source-pack-artifact-root; do not also pass source-pack inputs",
        ));
    }
    if source_pack.metadata_only && output.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-metadata-only",
            "-o/--out",
            "--source-pack-metadata-only writes persisted metadata only; omit -o/--out because no target bytes are emitted",
        ));
    }
    if source_pack.prepare_only && output.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-prepare-only",
            "-o/--out",
            "--source-pack-prepare-only advances persisted preparation only; omit -o/--out because no target bytes are emitted",
        ));
    }
    if source_pack.build_prepare_only && output.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-build-prepare-only",
            "-o/--out",
            "--source-pack-build-prepare-only prepares persisted build work only; omit -o/--out because no target bytes are emitted",
        ));
    }
    if source_pack.build_prepare_only && !source_pack.build_from_metadata {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-build-prepare-only",
            "metadata-free source-pack compilation",
            "add --source-pack-build-from-metadata when preparing build work from persisted metadata",
        ));
    }
    if source_pack.metadata_max_libraries.is_some()
        && !source_pack.metadata_only
        && !source_pack.prepare_only
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-metadata-max-libraries",
            "metadata-free source-pack modes",
            "--source-pack-metadata-max-libraries only applies with --source-pack-metadata-only or --source-pack-prepare-only",
        ));
    }
    if source_pack.metadata_max_source_files.is_some()
        && !source_pack.metadata_only
        && !source_pack.prepare_only
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-metadata-max-source-files",
            "metadata-free source-pack modes",
            "--source-pack-metadata-max-source-files only applies with --source-pack-metadata-only or --source-pack-prepare-only",
        ));
    }
    if source_pack.metadata_max_libraries == Some(0) {
        return Err(unsupported_cli_option_value_error(
            "--source-pack-metadata-max-libraries",
            "0",
            "an integer greater than zero",
            Some("--source-pack-metadata-max-libraries must be greater than zero".to_string()),
        ));
    }
    if source_pack.metadata_max_source_files == Some(0) {
        return Err(unsupported_cli_option_value_error(
            "--source-pack-metadata-max-source-files",
            "0",
            "an integer greater than zero",
            Some("--source-pack-metadata-max-source-files must be greater than zero".to_string()),
        ));
    }
    if source_pack.build_max_items == 0 {
        return Err(unsupported_cli_option_value_error(
            "--source-pack-build-max-items",
            "0",
            "an integer greater than zero",
            Some("--source-pack-build-max-items must be greater than zero".to_string()),
        ));
    }
    if (source_pack.manifest.is_some() || source_pack.library_manifest.is_some())
        && (!stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty()
            || !inputs.is_empty())
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-manifest/--source-pack-library-manifest",
            "--stdlib, --stdlib-root, --source-root, or positional input files",
            "--source-pack-manifest and --source-pack-library-manifest describe all source-pack libraries; do not also pass --stdlib, --stdlib-root, --source-root, or positional input files",
        ));
    }
    Ok(())
}

/// Validates diagnostics-only `check` mode constraints.
pub(super) fn validate_check_mode(
    check_only: bool,
    output: Option<&Path>,
    inputs: &[PathBuf],
    package_manifest: Option<&Path>,
    package_lockfile: Option<&Path>,
    stdlib_paths: &[PathBuf],
    source_pack: &source_pack::Options,
) -> Result<(), CliError> {
    if check_only && output.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc check",
            "-o/--out",
            "diagnostics-only check mode",
            "omit -o/--out because check mode does not write target bytes",
        ));
    }
    if check_only
        && (source_pack.uses_source_pack_mode_flag()
            || !stdlib_paths.is_empty()
            || inputs.len() > 1)
    {
        return Err(incompatible_cli_options_error(
            "laniusc check",
            "--check",
            "explicit source-pack descriptor, metadata, prepare, contract, artifact-root, --stdlib, or multi-input flags",
            "check mode currently supports single-entry in-memory, source-root, stdlib-root, package-manifest, and package-lockfile compile paths; omit explicit source-pack descriptor, metadata, prepare, contract, artifact-root, --stdlib, or multi-input flags",
        ));
    }
    if check_only && inputs.is_empty() && package_manifest.is_none() && package_lockfile.is_none() {
        return Err(missing_cli_argument_error(
            "laniusc check",
            "an input file, --package-manifest, or --package-lockfile",
        ));
    }
    Ok(())
}

/// Validates that descriptor-producing source-pack modes are requested
/// explicitly as contract output.
pub(super) fn validate_descriptor_output(
    uses_source_pack: bool,
    source_pack: &source_pack::Options,
) -> Result<(), CliError> {
    if source_pack.requests_contract_descriptor_output(uses_source_pack)
        && !source_pack.emit_contract
    {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "source-pack descriptor mode",
            "implicit target-byte output",
            "pass --emit-contract to write linked-output contract descriptors",
        ));
    }
    Ok(())
}

fn emit_for_target_triple(target_triple: &str) -> Option<&'static str> {
    match target_triple {
        "wasm32-unknown-unknown" => Some("wasm"),
        "x86_64-unknown-linux-gnu" => Some("x86_64"),
        _ => None,
    }
}
