use std::{iter::Peekable, path::PathBuf};

use super::{command::Command, request::CompileRequestBuilder, source_pack};
use crate::cli::common::{
    CliError,
    LANIUS_DIAGNOSTIC_FORMATS,
    LANIUS_EMIT_TARGETS,
    LANIUS_LANGUAGE_EDITION,
    LANIUS_TARGET_TRIPLES,
    missing_cli_option_value_error,
    unknown_cli_option_error,
    validate_diagnostic_format,
};

/// Parses top-level CLI arguments into a command or validated compile request.
///
/// Leading diagnostic-format selectors are consumed before forwarded
/// subcommands so invocation errors across the CLI share the same format
/// selection behavior.
pub(crate) fn parse_args(args: impl IntoIterator<Item = String>) -> Result<Command, CliError> {
    let mut args = args.into_iter().peekable();
    consume_leading_diagnostic_format_args(&mut args)?;

    if let Some(command) = parse_forwarded_subcommand(&mut args) {
        return Ok(command);
    }

    let mut request = CompileRequestBuilder::default();
    if args.peek().map(String::as_str) == Some("check") {
        args.next();
        request.check_only = true;
    }

    while let Some(arg) = args.next() {
        if source_pack::parse_arg(&arg, &mut args, &mut request)? {
            continue;
        }

        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "-V" | "--version" => return Ok(Command::Version),
            "--emit" => {
                request.emit = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--emit",
                        format!("one of: {LANIUS_EMIT_TARGETS}"),
                    )
                })?;
            }
            "--edition" => {
                request.language_edition = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--edition",
                        format!("the current language edition: {LANIUS_LANGUAGE_EDITION}"),
                    )
                })?;
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
            "--target" => {
                request.target_triple = Some(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--target",
                        format!("one of: {LANIUS_TARGET_TRIPLES}"),
                    )
                })?);
            }
            "--stdlib" => {
                request
                    .stdlib_paths
                    .push(PathBuf::from(args.next().ok_or_else(|| {
                        missing_cli_option_value_error("--stdlib", "a source file path")
                    })?));
            }
            "--stdlib-root" => {
                request.stdlib_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--stdlib-root", "a directory path")
                })?));
            }
            "--source-root" => {
                request
                    .source_roots
                    .push(PathBuf::from(args.next().ok_or_else(|| {
                        missing_cli_option_value_error("--source-root", "a directory path")
                    })?));
            }
            "--package-manifest" => {
                request.package_manifest = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--package-manifest", "a path")
                })?));
            }
            "--package-lockfile" => {
                request.package_lockfile = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--package-lockfile", "a path")
                })?));
            }
            "-o" | "--out" => {
                request.output =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        missing_cli_option_value_error(&arg, "an output path")
                    })?));
            }
            flag if flag.starts_with("--emit=") => {
                request.emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with("--edition=") => {
                request.language_edition = flag.trim_start_matches("--edition=").to_string();
            }
            flag if flag.starts_with("--diagnostic-format=") => {
                validate_diagnostic_format(flag.trim_start_matches("--diagnostic-format="))?;
            }
            flag if flag.starts_with("--target=") => {
                request.target_triple = Some(flag.trim_start_matches("--target=").to_string());
            }
            flag if flag.starts_with("--stdlib=") => {
                request
                    .stdlib_paths
                    .push(PathBuf::from(flag.trim_start_matches("--stdlib=")));
            }
            flag if flag.starts_with("--stdlib-root=") => {
                request.stdlib_root =
                    Some(PathBuf::from(flag.trim_start_matches("--stdlib-root=")));
            }
            flag if flag.starts_with("--source-root=") => {
                request
                    .source_roots
                    .push(PathBuf::from(flag.trim_start_matches("--source-root=")));
            }
            flag if flag.starts_with("--package-manifest=") => {
                request.package_manifest = Some(PathBuf::from(
                    flag.trim_start_matches("--package-manifest="),
                ));
            }
            flag if flag.starts_with("--package-lockfile=") => {
                request.package_lockfile = Some(PathBuf::from(
                    flag.trim_start_matches("--package-lockfile="),
                ));
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc",
                    flag,
                    "--version, --edition, --emit, --target, --diagnostic-format, --package-manifest, --package-lockfile, --stdlib, --stdlib-root, --source-root, --source-pack-descriptors, --source-pack-manifest, --source-pack-library-manifest, --source-pack-artifact-root, --source-pack-metadata-only, --source-pack-prepare-only, --source-pack-build-from-metadata, --source-pack-build-prepare-only, --emit-contract, -o/--out",
                ));
            }
            path => {
                request.inputs.push(PathBuf::from(path));
            }
        }
    }

    Ok(Command::Compile(request.finish()?))
}

fn parse_forwarded_subcommand<I>(args: &mut Peekable<I>) -> Option<Command>
where
    I: Iterator<Item = String>,
{
    match args.peek().map(String::as_str)? {
        "fmt" => {
            args.next();
            Some(Command::Fmt(args.collect()))
        }
        "doctor" => {
            args.next();
            Some(Command::Doctor(args.collect()))
        }
        "package" => {
            args.next();
            Some(Command::Package(args.collect()))
        }
        "lsp" => {
            args.next();
            Some(Command::Lsp(args.collect()))
        }
        "diagnostics" => {
            args.next();
            Some(Command::Diagnostics(args.collect()))
        }
        _ => return None,
    }
}

fn consume_leading_diagnostic_format_args<I>(args: &mut Peekable<I>) -> Result<(), CliError>
where
    I: Iterator<Item = String>,
{
    loop {
        match args.peek().map(String::as_str) {
            Some("--diagnostic-format") => {
                args.next();
                let value = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--diagnostic-format",
                        format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                    )
                })?;
                validate_diagnostic_format(&value)?;
            }
            Some(flag) if flag.starts_with("--diagnostic-format=") => {
                let value = flag.trim_start_matches("--diagnostic-format=").to_string();
                args.next();
                validate_diagnostic_format(&value)?;
            }
            _ => return Ok(()),
        }
    }
}
