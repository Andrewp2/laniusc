use std::{fs, path::PathBuf};

use super::request::CompileRequestBuilder;
use crate::{
    cli::common::{CliError, canonical_directory_path, missing_cli_option_value_error},
    compiler::{Diagnostic, NativeLinkOptions},
};

/// Parses options that select the native C executable profile.
pub(super) fn parse_arg<I>(
    arg: &str,
    args: &mut I,
    request: &mut CompileRequestBuilder,
) -> Result<bool, CliError>
where
    I: Iterator<Item = String>,
{
    if arg == "--native-link" {
        request
            .native_link
            .get_or_insert_with(NativeLinkOptions::default);
        return Ok(true);
    }
    let (flag, value) = match arg.split_once('=') {
        Some((flag, value)) => (flag, Some(value.to_string())),
        None => (arg, None),
    };
    let expected = match flag {
        "--native-library" => "a library name",
        "--native-object" => "an object or shared-library path",
        "--native-library-path" => "a directory path",
        "--native-linker" => "a C compiler driver executable path or name",
        _ => return Ok(false),
    };
    let value = value
        .or_else(|| args.next())
        .filter(|value| !value.is_empty() && !value.starts_with('-'))
        .ok_or_else(|| missing_cli_option_value_error(flag, expected))?;
    let options = request
        .native_link
        .get_or_insert_with(NativeLinkOptions::default);
    match flag {
        "--native-library" => options.libraries.push(value),
        "--native-object" => options.objects.push(PathBuf::from(value)),
        "--native-library-path" => options.library_paths.push(PathBuf::from(value)),
        "--native-linker" => options.linker = Some(PathBuf::from(value)),
        _ => unreachable!("native option matched above"),
    }
    Ok(true)
}

/// Resolves CLI paths while preserving the order of supplied link inputs.
pub(super) fn canonicalize_options(
    mut options: NativeLinkOptions,
) -> Result<NativeLinkOptions, CliError> {
    options.objects = options
        .objects
        .into_iter()
        .map(|path| canonical_file_path("native object", path))
        .collect::<Result<_, _>>()?;
    options.library_paths = options
        .library_paths
        .into_iter()
        .map(|path| canonical_directory_path("native library path", path))
        .collect::<Result<_, _>>()?;
    if let Some(linker) = &options.linker {
        if linker.is_relative() && linker.components().count() > 1 {
            options.linker = Some(canonical_file_path("native linker", linker.clone())?);
        }
    }
    Ok(options)
}

fn canonical_file_path(label: &str, path: PathBuf) -> Result<PathBuf, CliError> {
    let invalid_path = |reason: String| {
        CliError::Diagnostic(
            Diagnostic::error("LNC0040", "input read failed")
                .with_note(format!("{label}: {}", path.display()))
                .with_note(reason)
                .with_help(format!("pass an existing regular file for {label}")),
        )
    };
    let canonical = fs::canonicalize(&path)
        .map_err(|err| invalid_path(format!("could not canonicalize {}: {err}", path.display())))?;
    if !canonical.is_file() {
        return Err(invalid_path(format!(
            "{} is not a regular file",
            canonical.display()
        )));
    }
    Ok(canonical)
}
