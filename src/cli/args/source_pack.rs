use std::path::PathBuf;

use super::{
    request::CompileRequestBuilder,
    validation::{parse_usize_cli_arg, parse_usize_cli_value},
};
use crate::cli::common::{CliError, missing_cli_option_value_error};

pub(super) fn parse_arg<I>(
    arg: &str,
    args: &mut I,
    request: &mut CompileRequestBuilder,
) -> Result<bool, CliError>
where
    I: Iterator<Item = String>,
{
    match arg {
        "--source-pack-descriptors" => {
            request.source_pack.descriptors = true;
            Ok(true)
        }
        "--source-pack-legacy-in-memory" => {
            request.source_pack.legacy_in_memory = true;
            Ok(true)
        }
        "--emit-contract" => {
            request.source_pack.emit_contract = true;
            Ok(true)
        }
        "--source-pack-manifest" => {
            request.source_pack.manifest = Some(next_path_arg(arg, args)?);
            Ok(true)
        }
        "--source-pack-library-manifest" => {
            request.source_pack.library_manifest = Some(next_path_arg(arg, args)?);
            Ok(true)
        }
        "--source-pack-metadata-only" => {
            request.source_pack.metadata_only = true;
            Ok(true)
        }
        "--source-pack-prepare-only" => {
            request.source_pack.prepare_only = true;
            Ok(true)
        }
        "--source-pack-build-from-metadata" => {
            request.source_pack.build_from_metadata = true;
            Ok(true)
        }
        "--source-pack-build-prepare-only" => {
            request.source_pack.build_prepare_only = true;
            Ok(true)
        }
        "--source-pack-metadata-max-libraries" => {
            request.source_pack.metadata_max_libraries =
                Some(parse_usize_cli_arg(arg, args.next())?);
            Ok(true)
        }
        "--source-pack-metadata-max-source-files" => {
            request.source_pack.metadata_max_source_files =
                Some(parse_usize_cli_arg(arg, args.next())?);
            Ok(true)
        }
        "--source-pack-build-max-items" => {
            request.source_pack.build_max_items = parse_usize_cli_arg(arg, args.next())?;
            Ok(true)
        }
        "--source-pack-artifact-root" => {
            request.source_pack.artifact_root = Some(next_path_arg(arg, args)?);
            Ok(true)
        }
        "--source-pack-max-items" => {
            request.source_pack.max_items = parse_usize_cli_arg(arg, args.next())?;
            Ok(true)
        }
        "--source-pack-max-ready-items" => {
            request.source_pack.max_ready_items = parse_usize_cli_arg(arg, args.next())?;
            Ok(true)
        }
        _ => parse_equals_arg(arg, request),
    }
}

fn parse_equals_arg(arg: &str, request: &mut CompileRequestBuilder) -> Result<bool, CliError> {
    if let Some(value) = arg.strip_prefix("--source-pack-manifest=") {
        request.source_pack.manifest = Some(PathBuf::from(value));
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-library-manifest=") {
        request.source_pack.library_manifest = Some(PathBuf::from(value));
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-metadata-max-libraries=") {
        request.source_pack.metadata_max_libraries = Some(parse_usize_cli_value(
            "--source-pack-metadata-max-libraries",
            value,
        )?);
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-metadata-max-source-files=") {
        request.source_pack.metadata_max_source_files = Some(parse_usize_cli_value(
            "--source-pack-metadata-max-source-files",
            value,
        )?);
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-build-max-items=") {
        request.source_pack.build_max_items =
            parse_usize_cli_value("--source-pack-build-max-items", value)?;
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-artifact-root=") {
        request.source_pack.artifact_root = Some(PathBuf::from(value));
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-max-items=") {
        request.source_pack.max_items = parse_usize_cli_value("--source-pack-max-items", value)?;
        return Ok(true);
    }
    if let Some(value) = arg.strip_prefix("--source-pack-max-ready-items=") {
        request.source_pack.max_ready_items =
            parse_usize_cli_value("--source-pack-max-ready-items", value)?;
        return Ok(true);
    }
    Ok(false)
}

fn next_path_arg<I>(flag: &str, args: &mut I) -> Result<PathBuf, CliError>
where
    I: Iterator<Item = String>,
{
    Ok(PathBuf::from(args.next().ok_or_else(|| {
        missing_cli_option_value_error(flag, "a path")
    })?))
}
