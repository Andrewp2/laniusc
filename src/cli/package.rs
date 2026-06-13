use std::{
    env,
    fs,
    path::{Path, PathBuf},
};

use laniusc::compiler::{Diagnostic, PackageLockfile, PackageManifest};

use super::{
    common::{
        CliError,
        LANIUS_DIAGNOSTIC_FORMATS,
        incompatible_cli_options_error,
        missing_cli_argument_error,
        missing_cli_option_value_error,
        missing_cli_subcommand_error,
        package_metadata_cli_error,
        unknown_cli_option_error,
        unknown_cli_subcommand_error,
        validate_diagnostic_format,
    },
    help::{print_package_help, print_package_lock_help},
};

pub(crate) fn run(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut args = args.into_iter().peekable();
    loop {
        let Some(command) = args.next() else {
            return Err(missing_cli_subcommand_error("laniusc package", "lock"));
        };

        match command.as_str() {
            "-h" | "--help" => {
                print_package_help();
                return Ok(());
            }
            "--diagnostic-format" => {
                let value = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--diagnostic-format",
                        format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                    )
                })?;
                validate_diagnostic_format(&value)?;
            }
            flag if flag.starts_with("--diagnostic-format=") => {
                validate_diagnostic_format(flag.trim_start_matches("--diagnostic-format="))?;
            }
            "lock" => return run_package_lock(args),
            other => {
                return Err(unknown_cli_subcommand_error(
                    "laniusc package",
                    other,
                    "lock",
                ));
            }
        }
    }
}

fn run_package_lock(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut manifest: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;
    let mut args = args.into_iter();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_package_lock_help();
                return Ok(());
            }
            "--manifest" => {
                manifest = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--manifest", "a path")
                })?));
            }
            "-o" | "--out" => {
                output = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(&arg, "an output path")
                })?));
            }
            "--diagnostic-format" => {
                let value = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--diagnostic-format",
                        format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                    )
                })?;
                validate_diagnostic_format(&value)?;
            }
            flag if flag.starts_with("--manifest=") => {
                let value = flag.trim_start_matches("--manifest=");
                if value.is_empty() {
                    return Err(missing_cli_option_value_error("--manifest", "a path"));
                }
                manifest = Some(PathBuf::from(value));
            }
            flag if flag.starts_with("--out=") => {
                let value = flag.trim_start_matches("--out=");
                if value.is_empty() {
                    return Err(missing_cli_option_value_error("--out", "an output path"));
                }
                output = Some(PathBuf::from(value));
            }
            flag if flag.starts_with("--diagnostic-format=") => {
                validate_diagnostic_format(flag.trim_start_matches("--diagnostic-format="))?;
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc package lock",
                    flag,
                    "--help, --manifest, -o/--out, --diagnostic-format",
                ));
            }
            path => {
                return Err(package_lock_positional_argument_error(path));
            }
        }
    }

    let manifest_path = manifest
        .ok_or_else(|| missing_cli_argument_error("laniusc package lock", "--manifest path"))?;
    let output = output
        .ok_or_else(|| missing_cli_argument_error("laniusc package lock", "-o/--out path"))?;
    let manifest = PackageManifest::load_json_file(&manifest_path).map_err(|err| {
        package_metadata_cli_error("package lock --manifest", &manifest_path, err)
    })?;
    validate_package_lock_output_path(&manifest_path, &output)?;
    let lockfile = PackageLockfile::from_resolved_manifest(&manifest).map_err(|err| {
        package_metadata_cli_error("package lock --manifest", &manifest_path, err)
    })?;
    lockfile.write_json_file(&output).map_err(|err| {
        package_metadata_cli_error("package lock --manifest", &manifest_path, err)
    })?;
    Ok(())
}

fn validate_package_lock_output_path(
    manifest_path: &Path,
    output_path: &Path,
) -> Result<(), CliError> {
    let Some(manifest_identity) = package_lock_cli_identity_path(manifest_path) else {
        return Ok(());
    };
    let Some(output_identity) = package_lock_cli_identity_path(output_path) else {
        return Ok(());
    };
    if manifest_identity == output_identity {
        return Err(incompatible_cli_options_error(
            "laniusc package lock",
            "-o/--out",
            "--manifest path",
            &format!(
                "package lock output path {} would overwrite package manifest {}; choose a separate lockfile path",
                output_identity.display(),
                manifest_identity.display()
            ),
        ));
    }
    Ok(())
}

fn package_lock_cli_identity_path(path: &Path) -> Option<PathBuf> {
    if let Ok(canonical_path) = fs::canonicalize(path) {
        return Some(canonical_path);
    }

    let absolute_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        env::current_dir().ok()?.join(path)
    };
    let mut existing_prefix = absolute_path.as_path();

    loop {
        if let Ok(canonical_prefix) = fs::canonicalize(existing_prefix) {
            let missing_tail = absolute_path.strip_prefix(existing_prefix).ok()?;
            return apply_missing_package_lock_output_tail(canonical_prefix, missing_tail);
        }
        existing_prefix = existing_prefix.parent()?;
    }
}

fn apply_missing_package_lock_output_tail(mut base: PathBuf, tail: &Path) -> Option<PathBuf> {
    for component in tail.components() {
        match component {
            std::path::Component::Normal(segment) => base.push(segment),
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if !base.pop() {
                    return None;
                }
            }
            std::path::Component::Prefix(_) | std::path::Component::RootDir => return None,
        }
    }
    Some(base)
}

fn package_lock_positional_argument_error(argument: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0031", "unexpected CLI argument")
            .with_note(format!(
                "laniusc package lock does not accept positional input file {argument:?}"
            ))
            .with_note(
                "accepted laniusc package lock arguments/options: --help, --manifest, -o/--out, --diagnostic-format"
                    .to_string(),
            ),
    )
}
