use std::{
    collections::HashMap,
    env,
    fs,
    io::{self, BufRead, Read, Write},
    path::{Path, PathBuf},
    process::Command,
};

use laniusc::{
    compiler::{
        CompileError,
        Diagnostic,
        DiagnosticLabel,
        EntrySourceRoots,
        FilesystemArtifactStore,
        LSP_DIAGNOSTIC_SOURCE,
        LSP_POSITION_ENCODING,
        PackageLockfile,
        PackageManifest,
        SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        SourcePackWorkQueueProgressIndex,
        compile_entry_to_wasm_with_source_roots,
        compile_entry_to_wasm_with_stdlib,
        compile_entry_to_x86_64_with_source_roots,
        compile_entry_to_x86_64_with_stdlib,
        compile_source_to_wasm_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen_from_path,
        compile_source_to_x86_64_with_gpu_codegen,
        compile_source_to_x86_64_with_gpu_codegen_from_path,
        diagnostic_explanation_json_pretty,
        diagnostic_output_formats,
        diagnostic_output_formats_json_pretty,
        diagnostic_registry,
        diagnostic_registry_json_pretty,
        type_check_entry_with_source_roots,
        type_check_entry_with_stdlib,
        type_check_source_with_gpu,
        type_check_source_with_gpu_from_path,
    },
    formatter::format_source,
    gpu::device,
};

mod cli;

use cli::{
    CliEmission,
    SourcePackCliOptions,
    canonical_directory_path,
    canonical_unique_directory_paths,
    parse_usize_value,
    source_pack::{
        compile_from_metadata_with_descriptor_queue,
        compile_source_pack_legacy_in_memory,
        compile_source_pack_library_manifest_with_descriptor_queue,
        compile_source_pack_manifest_with_descriptor_queue,
        compile_source_pack_with_descriptor_queue,
        prepare_build_from_metadata_chunk_only,
        prepare_inputs_chunk_only,
        prepare_metadata_only,
    },
    source_pack_artifact_target,
    write_cli_emission,
};

const LANIUS_LANGUAGE_EDITION: &str = "unstable-alpha";
const LANIUS_EDITION_POLICY: &str =
    "no stable production language edition yet; accepts the current alpha slice only";
const LANIUS_EMIT_TARGETS: &str = "wasm, x86_64";
const LANIUS_TARGET_TRIPLES: &str = "wasm32-unknown-unknown, x86_64-unknown-linux-gnu";
const LANIUS_DIAGNOSTIC_FORMATS: &str = "text, json, lsp-json";
const LANIUS_X86_64_SUPPORT: &str = "bounded GPU HIR main-return, same-module resolver-backed scalar-const, and direct scalar helper-call source-pack slices; unsupported source shapes are rejected through GPU status";
const LANIUS_DOCTOR_SCHEMA_VERSION: u32 = 3;
const LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION: u32 = 1;
const LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION: u32 = 1;
const LSP_STDIO_METHODS: &[&str] = &[
    "initialize",
    "initialized",
    "textDocument/didOpen",
    "textDocument/didChange",
    "textDocument/didClose",
    "textDocument/formatting",
    "textDocument/diagnostic",
    "shutdown",
    "exit",
];
const LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION: u32 = 4;
const LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION: u32 = 2;
const LANIUS_FORMATTER_CONTRACT: &str = "unstable-alpha lexical full-document formatter";

fn main() {
    let diagnostic_format = diagnostic_format_from_args(env::args().skip(1));
    if let Err(err) = run() {
        match (diagnostic_format, err) {
            (DiagnosticFormat::Json, CliError::Diagnostic(diagnostic)) => {
                match diagnostic.render_json_pretty() {
                    Ok(json) => eprintln!("{json}"),
                    Err(err) => eprintln!("laniusc: failed to serialize diagnostic JSON: {err}"),
                }
            }
            (DiagnosticFormat::LspJson, CliError::Diagnostic(diagnostic)) => {
                match diagnostic.render_lsp_json_pretty() {
                    Ok(json) => eprintln!("{json}"),
                    Err(err) => {
                        eprintln!("laniusc: failed to serialize LSP diagnostic JSON: {err}")
                    }
                }
            }
            (_, err) => eprintln!("laniusc: {err}"),
        }
        std::process::exit(1);
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DiagnosticFormat {
    Text,
    Json,
    LspJson,
}

#[derive(Debug)]
enum CliError {
    Diagnostic(Diagnostic),
    Message(String),
}

impl CliError {
    fn from_compile_error(err: CompileError) -> Self {
        match err {
            CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic),
            err => CliError::Message(err.to_string()),
        }
    }
}

impl From<String> for CliError {
    fn from(value: String) -> Self {
        CliError::Message(value)
    }
}

impl From<&str> for CliError {
    fn from(value: &str) -> Self {
        CliError::Message(value.to_string())
    }
}

impl std::fmt::Display for CliError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CliError::Diagnostic(diagnostic) => write!(f, "{diagnostic}"),
            CliError::Message(message) => f.write_str(message),
        }
    }
}

fn diagnostic_format_from_args(args: impl IntoIterator<Item = String>) -> DiagnosticFormat {
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--diagnostic-format" {
            return match args.next().as_deref() {
                Some(value) => {
                    diagnostic_format_from_value(value).unwrap_or(DiagnosticFormat::Text)
                }
                _ => DiagnosticFormat::Text,
            };
        }
        if let Some(value) = arg.strip_prefix("--diagnostic-format=") {
            return diagnostic_format_from_value(value).unwrap_or(DiagnosticFormat::Text);
        }
    }
    DiagnosticFormat::Text
}

fn diagnostic_format_from_value(value: &str) -> Option<DiagnosticFormat> {
    match value {
        "text" => Some(DiagnosticFormat::Text),
        "json" => Some(DiagnosticFormat::Json),
        "lsp-json" => Some(DiagnosticFormat::LspJson),
        _ => None,
    }
}

fn validate_diagnostic_format(value: &str) -> Result<(), CliError> {
    if diagnostic_format_from_value(value).is_some() {
        Ok(())
    } else {
        Err(unsupported_cli_option_value_error(
            "--diagnostic-format",
            value,
            LANIUS_DIAGNOSTIC_FORMATS,
            None,
        ))
    }
}

fn unsupported_cli_option_value_error(
    option: &str,
    value: &str,
    accepted: &str,
    detail: Option<String>,
) -> CliError {
    let mut diagnostic = Diagnostic::error("LNC0018", "unsupported CLI option value")
        .with_note(format!("{option} value {value:?} is not supported"))
        .with_note(format!("accepted {option} values: {accepted}"));
    if let Some(detail) = detail {
        diagnostic = diagnostic.with_note(detail);
    }
    CliError::Diagnostic(diagnostic)
}

fn missing_cli_option_value_error(option: &str, expected: impl Into<String>) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0023", "missing CLI option value")
            .with_note(format!("{option} requires {}", expected.into())),
    )
}

fn parse_usize_cli_arg(flag: &str, value: Option<String>) -> Result<usize, CliError> {
    let value =
        value.ok_or_else(|| missing_cli_option_value_error(flag, "a non-negative integer"))?;
    parse_usize_cli_value(flag, &value)
}

fn parse_usize_cli_value(flag: &str, value: &str) -> Result<usize, CliError> {
    parse_usize_value(flag, value).map_err(|err| {
        unsupported_cli_option_value_error(flag, value, "a non-negative integer", Some(err))
    })
}

fn unknown_cli_option_error(command: &str, flag: &str, accepted: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0020", "unknown CLI option")
            .with_note(format!("{command} option {flag:?} is not recognized"))
            .with_note(format!("accepted {command} options: {accepted}")),
    )
}

fn unknown_cli_subcommand_error(command: &str, subcommand: &str, accepted: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0020", "unknown CLI option")
            .with_note(format!(
                "{command} subcommand {subcommand:?} is not recognized"
            ))
            .with_note(format!("accepted {command} subcommands: {accepted}")),
    )
}

fn missing_cli_subcommand_error(command: &str, accepted: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0025", "missing CLI subcommand")
            .with_note(format!("{command} requires a subcommand"))
            .with_note(format!("accepted {command} subcommands: {accepted}")),
    )
}

fn missing_cli_argument_error(command: &str, expected: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0026", "missing CLI argument")
            .with_note(format!("{command} requires {expected}")),
    )
}

fn extra_cli_argument_error(command: &str, argument: &str, accepted: &str) -> CliError {
    if argument.starts_with('-') {
        unknown_cli_option_error(command, argument, accepted)
    } else {
        CliError::Diagnostic(
            Diagnostic::error("LNC0031", "unexpected CLI argument")
                .with_note(format!(
                    "{command} does not accept extra argument {argument:?}"
                ))
                .with_note(format!("accepted {command} arguments/options: {accepted}")),
        )
    }
}

fn incompatible_cli_options_error(
    command: &str,
    option: &str,
    incompatible_with: &str,
    remediation: &str,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0032", "incompatible CLI options")
            .with_note(format!(
                "{command} cannot combine {option} with {incompatible_with}"
            ))
            .with_note(remediation.to_string()),
    )
}

fn run() -> Result<(), CliError> {
    let mut inputs: Vec<PathBuf> = Vec::new();
    let mut stdlib_paths: Vec<PathBuf> = Vec::new();
    let mut stdlib_root: Option<PathBuf> = None;
    let mut source_roots: Vec<PathBuf> = Vec::new();
    let mut package_manifest: Option<PathBuf> = None;
    let mut package_lockfile: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;
    let mut emit = "wasm".to_string();
    let mut target_triple: Option<String> = None;
    let mut language_edition = LANIUS_LANGUAGE_EDITION.to_string();
    let mut check_only = false;
    let mut source_pack = SourcePackCliOptions::default();

    let mut args = env::args().skip(1).peekable();
    if args.peek().map(String::as_str) == Some("fmt") {
        args.next();
        return run_fmt(args);
    }
    if args.peek().map(String::as_str) == Some("doctor") {
        args.next();
        return run_doctor(args);
    }
    if args.peek().map(String::as_str) == Some("package") {
        args.next();
        return run_package(args);
    }
    if args.peek().map(String::as_str) == Some("lsp") {
        args.next();
        return run_lsp(args);
    }
    if args.peek().map(String::as_str) == Some("diagnostics") {
        args.next();
        return run_diagnostics(args);
    }
    if args.peek().map(String::as_str) == Some("check") {
        args.next();
        check_only = true;
    }

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            "-V" | "--version" => {
                print_version();
                return Ok(());
            }
            "--emit" => {
                emit = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--emit",
                        format!("one of: {LANIUS_EMIT_TARGETS}"),
                    )
                })?;
            }
            "--edition" => {
                language_edition = args.next().ok_or_else(|| {
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
                target_triple = Some(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--target",
                        format!("one of: {LANIUS_TARGET_TRIPLES}"),
                    )
                })?);
            }
            "--stdlib" => {
                stdlib_paths.push(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--stdlib", "a source file path")
                })?));
            }
            "--stdlib-root" => {
                stdlib_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--stdlib-root", "a directory path")
                })?));
            }
            "--source-root" => {
                source_roots.push(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--source-root", "a directory path")
                })?));
            }
            "--package-manifest" => {
                package_manifest = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--package-manifest", "a path")
                })?));
            }
            "--package-lockfile" => {
                package_lockfile = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--package-lockfile", "a path")
                })?));
            }
            "--source-pack-descriptors" => {
                source_pack.descriptors = true;
            }
            "--source-pack-legacy-in-memory" => {
                source_pack.legacy_in_memory = true;
            }
            "--emit-contract" => {
                source_pack.emit_contract = true;
            }
            "--source-pack-manifest" => {
                source_pack.manifest = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--source-pack-manifest", "a path")
                })?));
            }
            "--source-pack-library-manifest" => {
                source_pack.library_manifest =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        missing_cli_option_value_error("--source-pack-library-manifest", "a path")
                    })?));
            }
            "--source-pack-metadata-only" => {
                source_pack.metadata_only = true;
            }
            "--source-pack-prepare-only" => {
                source_pack.prepare_only = true;
            }
            "--source-pack-build-from-metadata" => {
                source_pack.build_from_metadata = true;
            }
            "--source-pack-build-prepare-only" => {
                source_pack.build_prepare_only = true;
            }
            "--source-pack-metadata-max-libraries" => {
                source_pack.metadata_max_libraries = Some(parse_usize_cli_arg(
                    "--source-pack-metadata-max-libraries",
                    args.next(),
                )?);
            }
            "--source-pack-metadata-max-source-files" => {
                source_pack.metadata_max_source_files = Some(parse_usize_cli_arg(
                    "--source-pack-metadata-max-source-files",
                    args.next(),
                )?);
            }
            "--source-pack-build-max-items" => {
                source_pack.build_max_items =
                    parse_usize_cli_arg("--source-pack-build-max-items", args.next())?;
            }
            "--source-pack-artifact-root" => {
                source_pack.artifact_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--source-pack-artifact-root", "a path")
                })?));
            }
            "--source-pack-max-items" => {
                source_pack.max_items =
                    parse_usize_cli_arg("--source-pack-max-items", args.next())?;
            }
            "--source-pack-max-ready-items" => {
                source_pack.max_ready_items =
                    parse_usize_cli_arg("--source-pack-max-ready-items", args.next())?;
            }
            "-o" | "--out" => {
                output = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(&arg, "an output path")
                })?));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with("--edition=") => {
                language_edition = flag.trim_start_matches("--edition=").to_string();
            }
            flag if flag.starts_with("--diagnostic-format=") => {
                validate_diagnostic_format(flag.trim_start_matches("--diagnostic-format="))?;
            }
            flag if flag.starts_with("--target=") => {
                target_triple = Some(flag.trim_start_matches("--target=").to_string());
            }
            flag if flag.starts_with("--stdlib=") => {
                stdlib_paths.push(PathBuf::from(flag.trim_start_matches("--stdlib=")));
            }
            flag if flag.starts_with("--stdlib-root=") => {
                stdlib_root = Some(PathBuf::from(flag.trim_start_matches("--stdlib-root=")));
            }
            flag if flag.starts_with("--source-root=") => {
                source_roots.push(PathBuf::from(flag.trim_start_matches("--source-root=")));
            }
            flag if flag.starts_with("--package-manifest=") => {
                package_manifest = Some(PathBuf::from(
                    flag.trim_start_matches("--package-manifest="),
                ));
            }
            flag if flag.starts_with("--package-lockfile=") => {
                package_lockfile = Some(PathBuf::from(
                    flag.trim_start_matches("--package-lockfile="),
                ));
            }
            flag if flag.starts_with("--source-pack-manifest=") => {
                source_pack.manifest = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-manifest="),
                ));
            }
            flag if flag.starts_with("--source-pack-library-manifest=") => {
                source_pack.library_manifest = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-library-manifest="),
                ));
            }
            flag if flag.starts_with("--source-pack-metadata-max-libraries=") => {
                source_pack.metadata_max_libraries = Some(parse_usize_cli_value(
                    "--source-pack-metadata-max-libraries",
                    flag.trim_start_matches("--source-pack-metadata-max-libraries="),
                )?);
            }
            flag if flag.starts_with("--source-pack-metadata-max-source-files=") => {
                source_pack.metadata_max_source_files = Some(parse_usize_cli_value(
                    "--source-pack-metadata-max-source-files",
                    flag.trim_start_matches("--source-pack-metadata-max-source-files="),
                )?);
            }
            flag if flag.starts_with("--source-pack-build-max-items=") => {
                source_pack.build_max_items = parse_usize_cli_value(
                    "--source-pack-build-max-items",
                    flag.trim_start_matches("--source-pack-build-max-items="),
                )?;
            }
            flag if flag.starts_with("--source-pack-artifact-root=") => {
                source_pack.artifact_root = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-artifact-root="),
                ));
            }
            flag if flag.starts_with("--source-pack-max-items=") => {
                source_pack.max_items = parse_usize_cli_value(
                    "--source-pack-max-items",
                    flag.trim_start_matches("--source-pack-max-items="),
                )?;
            }
            flag if flag.starts_with("--source-pack-max-ready-items=") => {
                source_pack.max_ready_items = parse_usize_cli_value(
                    "--source-pack-max-ready-items",
                    flag.trim_start_matches("--source-pack-max-ready-items="),
                )?;
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc",
                    flag,
                    "--version, --edition, --emit, --target, --diagnostic-format, --package-manifest, --package-lockfile, --stdlib, --stdlib-root, --source-root, --source-pack-descriptors, --source-pack-manifest, --source-pack-library-manifest, --source-pack-artifact-root, --source-pack-metadata-only, --source-pack-prepare-only, --source-pack-build-from-metadata, --source-pack-build-prepare-only, --source-pack-legacy-in-memory, --emit-contract, -o/--out",
                ));
            }
            path => {
                inputs.push(PathBuf::from(path));
            }
        }
    }

    if emit != "wasm" && emit != "x86_64" {
        return Err(unsupported_cli_option_value_error(
            "--emit",
            &emit,
            LANIUS_EMIT_TARGETS,
            Some(format!("x86_64 currently supports {LANIUS_X86_64_SUPPORT}")),
        ));
    }
    if language_edition != LANIUS_LANGUAGE_EDITION {
        return Err(unsupported_cli_option_value_error(
            "--edition",
            &language_edition,
            LANIUS_LANGUAGE_EDITION,
            Some(LANIUS_EDITION_POLICY.to_string()),
        ));
    }
    if let Some(target_triple) = target_triple.as_deref() {
        let target_emit = emit_for_target_triple(target_triple).ok_or_else(|| {
            unsupported_cli_option_value_error(
                "--target",
                target_triple,
                LANIUS_TARGET_TRIPLES,
                None,
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
    if source_pack.descriptors && source_pack.legacy_in_memory {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-descriptors",
            "--source-pack-legacy-in-memory",
            "choose descriptor mode or the legacy in-memory source-pack path, not both",
        ));
    }
    if source_pack.emit_contract && source_pack.legacy_in_memory {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--emit-contract",
            "--source-pack-legacy-in-memory",
            "--emit-contract only applies to source-pack descriptor mode; omit --source-pack-legacy-in-memory",
        ));
    }
    if source_pack.manifest.is_some() && source_pack.legacy_in_memory {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-manifest",
            "--source-pack-legacy-in-memory",
            "--source-pack-manifest requires descriptor mode; omit --source-pack-legacy-in-memory",
        ));
    }
    if source_pack.library_manifest.is_some() && source_pack.legacy_in_memory {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-library-manifest",
            "--source-pack-legacy-in-memory",
            "--source-pack-library-manifest requires descriptor mode; omit --source-pack-legacy-in-memory",
        ));
    }
    if source_pack.manifest.is_some() && source_pack.library_manifest.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "--source-pack-manifest",
            "--source-pack-library-manifest",
            "choose either a whole source-pack manifest or one library manifest, not both",
        ));
    }
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
    if package_lockfile.is_some()
        && (source_pack.manifest.is_some()
            || source_pack.library_manifest.is_some()
            || source_pack.descriptors
            || source_pack.artifact_root.is_some()
            || source_pack.metadata_only
            || source_pack.prepare_only
            || source_pack.build_from_metadata
            || source_pack.build_prepare_only
            || source_pack.legacy_in_memory
            || source_pack.emit_contract)
    {
        return Err(
            "--package-lockfile currently uses the in-memory source-root compiler path; do not combine it with source-pack descriptor, metadata, prepare, artifact-root, legacy, or contract-output flags"
                .into(),
        );
    }
    if package_manifest.is_some()
        && (source_pack.manifest.is_some()
            || source_pack.library_manifest.is_some()
            || source_pack.descriptors
            || source_pack.artifact_root.is_some()
            || source_pack.metadata_only
            || source_pack.prepare_only
            || source_pack.build_from_metadata
            || source_pack.build_prepare_only
            || source_pack.legacy_in_memory
            || source_pack.emit_contract)
    {
        return Err(
            "--package-manifest currently uses the in-memory source-root compiler path; do not combine it with source-pack descriptor, metadata, prepare, artifact-root, legacy, or contract-output flags"
                .into(),
        );
    }
    if source_pack.metadata_only && source_pack.build_from_metadata {
        return Err(
            "--source-pack-metadata-only and --source-pack-build-from-metadata are mutually exclusive"
                .into(),
        );
    }
    if source_pack.prepare_only && source_pack.metadata_only {
        return Err(
            "--source-pack-prepare-only and --source-pack-metadata-only are mutually exclusive"
                .into(),
        );
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
        return Err("--source-pack-prepare-only prepares from source-pack inputs; use --source-pack-build-from-metadata --source-pack-build-prepare-only for persisted metadata".into());
    }
    if (source_pack.metadata_only || source_pack.prepare_only || source_pack.build_from_metadata)
        && source_pack.legacy_in_memory
    {
        return Err(
            "--source-pack-metadata-only, --source-pack-prepare-only, and --source-pack-build-from-metadata require descriptor mode; they cannot be combined with --source-pack-legacy-in-memory"
                .into(),
        );
    }
    if source_pack.build_from_metadata
        && (source_pack.manifest.is_some()
            || source_pack.library_manifest.is_some()
            || !stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty()
            || !inputs.is_empty())
    {
        return Err(
            "--source-pack-build-from-metadata reads persisted metadata from --source-pack-artifact-root; do not also pass source-pack inputs"
                .into(),
        );
    }
    if source_pack.metadata_only && output.is_some() {
        return Err("--source-pack-metadata-only does not emit target bytes; omit -o/--out".into());
    }
    if source_pack.prepare_only && output.is_some() {
        return Err("--source-pack-prepare-only does not emit target bytes; omit -o/--out".into());
    }
    if source_pack.build_prepare_only && output.is_some() {
        return Err(
            "--source-pack-build-prepare-only does not emit target bytes; omit -o/--out".into(),
        );
    }
    if source_pack.build_prepare_only && !source_pack.build_from_metadata {
        return Err(
            "--source-pack-build-prepare-only requires --source-pack-build-from-metadata".into(),
        );
    }
    if source_pack.metadata_max_libraries.is_some()
        && !source_pack.metadata_only
        && !source_pack.prepare_only
    {
        return Err(
            "--source-pack-metadata-max-libraries only applies with --source-pack-metadata-only or --source-pack-prepare-only"
                .into(),
        );
    }
    if source_pack.metadata_max_source_files.is_some()
        && !source_pack.metadata_only
        && !source_pack.prepare_only
    {
        return Err(
            "--source-pack-metadata-max-source-files only applies with --source-pack-metadata-only or --source-pack-prepare-only"
                .into(),
        );
    }
    if source_pack.metadata_max_libraries == Some(0) {
        return Err("--source-pack-metadata-max-libraries must be greater than zero".into());
    }
    if source_pack.metadata_max_source_files == Some(0) {
        return Err("--source-pack-metadata-max-source-files must be greater than zero".into());
    }
    if source_pack.build_max_items == 0 {
        return Err("--source-pack-build-max-items must be greater than zero".into());
    }
    if (source_pack.manifest.is_some() || source_pack.library_manifest.is_some())
        && (!stdlib_paths.is_empty()
            || stdlib_root.is_some()
            || !source_roots.is_empty()
            || !inputs.is_empty())
    {
        return Err(
            "--source-pack-manifest and --source-pack-library-manifest describe all source-pack libraries; do not also pass --stdlib, --stdlib-root, --source-root, or positional input files"
                .into(),
        );
    }
    let source_root_requested = !source_roots.is_empty() || stdlib_root.is_some();
    if source_root_requested && !stdlib_paths.is_empty() {
        return Err(
            "--source-root and --stdlib-root discover module-path imports; do not combine them with explicit --stdlib source files"
                .into(),
        );
    }
    if source_root_requested
        && (source_pack.metadata_only
            || source_pack.prepare_only
            || source_pack.build_prepare_only
            || source_pack.descriptors
            || source_pack.artifact_root.is_some())
    {
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

    let source_pack_requested = source_pack.manifest.is_some()
        || source_pack.library_manifest.is_some()
        || source_pack.descriptors
        || source_pack.artifact_root.is_some()
        || source_pack.metadata_only
        || source_pack.prepare_only
        || source_pack.build_from_metadata
        || !stdlib_paths.is_empty()
        || inputs.len() > 1;
    if source_pack_requested && inputs.is_empty() {
        if source_pack.manifest.is_none()
            && source_pack.library_manifest.is_none()
            && !source_pack.build_from_metadata
        {
            return Err("explicit source-pack compilation requires at least one input file".into());
        }
    }
    if check_only && output.is_some() {
        return Err(incompatible_cli_options_error(
            "laniusc check",
            "-o/--out",
            "diagnostics-only check mode",
            "omit -o/--out because check mode does not write target bytes",
        ));
    }
    if check_only
        && (source_pack.manifest.is_some()
            || source_pack.library_manifest.is_some()
            || source_pack.descriptors
            || source_pack.artifact_root.is_some()
            || source_pack.metadata_only
            || source_pack.prepare_only
            || source_pack.build_from_metadata
            || source_pack.build_prepare_only
            || source_pack.legacy_in_memory
            || source_pack.emit_contract
            || !stdlib_paths.is_empty()
            || inputs.len() > 1)
    {
        return Err(
            "check mode currently supports single-entry in-memory, source-root, stdlib-root, package-manifest, and package-lockfile compile paths; omit explicit source-pack descriptor, metadata, prepare, legacy, contract, artifact-root, --stdlib, or multi-input flags"
                .into(),
        );
    }
    if check_only && inputs.is_empty() && package_manifest.is_none() && package_lockfile.is_none() {
        return Err(missing_cli_argument_error(
            "laniusc check",
            "an input file, --package-manifest, or --package-lockfile",
        ));
    }
    let descriptor_contract_output_requested = source_pack_requested
        && !source_pack.legacy_in_memory
        && !source_pack.metadata_only
        && !source_pack.prepare_only
        && !source_pack.build_prepare_only;
    if descriptor_contract_output_requested && !source_pack.emit_contract {
        return Err(incompatible_cli_options_error(
            "laniusc",
            "source-pack descriptor mode",
            "implicit target-byte output",
            "pass --emit-contract to write linked-output contract descriptors, or pass --source-pack-legacy-in-memory when executable target bytes are required",
        ));
    }

    if source_pack.metadata_only {
        prepare_metadata_only(&emit, &stdlib_paths, &inputs, &source_pack)?;
        return Ok(());
    }
    if source_pack.prepare_only {
        prepare_inputs_chunk_only(&emit, &stdlib_paths, &inputs, &source_pack)?;
        return Ok(());
    }
    if source_pack.build_prepare_only {
        prepare_build_from_metadata_chunk_only(&emit, &source_pack)?;
        return Ok(());
    }

    let emitted = if source_pack.build_from_metadata {
        CliEmission::ContractDescriptorFile(compile_from_metadata_with_descriptor_queue(
            &emit,
            &source_pack,
        )?)
    } else if let Some(library_manifest_path) = source_pack.library_manifest.as_deref() {
        CliEmission::ContractDescriptorFile(
            compile_source_pack_library_manifest_with_descriptor_queue(
                &emit,
                library_manifest_path,
                &source_pack,
            )?,
        )
    } else if let Some(manifest_path) = source_pack.manifest.as_deref() {
        CliEmission::ContractDescriptorFile(compile_source_pack_manifest_with_descriptor_queue(
            &emit,
            manifest_path,
            &source_pack,
        )?)
    } else if source_pack_requested {
        if source_pack.legacy_in_memory {
            CliEmission::Bytes(compile_source_pack_legacy_in_memory(
                &emit,
                &stdlib_paths,
                &inputs,
            )?)
        } else {
            CliEmission::ContractDescriptorFile(compile_source_pack_with_descriptor_queue(
                &emit,
                &stdlib_paths,
                &inputs,
                &source_pack,
            )?)
        }
    } else if let Some(package_manifest_path) = package_manifest.as_deref() {
        let package = PackageManifest::load_json_file(package_manifest_path).map_err(|err| {
            package_metadata_cli_error("--package-manifest", package_manifest_path, err)
        })?;
        let roots = package.to_entry_source_roots();
        if check_only {
            pollster::block_on(type_check_entry_with_source_roots(&package.entry, &roots))
                .map_err(|err| {
                    package_compile_cli_error("--package-manifest", package_manifest_path, err)
                })?;
            CliEmission::Bytes(Vec::new())
        } else if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_wasm_with_source_roots(
                    &package.entry,
                    &roots,
                ))
                .map_err(|err| {
                    package_compile_cli_error("--package-manifest", package_manifest_path, err)
                })?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_x86_64_with_source_roots(
                    &package.entry,
                    &roots,
                ))
                .map_err(|err| {
                    package_compile_cli_error("--package-manifest", package_manifest_path, err)
                })?,
            )
        }
    } else if let Some(package_lockfile_path) = package_lockfile.as_deref() {
        let package = PackageLockfile::load_json_file(package_lockfile_path).map_err(|err| {
            package_metadata_cli_error("--package-lockfile", package_lockfile_path, err)
        })?;
        let roots = package.to_entry_source_roots();
        if check_only {
            pollster::block_on(type_check_entry_with_source_roots(&package.entry, &roots))
                .map_err(|err| {
                    package_compile_cli_error("--package-lockfile", package_lockfile_path, err)
                })?;
            CliEmission::Bytes(Vec::new())
        } else if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_wasm_with_source_roots(
                    &package.entry,
                    &roots,
                ))
                .map_err(|err| {
                    package_compile_cli_error("--package-lockfile", package_lockfile_path, err)
                })?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_x86_64_with_source_roots(
                    &package.entry,
                    &roots,
                ))
                .map_err(|err| {
                    package_compile_cli_error("--package-lockfile", package_lockfile_path, err)
                })?,
            )
        }
    } else if !source_roots.is_empty() {
        let input = inputs
            .first()
            .expect("--source-root validation requires one input");
        let roots = EntrySourceRoots {
            stdlib_root: stdlib_root.clone(),
            user_roots: source_roots.clone(),
        };
        if check_only {
            pollster::block_on(type_check_entry_with_source_roots(input, &roots))
                .map_err(CliError::from_compile_error)?;
            CliEmission::Bytes(Vec::new())
        } else if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_wasm_with_source_roots(input, &roots))
                    .map_err(CliError::from_compile_error)?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_x86_64_with_source_roots(input, &roots))
                    .map_err(CliError::from_compile_error)?,
            )
        }
    } else if let Some(stdlib_root) = stdlib_root.as_deref() {
        let input = inputs
            .first()
            .expect("--stdlib-root validation requires one input");
        if check_only {
            pollster::block_on(type_check_entry_with_stdlib(input, stdlib_root))
                .map_err(CliError::from_compile_error)?;
            CliEmission::Bytes(Vec::new())
        } else if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_wasm_with_stdlib(input, stdlib_root))
                    .map_err(CliError::from_compile_error)?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(input, stdlib_root))
                    .map_err(CliError::from_compile_error)?,
            )
        }
    } else if let Some(input) = inputs.first() {
        if check_only {
            pollster::block_on(type_check_source_with_gpu_from_path(input))
                .map_err(CliError::from_compile_error)?;
            CliEmission::Bytes(Vec::new())
        } else if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(input))
                    .map_err(CliError::from_compile_error)?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(input))
                    .map_err(CliError::from_compile_error)?,
            )
        }
    } else if emit == "wasm" {
        CliEmission::Bytes(
            pollster::block_on(compile_source_to_wasm_with_gpu_codegen("let x = 7;\n"))
                .map_err(CliError::from_compile_error)?,
        )
    } else {
        CliEmission::Bytes(
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
                "fn main() { return 7; }\n",
            ))
            .map_err(CliError::from_compile_error)?,
        )
    };
    device::persist_pipeline_cache();
    if check_only {
        return Ok(());
    }
    write_cli_emission(emitted, output, &emit)?;
    Ok(())
}

fn run_fmt(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut check = false;
    let mut stdin = false;
    let mut inputs: Vec<PathBuf> = Vec::new();

    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_fmt_help();
                return Ok(());
            }
            "--check" => {
                check = true;
            }
            "--stdin" => {
                stdin = true;
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
            "-" => {
                stdin = true;
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc fmt",
                    flag,
                    "--help, --check, --stdin, --diagnostic-format",
                ));
            }
            path => {
                inputs.push(PathBuf::from(path));
            }
        }
    }

    if stdin {
        if !inputs.is_empty() {
            return Err(incompatible_cli_options_error(
                "laniusc fmt",
                "--stdin/-",
                "input files",
                "omit input files when formatting standard input",
            ));
        }

        let mut source = String::new();
        io::stdin()
            .read_to_string(&mut source)
            .map_err(|err| format!("read stdin for formatting: {err}"))?;
        let formatted = format_source(&source);

        if check {
            if source == formatted {
                return Ok(());
            }
            return Err(CliError::Diagnostic(formatter_check_failed_diagnostic(
                Path::new("<stdin>"),
                &source,
                &formatted,
                "pipe the source through `laniusc fmt --stdin` to print the rewrite".to_string(),
            )));
        }

        io::stdout()
            .write_all(formatted.as_bytes())
            .map_err(|err| format!("write formatted stdout: {err}"))?;
        return Ok(());
    }

    if inputs.is_empty() {
        return Err(missing_cli_argument_error(
            "laniusc fmt",
            "one or more input files or --stdin",
        ));
    }

    for input in inputs {
        let source = fs::read_to_string(&input)
            .map_err(|err| format!("read {} for formatting: {err}", input.display()))?;
        let formatted = format_source(&source);

        if source == formatted {
            continue;
        }

        if check {
            return Err(CliError::Diagnostic(formatter_check_failed_diagnostic(
                &input,
                &source,
                &formatted,
                format!("run `laniusc fmt {}` to rewrite the file", input.display()),
            )));
        }

        fs::write(&input, formatted)
            .map_err(|err| format!("write formatted {}: {err}", input.display()))?;
    }
    Ok(())
}

fn formatter_check_failed_diagnostic(
    input: &Path,
    source: &str,
    formatted: &str,
    rewrite_hint: String,
) -> Diagnostic {
    Diagnostic::error("LNC0019", "formatter check failed")
        .with_primary_label(formatter_check_label(input, source, formatted))
        .with_note(format!(
            "fmt check failed: {} is not formatted",
            input.display()
        ))
        .with_note(rewrite_hint)
}

fn formatter_check_label(input: &Path, source: &str, formatted: &str) -> DiagnosticLabel {
    let diff_byte = first_format_difference_byte(source, formatted);
    let label_start = if diff_byte < source.len() {
        diff_byte
    } else {
        source
            .char_indices()
            .last()
            .map(|(index, _)| index)
            .unwrap_or(0)
    };
    let line_start = source[..label_start]
        .rfind('\n')
        .map(|index| index + 1)
        .unwrap_or(0);
    let line_end = source[label_start..]
        .find('\n')
        .map(|index| label_start + index)
        .unwrap_or(source.len());
    let line = source[..line_start]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let column = source[line_start..label_start].chars().count() + 1;
    let source_line = if line_start < line_end {
        source.get(line_start..line_end).map(ToOwned::to_owned)
    } else {
        None
    };

    DiagnosticLabel::primary(
        input,
        line,
        column,
        1,
        source_line,
        "formatting differs here",
    )
}

fn first_format_difference_byte(source: &str, formatted: &str) -> usize {
    let mut source_chars = source.char_indices();
    let mut formatted_chars = formatted.chars();
    loop {
        match (source_chars.next(), formatted_chars.next()) {
            (Some((_, source_char)), Some(formatted_char)) if source_char == formatted_char => {}
            (Some((index, _)), _) => return index,
            (None, Some(_)) => return source.len(),
            (None, None) => return 0,
        }
    }
}

fn run_package(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
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
                manifest = Some(PathBuf::from(flag.trim_start_matches("--manifest=")));
            }
            flag if flag.starts_with("--out=") => {
                output = Some(PathBuf::from(flag.trim_start_matches("--out=")));
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
                return Err(format!(
                    "package lock does not accept positional input file {path:?}; pass --manifest and -o/--out"
                )
                .into());
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

fn run_lsp(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args = cli_args_without_diagnostic_format(
        "laniusc lsp",
        args,
        "--help, capabilities, serve, --stdio, --diagnostic-format",
    )?;
    let mut args = args.into_iter();
    let Some(command) = args.next() else {
        print_lsp_help();
        return Ok(());
    };

    match command.as_str() {
        "-h" | "--help" => {
            print_lsp_help();
            Ok(())
        }
        "capabilities" => {
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc lsp capabilities",
                    &extra,
                    "no options",
                ));
            }
            let document = lsp_capabilities_document();
            let json = serde_json::to_string_pretty(&document)
                .map_err(|err| format!("serialize lsp capabilities: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "serve" => run_lsp_serve(args),
        other => Err(unknown_cli_subcommand_error(
            "laniusc lsp",
            other,
            "capabilities, serve",
        )),
    }
}

fn lsp_capabilities_document() -> serde_json::Value {
    serde_json::json!({
        "schema_version": LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
        "status": "stdio-handshake-ready",
        "server": {
            "name": "laniusc",
            "version": env!("CARGO_PKG_VERSION"),
            "stdio": true,
            "stdio_methods": LSP_STDIO_METHODS
        },
        "language_id": "lanius",
        "position_encoding": LSP_POSITION_ENCODING,
        "diagnostic_source": LSP_DIAGNOSTIC_SOURCE,
        "diagnostic_registry": diagnostic_registry(),
        "document_sync": {
            "open_close": true,
            "change": 1,
            "change_kind": "full",
            "incremental_changes": false
        },
        "formatting": lsp_formatter_metadata(),
        "document_diagnostics": {
            "method": "textDocument/diagnostic",
            "report_kind": "full",
            "source_compilation": true,
            "gpu_device_creation": true,
            "target_codegen": false
        },
        "no_run_guards": {
            "source_compilation": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    })
}

fn lsp_formatter_metadata() -> serde_json::Value {
    serde_json::json!({
        "document_formatting_provider": true,
        "method": "textDocument/formatting",
        "edit_strategy": "single full-document replacement when formatting changes",
        "range_formatting_provider": false,
        "cli_command": "laniusc fmt --stdin",
        "cli_check_command": "laniusc fmt --stdin --check",
        "formatter_contract": LANIUS_FORMATTER_CONTRACT,
        "source_compilation": false,
        "gpu_device_creation": false,
        "target_codegen": false
    })
}

fn run_lsp_serve(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut saw_stdio = false;
    for arg in args {
        match arg.as_str() {
            "--stdio" => saw_stdio = true,
            "-h" | "--help" => {
                print_lsp_help();
                return Ok(());
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc lsp serve",
                    other,
                    "--stdio",
                ));
            }
        }
    }
    if !saw_stdio {
        return Err(missing_cli_option_value_error(
            "laniusc lsp serve",
            "--stdio",
        ));
    }

    run_lsp_stdio(io::stdin().lock(), io::stdout().lock())
}

fn run_lsp_stdio(mut input: impl BufRead, mut output: impl Write) -> Result<(), CliError> {
    let mut shutdown_received = false;
    let mut documents = HashMap::<String, LspOpenDocument>::new();
    loop {
        let body = match read_lsp_framed_body(&mut input)? {
            LspFrameRead::Body(body) => body,
            LspFrameRead::InvalidFrame(note) => {
                let response = invalid_lsp_message_error_response(
                    serde_json::Value::Null,
                    -32700,
                    "invalid LSP frame",
                    note,
                );
                write_lsp_response(&mut output, &response)?;
                continue;
            }
            LspFrameRead::EndOfInput => break,
        };
        let request: serde_json::Value = match serde_json::from_slice(&body) {
            Ok(request) => request,
            Err(err) => {
                let response = invalid_lsp_message_error_response(
                    serde_json::Value::Null,
                    -32700,
                    format!("invalid JSON-RPC payload: {err}"),
                    "message body was not valid JSON",
                );
                write_lsp_response(&mut output, &response)?;
                continue;
            }
        };
        let id = request
            .get("id")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        let Some(method) = request.get("method").and_then(serde_json::Value::as_str) else {
            if !id.is_null() {
                let response = invalid_lsp_message_error_response(
                    id,
                    -32600,
                    "JSON-RPC request must include method",
                    "request object did not include a string method field",
                );
                write_lsp_response(&mut output, &response)?;
            }
            continue;
        };
        match method {
            "initialize" => {
                let response = serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "serverInfo": {
                            "name": "laniusc",
                            "version": env!("CARGO_PKG_VERSION")
                        },
                        "capabilities": {
                            "positionEncoding": LSP_POSITION_ENCODING,
                            "textDocumentSync": {
                                "openClose": true,
                                "change": 1
                            },
                            "diagnosticProvider": {
                                "interFileDependencies": false,
                                "workspaceDiagnostics": false
                            },
                            "documentFormattingProvider": true,
                            "experimental": {
                                "laniusc": {
                                    "schema_version": LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
                                    "language_id": "lanius",
                                    "diagnostic_source": LSP_DIAGNOSTIC_SOURCE,
                                    "diagnostic_registry": diagnostic_registry(),
                                    "formatting": lsp_formatter_metadata(),
                                    "supported_methods": LSP_STDIO_METHODS,
                                    "document_diagnostics": true,
                                    "no_run_guards": {
                                        "source_compilation": false,
                                        "gpu_device_creation": false,
                                        "target_codegen": false
                                    }
                                }
                            }
                        }
                    }
                });
                write_lsp_response(&mut output, &response)?;
            }
            "initialized" => {
                if !id.is_null() {
                    let response = lsp_null_result_response(id);
                    write_lsp_response(&mut output, &response)?;
                }
            }
            "textDocument/didOpen" => match lsp_open_document_from_request(&request) {
                Ok((uri, document)) => {
                    documents.insert(uri, document);
                    if !id.is_null() {
                        let response = lsp_null_result_response(id);
                        write_lsp_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = invalid_lsp_message_error_response(
                            id,
                            -32602,
                            "invalid textDocument/didOpen parameters",
                            note,
                        );
                        write_lsp_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/didChange" => match lsp_document_change_from_request(&request) {
                Ok((uri, text)) => {
                    documents.insert(uri, LspOpenDocument { text });
                    if !id.is_null() {
                        let response = lsp_null_result_response(id);
                        write_lsp_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = invalid_lsp_message_error_response(
                            id,
                            -32602,
                            "invalid textDocument/didChange parameters",
                            note,
                        );
                        write_lsp_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/didClose" => match lsp_document_uri_from_request(&request) {
                Ok(uri) => {
                    documents.remove(&uri);
                    if !id.is_null() {
                        let response = lsp_null_result_response(id);
                        write_lsp_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = invalid_lsp_message_error_response(
                            id,
                            -32602,
                            "invalid textDocument/didClose parameters",
                            note,
                        );
                        write_lsp_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/formatting" => {
                if !id.is_null() {
                    match lsp_document_uri_from_request(&request) {
                        Ok(uri) => {
                            let Some(document) = documents.get(&uri) else {
                                let response = invalid_lsp_message_error_response(
                                    id,
                                    -32602,
                                    "invalid textDocument/formatting parameters",
                                    "textDocument/formatting requested a document that is not open",
                                );
                                write_lsp_response(&mut output, &response)?;
                                continue;
                            };
                            let response = serde_json::json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "result": lsp_document_formatting_edits(&document.text)
                            });
                            write_lsp_response(&mut output, &response)?;
                        }
                        Err(note) => {
                            let response = invalid_lsp_message_error_response(
                                id,
                                -32602,
                                "invalid textDocument/formatting parameters",
                                note,
                            );
                            write_lsp_response(&mut output, &response)?;
                        }
                    }
                }
            }
            "textDocument/diagnostic" => {
                if !id.is_null() {
                    match lsp_document_uri_from_request(&request) {
                        Ok(uri) => {
                            let Some(document) = documents.get(&uri) else {
                                let response = invalid_lsp_message_error_response(
                                    id,
                                    -32602,
                                    "invalid textDocument/diagnostic parameters",
                                    "textDocument/diagnostic requested a document that is not open",
                                );
                                write_lsp_response(&mut output, &response)?;
                                continue;
                            };
                            match lsp_document_diagnostic_items(&uri, &document.text) {
                                Ok(items) => {
                                    let response = serde_json::json!({
                                        "jsonrpc": "2.0",
                                        "id": id,
                                        "result": {
                                            "kind": "full",
                                            "items": items
                                        }
                                    });
                                    write_lsp_response(&mut output, &response)?;
                                }
                                Err(message) => {
                                    let response = lsp_error_response_with_data(
                                        id,
                                        -32603,
                                        "document diagnostics failed",
                                        serde_json::json!({
                                            "message": message,
                                            "no_run_guards": {
                                                "source_compilation": true,
                                                "gpu_device_creation": true,
                                                "target_codegen": false
                                            }
                                        }),
                                    );
                                    write_lsp_response(&mut output, &response)?;
                                }
                            }
                        }
                        Err(note) => {
                            let response = invalid_lsp_message_error_response(
                                id,
                                -32602,
                                "invalid textDocument/diagnostic parameters",
                                note,
                            );
                            write_lsp_response(&mut output, &response)?;
                        }
                    }
                }
            }
            "shutdown" => {
                shutdown_received = true;
                let response = serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": serde_json::Value::Null
                });
                write_lsp_response(&mut output, &response)?;
            }
            "exit" => break,
            other => {
                if !id.is_null() {
                    let response = unsupported_lsp_method_error_response(id, other);
                    write_lsp_response(&mut output, &response)?;
                }
            }
        }
        if shutdown_received && method == "exit" {
            break;
        }
    }
    Ok(())
}

#[derive(Debug)]
enum LspFrameRead {
    Body(Vec<u8>),
    InvalidFrame(String),
    EndOfInput,
}

#[derive(Clone, Debug)]
struct LspOpenDocument {
    text: String,
}

fn lsp_open_document_from_request(
    request: &serde_json::Value,
) -> Result<(String, LspOpenDocument), String> {
    let text_document = request
        .get("params")
        .and_then(|params| params.get("textDocument"))
        .ok_or_else(|| "didOpen request did not include params.textDocument".to_string())?;
    let uri = text_document
        .get("uri")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "didOpen request did not include textDocument.uri".to_string())?;
    let text = text_document
        .get("text")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "didOpen request did not include textDocument.text".to_string())?;
    Ok((
        uri.to_string(),
        LspOpenDocument {
            text: text.to_string(),
        },
    ))
}

fn lsp_document_change_from_request(
    request: &serde_json::Value,
) -> Result<(String, String), String> {
    let uri = lsp_document_uri_from_request(request)?;
    let changes = request
        .get("params")
        .and_then(|params| params.get("contentChanges"))
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "didChange request did not include params.contentChanges".to_string())?;
    if changes
        .iter()
        .any(|change| change.get("range").is_some() || change.get("rangeLength").is_some())
    {
        return Err(
            "didChange only accepts full-document text changes; ranged incremental changes are not supported"
                .to_string(),
        );
    }
    let text = changes
        .iter()
        .filter_map(|change| change.get("text").and_then(serde_json::Value::as_str))
        .next_back()
        .ok_or_else(|| "didChange request did not include full-document text".to_string())?;
    Ok((uri, text.to_string()))
}

fn lsp_document_uri_from_request(request: &serde_json::Value) -> Result<String, String> {
    request
        .get("params")
        .and_then(|params| params.get("textDocument"))
        .and_then(|text_document| text_document.get("uri"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| "request did not include params.textDocument.uri".to_string())
}

fn lsp_document_formatting_edits(source: &str) -> Vec<serde_json::Value> {
    let formatted = format_source(source);
    if formatted == source {
        return Vec::new();
    }

    vec![serde_json::json!({
        "range": {
            "start": {
                "line": 0,
                "character": 0
            },
            "end": lsp_document_end_position(source)
        },
        "newText": formatted
    })]
}

fn lsp_document_end_position(source: &str) -> serde_json::Value {
    let mut line = 0u32;
    let mut character = 0u32;
    let mut chars = source.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\r' if chars.peek() == Some(&'\n') => {}
            '\r' | '\n' => {
                line = line.saturating_add(1);
                character = 0;
            }
            _ => {
                character = character.saturating_add(ch.len_utf16() as u32);
            }
        }
    }
    serde_json::json!({
        "line": line,
        "character": character
    })
}

fn lsp_document_diagnostic_items(
    uri: &str,
    source: &str,
) -> Result<Vec<serde_json::Value>, String> {
    match pollster::block_on(type_check_source_with_gpu(source)) {
        Ok(()) => Ok(Vec::new()),
        Err(CompileError::Diagnostic(mut diagnostic)) => {
            if let Some(label) = diagnostic.primary_label.as_mut() {
                label.path = lsp_document_uri_label_path(uri);
            }
            serde_json::to_value(diagnostic.to_lsp_diagnostic())
                .map(|diagnostic| vec![diagnostic])
                .map_err(|err| format!("serialize LSP diagnostic: {err}"))
        }
        Err(err) => Err(err.to_string()),
    }
}

fn lsp_document_uri_label_path(uri: &str) -> PathBuf {
    uri.strip_prefix("file://")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(uri))
}

fn read_lsp_framed_body(input: &mut impl BufRead) -> Result<LspFrameRead, CliError> {
    let mut content_length = None;
    let mut frame_error: Option<String> = None;
    loop {
        let mut line = String::new();
        let read = input
            .read_line(&mut line)
            .map_err(|err| format!("read LSP header: {err}"))?;
        if read == 0 {
            return if frame_error.is_some() || content_length.is_some() {
                Ok(LspFrameRead::InvalidFrame(frame_error.unwrap_or_else(
                    || "LSP frame ended before the header terminator".to_string(),
                )))
            } else {
                Ok(LspFrameRead::EndOfInput)
            };
        }
        let header = line.trim_end_matches(|ch| ch == '\r' || ch == '\n');
        if header.is_empty() {
            break;
        }
        let Some((name, value)) = header.split_once(':') else {
            frame_error.get_or_insert_with(|| format!("malformed LSP header {header:?}"));
            continue;
        };
        if name.eq_ignore_ascii_case("content-length") {
            match value.trim().parse::<usize>() {
                Ok(parsed) => content_length = Some(parsed),
                Err(err) => {
                    frame_error.get_or_insert_with(|| {
                        format!("invalid LSP Content-Length {value:?}: {err}")
                    });
                }
            }
        }
    }
    if let Some(note) = frame_error {
        return Ok(LspFrameRead::InvalidFrame(note));
    }
    let Some(content_length) = content_length else {
        return Ok(LspFrameRead::InvalidFrame(
            "LSP message missing Content-Length header".to_string(),
        ));
    };
    let mut body = vec![0; content_length];
    match input.read_exact(&mut body) {
        Ok(()) => Ok(LspFrameRead::Body(body)),
        Err(err) if err.kind() == io::ErrorKind::UnexpectedEof => Ok(LspFrameRead::InvalidFrame(
            format!("LSP body ended before Content-Length bytes were available: {err}"),
        )),
        Err(err) => Err(format!("read LSP body: {err}").into()),
    }
}

fn lsp_null_result_response(id: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": serde_json::Value::Null
    })
}

fn write_lsp_response(
    output: &mut impl Write,
    response: &serde_json::Value,
) -> Result<(), CliError> {
    let body =
        serde_json::to_vec(response).map_err(|err| format!("serialize LSP response: {err}"))?;
    write!(output, "Content-Length: {}\r\n\r\n", body.len())
        .map_err(|err| format!("write LSP response header: {err}"))?;
    output
        .write_all(&body)
        .map_err(|err| format!("write LSP response body: {err}"))?;
    output
        .flush()
        .map_err(|err| format!("flush LSP response: {err}"))?;
    Ok(())
}

fn lsp_error_response_with_data(
    id: serde_json::Value,
    code: i32,
    message: impl Into<String>,
    data: serde_json::Value,
) -> serde_json::Value {
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {
            "code": code,
            "message": message.into(),
            "data": data
        }
    })
}

fn invalid_lsp_message_error_response(
    id: serde_json::Value,
    code: i32,
    message: impl Into<String>,
    note: impl Into<String>,
) -> serde_json::Value {
    let diagnostic = Diagnostic::error("LNC0029", "invalid LSP message")
        .with_note(note)
        .with_note(format!(
            "supported LSP methods: {}",
            LSP_STDIO_METHODS.join(", ")
        ));
    lsp_error_response_with_data(
        id,
        code,
        message,
        serde_json::json!({
            "diagnostic": diagnostic,
            "supported_methods": LSP_STDIO_METHODS,
            "no_run_guards": {
                "source_compilation": false,
                "gpu_device_creation": false,
                "target_codegen": false
            }
        }),
    )
}

fn unsupported_lsp_method_error_response(id: serde_json::Value, method: &str) -> serde_json::Value {
    let diagnostic = Diagnostic::error("LNC0028", "unsupported LSP method")
        .with_note(format!(
            "LSP method {method:?} is not supported by this stdio server"
        ))
        .with_note(format!(
            "supported LSP methods: {}",
            LSP_STDIO_METHODS.join(", ")
        ));
    let message = diagnostic.message.clone();
    lsp_error_response_with_data(
        id,
        -32601,
        message,
        serde_json::json!({
            "diagnostic": diagnostic,
            "supported_methods": LSP_STDIO_METHODS,
            "no_run_guards": {
                "source_compilation": false,
                "gpu_device_creation": false,
                "target_codegen": false
            }
        }),
    )
}

fn run_diagnostics(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args = cli_args_without_diagnostic_format(
        "laniusc diagnostics",
        args,
        "--help, registry, categories, formats, explain, source-pack-progress, --diagnostic-format",
    )?;
    let mut args = args.into_iter();
    let Some(command) = args.next() else {
        print_diagnostics_help();
        return Ok(());
    };

    match command.as_str() {
        "-h" | "--help" => {
            print_diagnostics_help();
            Ok(())
        }
        "registry" => {
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics registry",
                    &extra,
                    "no options",
                ));
            }
            let json = diagnostic_registry_json_pretty()
                .map_err(|err| format!("serialize diagnostic registry: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "categories" => {
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics categories",
                    &extra,
                    "no options",
                ));
            }
            let json = diagnostic_categories_json_pretty()
                .map_err(|err| format!("serialize diagnostic categories: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "formats" => {
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics formats",
                    &extra,
                    "no options",
                ));
            }
            let json = diagnostic_output_formats_json_pretty()
                .map_err(|err| format!("serialize diagnostic output formats: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "explain" => {
            let code = args.next().ok_or_else(|| {
                missing_cli_argument_error("laniusc diagnostics explain", "a diagnostic code")
            })?;
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics explain",
                    &extra,
                    "CODE",
                ));
            }
            let json = diagnostic_explanation_json_pretty(&code)
                .map_err(|err| format!("serialize diagnostic explanation: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "source-pack-progress" => {
            let json = diagnostic_source_pack_progress_json_pretty(args)?;
            println!("{json}");
            Ok(())
        }
        other => Err(unknown_cli_subcommand_error(
            "laniusc diagnostics",
            other,
            "registry, categories, formats, explain, source-pack-progress",
        )),
    }
}

fn diagnostic_source_pack_progress_json_pretty(
    args: impl IntoIterator<Item = String>,
) -> Result<String, CliError> {
    let (artifact_root, emit) = parse_diagnostic_source_pack_progress_args(args)?;
    let target = source_pack_artifact_target(&emit);
    let store = FilesystemArtifactStore::new(&artifact_root);
    let progress = store
        .load_work_queue_progress_index_for_target(target)
        .map_err(CliError::from_compile_error)?;
    let progress_index_path = store.work_queue_progress_index_path_for_target(target);
    let complete = progress.completed_item_count == progress.work_item_count;
    let document = serde_json::json!({
        "schema_version": LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION,
        "artifact_root": artifact_root.display().to_string(),
        "target": emit,
        "data_source": "source-pack work queue progress index artifact",
        "record_contract": {
            "kind": "source-pack-work-queue-progress-index",
            "schema_version": progress.version,
            "expected_schema_version": SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            "path": progress_index_path.display().to_string()
        },
        "status": source_pack_progress_status(&progress),
        "progress": {
            "work_item_count": progress.work_item_count,
            "artifact_item_count": progress.artifact_item_count,
            "completed_item_count": progress.completed_item_count,
            "ready_item_count": progress.ready_item_count,
            "ready_artifact_item_count": progress.ready_artifact_item_count,
            "claimed_item_count": progress.claimed_item_count,
            "first_ready_item_index": progress.first_ready_item_index,
            "first_ready_artifact_item_index": progress.first_ready_artifact_item_index,
            "page_size": progress.page_size,
            "page_count": progress.page_count,
            "complete": complete
        },
        "guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
        .map_err(|err| format!("serialize source-pack progress diagnostics: {err}").into())
}

fn parse_diagnostic_source_pack_progress_args(
    args: impl IntoIterator<Item = String>,
) -> Result<(PathBuf, String), CliError> {
    let mut artifact_root = None;
    let mut emit = "wasm".to_string();
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--source-pack-artifact-root" => {
                artifact_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--source-pack-artifact-root",
                        "a persisted source-pack artifact directory",
                    )
                })?));
            }
            "--emit" => {
                emit = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--emit",
                        format!("one of: {LANIUS_EMIT_TARGETS}"),
                    )
                })?;
            }
            flag if flag.starts_with("--source-pack-artifact-root=") => {
                artifact_root = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-artifact-root="),
                ));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc diagnostics source-pack-progress",
                    flag,
                    "--emit, --source-pack-artifact-root",
                ));
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics source-pack-progress",
                    other,
                    "--emit, --source-pack-artifact-root",
                ));
            }
        }
    }
    if emit != "wasm" && emit != "x86_64" {
        return Err(unsupported_cli_option_value_error(
            "--emit",
            &emit,
            LANIUS_EMIT_TARGETS,
            Some(
                "source-pack progress diagnostics select the persisted artifact target by emit mode"
                    .to_string(),
            ),
        ));
    }
    let artifact_root = artifact_root.ok_or_else(|| {
        missing_cli_option_value_error(
            "--source-pack-artifact-root",
            "a persisted source-pack artifact directory",
        )
    })?;
    Ok((artifact_root, emit))
}

fn source_pack_progress_status(progress: &SourcePackWorkQueueProgressIndex) -> &'static str {
    if progress.completed_item_count == progress.work_item_count {
        "complete"
    } else if progress.ready_item_count > 0 {
        "ready"
    } else if progress.claimed_item_count > 0 {
        "claimed"
    } else {
        "waiting"
    }
}

fn diagnostic_categories_json_pretty() -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let categories = registry
        .categories
        .iter()
        .map(|category| {
            let codes = registry
                .codes
                .iter()
                .filter(|code| code.category == *category)
                .map(|code| {
                    serde_json::json!({
                        "code": code.code,
                        "title": code.title,
                        "primary_label_policy": code.primary_label_policy,
                        "default_severity": code.default_severity,
                        "lsp_source": code.lsp_source,
                        "lsp_severity": code.lsp_severity,
                    })
                })
                .collect::<Vec<_>>();
            let unsupported_feature_codes = registry
                .unsupported_features
                .iter()
                .filter_map(|feature| {
                    registry
                        .codes
                        .iter()
                        .any(|code| code.code == feature.code && code.category == *category)
                        .then_some(feature.code)
                })
                .collect::<Vec<_>>();
            serde_json::json!({
                "name": category,
                "code_count": codes.len(),
                "codes": codes,
                "unsupported_feature_codes": unsupported_feature_codes,
            })
        })
        .collect::<Vec<_>>();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION,
        "registry_schema_version": registry.schema_version,
        "categories": categories,
        "no_run_guards": {
            "source_compilation": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

fn cli_args_without_diagnostic_format(
    command: &str,
    args: impl IntoIterator<Item = String>,
    accepted: &str,
) -> Result<Vec<String>, CliError> {
    let mut filtered = Vec::new();
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--diagnostic-format" {
            let value = args.next().ok_or_else(|| {
                missing_cli_option_value_error(
                    "--diagnostic-format",
                    format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                )
            })?;
            validate_diagnostic_format(&value)?;
        } else if let Some(value) = arg.strip_prefix("--diagnostic-format=") {
            validate_diagnostic_format(value)?;
        } else if arg.starts_with("--diagnostic-format") {
            return Err(unknown_cli_option_error(command, &arg, accepted));
        } else {
            filtered.push(arg);
        }
    }
    Ok(filtered)
}

fn run_doctor(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args =
        cli_args_without_diagnostic_format("laniusc doctor", args, "--help, --diagnostic-format")?;
    let mut args = args.into_iter();
    if let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_doctor_help();
                return Ok(());
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc doctor",
                    other,
                    "--help, --diagnostic-format",
                ));
            }
        }
    }

    let json = doctor_report_json_pretty()?;
    println!("{json}");
    Ok(())
}

fn doctor_report_json_pretty() -> Result<String, CliError> {
    let (slangc_status, slangc_check) = slangc_doctor_check();
    let diagnostic_registry_schema_version = diagnostic_registry().schema_version;
    let diagnostic_format_registry = diagnostic_output_formats();
    let status = if slangc_status == "ok" {
        "ok"
    } else {
        "action-required"
    };
    let document = serde_json::json!({
        "schema_version": LANIUS_DOCTOR_SCHEMA_VERSION,
        "status": status,
        "compiler": {
            "name": "laniusc",
            "version": env!("CARGO_PKG_VERSION"),
            "language_edition": LANIUS_LANGUAGE_EDITION,
            "edition_policy": LANIUS_EDITION_POLICY,
            "emit_targets": ["wasm", "x86_64"],
            "target_triples": ["wasm32-unknown-unknown", "x86_64-unknown-linux-gnu"],
            "x86_64": LANIUS_X86_64_SUPPORT,
        },
        "toolchain": {
            "slangc": slangc_check,
            "wgpu": {
                "status": known_or_unknown_status(option_env!("LANIUS_WGPU_VERSION")),
                "version": option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown"),
            },
            "build_profile": {
                "status": known_or_unknown_status(option_env!("LANIUS_BUILD_PROFILE")),
                "value": option_env!("LANIUS_BUILD_PROFILE").unwrap_or("unknown"),
            },
            "shader_artifact_digest": {
                "status": known_or_unknown_status(option_env!("LANIUS_SHADER_ARTIFACT_DIGEST")),
                "value": option_env!("LANIUS_SHADER_ARTIFACT_DIGEST").unwrap_or("unknown"),
            },
        },
        "diagnostics": {
            "cli_flag": diagnostic_format_registry.cli_flag,
            "default_format": diagnostic_format_registry.default_format,
            "accepted_formats": diagnostic_format_registry.accepted_formats,
            "registry_schema_version": diagnostic_registry_schema_version,
            "formats_schema_version": diagnostic_format_registry.schema_version,
            "lsp_source": LSP_DIAGNOSTIC_SOURCE,
            "lsp_position_encoding": LSP_POSITION_ENCODING,
        },
        "no_run_guards": {
            "source_compilation": false,
            "gpu_device_creation": false,
            "pareas_invocation": false,
            "generated_workloads": false,
            "note": "doctor reports local toolchain metadata only; it does not compile source, create a GPU device, run generated gates, or invoke Pareas"
        }
    });
    serde_json::to_string_pretty(&document)
        .map_err(|err| format!("serialize doctor report: {err}").into())
}

fn known_or_unknown_status(value: Option<&str>) -> &'static str {
    match value {
        Some(value) if !value.trim().is_empty() && value != "unknown" => "ok",
        _ => "unknown",
    }
}

fn slangc_doctor_check() -> (&'static str, serde_json::Value) {
    let build_version = option_env!("LANIUS_SLANGC_VERSION").unwrap_or("unknown");
    let configured_slangc = env::var_os("SLANGC").filter(|value| !value.is_empty());
    let (source, command) = match configured_slangc.as_deref() {
        Some(path) => ("SLANGC", PathBuf::from(path)),
        None => ("PATH", PathBuf::from("slangc")),
    };
    let command_display = command.display().to_string();
    match Command::new(&command).arg("--version").output() {
        Ok(output) if output.status.success() => {
            let runtime_version = first_nonempty_line(&output.stdout)
                .or_else(|| first_nonempty_line(&output.stderr))
                .unwrap_or_else(|| build_version.to_string());
            (
                "ok",
                serde_json::json!({
                    "status": "ok",
                    "source": source,
                    "path": command_display,
                    "version": runtime_version,
                    "build_version": build_version,
                    "required": "compatible slangc available through SLANGC or PATH for shader compilation"
                }),
            )
        }
        Ok(output) => (
            "error",
            serde_json::json!({
                "status": "error",
                "source": source,
                "path": command_display,
                "exit_status": output.status.code(),
                "stdout": String::from_utf8_lossy(&output.stdout).trim(),
                "stderr": String::from_utf8_lossy(&output.stderr).trim(),
                "build_version": build_version,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
        Err(err) if err.kind() == io::ErrorKind::NotFound => (
            "missing",
            serde_json::json!({
                "status": "missing",
                "source": source,
                "path": command_display,
                "build_version": build_version,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
        Err(err) => (
            "error",
            serde_json::json!({
                "status": "error",
                "source": source,
                "path": command_display,
                "error": err.to_string(),
                "build_version": build_version,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
    }
}

fn first_nonempty_line(bytes: &[u8]) -> Option<String> {
    String::from_utf8_lossy(bytes)
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(ToOwned::to_owned)
}

fn package_metadata_cli_error(flag: &str, path: &std::path::Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic.with_note(
            format!("package metadata context: {flag} {}", path.display()),
        )),
        CompileError::GpuFrontend(message) => package_metadata_invalid_error(flag, path, message),
        err => package_metadata_invalid_error(flag, path, err.to_string()),
    }
}

fn package_metadata_invalid_error(flag: &str, path: &std::path::Path, message: String) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0037", "package metadata invalid")
            .with_note(format!("package metadata selector: {flag}"))
            .with_note(format!("package metadata path: {}", path.display()))
            .with_note(message)
            .with_help(
                "fix the package manifest or regenerate the package lockfile before compiling",
            ),
    )
}

fn package_compile_cli_error(flag: &str, path: &std::path::Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(
            diagnostic.with_note(format!("package context: {flag} {}", path.display())),
        ),
        err => package_metadata_cli_error(flag, path, err),
    }
}

fn emit_for_target_triple(target_triple: &str) -> Option<&'static str> {
    match target_triple {
        "wasm32-unknown-unknown" => Some("wasm"),
        "x86_64-unknown-linux-gnu" => Some("x86_64"),
        _ => None,
    }
}

fn print_help() {
    eprintln!(
        "Usage: laniusc [--version] [--edition unstable-alpha] [--emit x86_64|wasm] [--target triple] [--diagnostic-format text|json|lsp-json] [--package-manifest path] [--package-lockfile path] [--stdlib path]... [--stdlib-root dir] [--source-root dir] [-o output] [--source-pack-descriptors] [--source-pack-manifest path] [--source-pack-library-manifest path] [--source-pack-artifact-root path] [--source-pack-metadata-only] [--source-pack-prepare-only] [--source-pack-metadata-max-libraries N] [--source-pack-metadata-max-source-files N] [--source-pack-build-from-metadata] [--source-pack-build-prepare-only] [--source-pack-build-max-items N] [--source-pack-max-items N] [--source-pack-max-ready-items N] [--source-pack-legacy-in-memory] <input.lani> [more-input.lani...]\n\
         Usage: laniusc check [--edition unstable-alpha] [--emit x86_64|wasm] [--target triple] [--diagnostic-format text|json|lsp-json] [--package-manifest path] [--package-lockfile path] [--stdlib-root dir] [--source-root dir] <input.lani>\n\
         Usage: laniusc package lock --manifest path -o path\n\
         Usage: laniusc lsp capabilities\n\
         Usage: laniusc lsp serve --stdio\n\
         Usage: laniusc diagnostics registry\n\
         Usage: laniusc diagnostics categories\n\
         Usage: laniusc diagnostics formats\n\
         Usage: laniusc diagnostics explain CODE\n\
         Usage: laniusc diagnostics source-pack-progress --source-pack-artifact-root dir [--emit wasm|x86_64]\n\
         Usage: laniusc doctor\n\
         Usage: laniusc fmt [--check] [--diagnostic-format text|json|lsp-json] (<input.lani> [more-input.lani...]|--stdin|-)\n\
         Emits the selected target using GPU lexing, GPU parsing, GPU type checking, and GPU emission.\n\
         check runs the same bounded GPU compiler path for diagnostics and exits without writing target bytes.\n\
         package lock generates a JSON package lockfile from a package manifest using control-plane package metadata only; semantic module identity still comes from GPU-parsed records when the lockfile is used for compilation.\n\
         lsp capabilities prints no-run JSON metadata for editor experiments, including diagnostic codes, LSP source, severity, UTF-16 position encoding, full-document sync mode, document formatting, and supported stdio methods. lsp serve --stdio handles initialize/shutdown without compiling source, accepts full-document didChange text only, formats opened documents with the lexical formatter without GPU work, and serves opened-document pull diagnostics through the GPU type-check path without target codegen.\n\
         diagnostics registry prints the stable diagnostic registry JSON directly for tools that do not need LSP capability metadata; diagnostics categories groups codes by stable category for filter-building tools; diagnostics formats prints the accepted diagnostic render formats and payload contracts; diagnostics explain prints one code-specific JSON explanation; diagnostics source-pack-progress prints persisted work-queue progress from source-pack artifact records without loading source.\n\
         doctor prints a no-run JSON toolchain report for installation checks, including compiler version, language edition, target surface, diagnostic format metadata, Slang availability from SLANGC or PATH, build metadata, and guards proving it did not compile source or create a GPU device.\n\
         fmt formats one or more source files in place using the alpha lexical formatter; --check verifies formatting without writing.\n\
         Current language edition: {edition}; {policy}.\n\
         --edition selects the language edition for this invocation; only {edition} is accepted today and unsupported editions are rejected before compilation.\n\
         Accepted emit targets: {targets}.\n\
         Accepted target triples: {target_triples}; --target must match --emit and unsupported triples are rejected before compilation.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON rendering for compiler diagnostics and formatter check diagnostics; JSON diagnostics are emitted without the laniusc text prefix, and lsp-json is a single diagnostic object, not a language-server publishDiagnostics envelope.\n\
         --package-manifest loads a JSON package manifest with package, roots, optional stdlib_root, and entry fields; package names and paths are control-plane loading metadata only, while module identity still comes from GPU-parsed module/import records. It currently uses the in-memory source-root compiler path.\n\
         --package-lockfile loads a JSON package lockfile with absolute resolved roots and entry path; package names and resolved paths remain control-plane loading metadata only, while module identity still comes from GPU-parsed module/import records.\n\
         Repeating --stdlib adds explicitly supplied source-pack files before positional user files; multi-file source-pack inputs compile only from an explicit prepared descriptor artifact root.\n\
         --source-root maps leading module-path imports from one entry file to files below a user source root, such as app::util -> src/app/util.lani; --stdlib-root can be combined with --source-root as a fallback for stdlib modules such as core::i32 -> stdlib/core/i32.lani. Root loading feeds discovered files to the GPU source-pack resolver without source rewriting; descriptor mode for source roots is not implemented yet.\n\
         --source-pack-manifest names a previously prepared JSON ExplicitSourcePackPathManifest artifact root; use --source-pack-library-manifest for bounded metadata preparation.\n\
         --source-pack-library-manifest reads newline-delimited JSON library records, each with library_id, source_file_count, path_list, and dependency_library_ids; each path_list is streamed line by line.\n\
         --source-pack-metadata-only stores source-pack metadata and exits; JSONL library manifests store one bounded chunk by default, --source-pack-metadata-max-libraries overrides how many new libraries that metadata pass stores, and --source-pack-metadata-max-source-files bounds the source-file records consumed by that chunk; --source-pack-build-from-metadata builds and runs from persisted metadata.\n\
         --source-pack-prepare-only performs one bounded preparation chunk from source-pack inputs and exits: metadata first, then build preparation after metadata is complete.\n\
         --source-pack-build-prepare-only performs one bounded build-preparation chunk from persisted metadata and exits; --source-pack-build-max-items bounds that preparation chunk and defaults to 64.\n\
         --source-pack-descriptors is the default source-pack mode; descriptor builds currently write linked-output contract descriptors and require --emit-contract; --source-pack-artifact-root selects the persisted descriptor directory; --source-pack-max-items limits how many queued work items this invocation submits and is capped at 64; --source-pack-legacy-in-memory opts into the old whole-pack byte emitter.\n\
         x86_64 currently supports {x86_support}.\n\
         --version prints compiler, language-edition, target, formatter, LSP schema, Slang, wgpu, build-profile, and shader artifact details.\n\
         Without an input file, compiles a tiny built-in sample to stdout.",
        edition = LANIUS_LANGUAGE_EDITION,
        policy = LANIUS_EDITION_POLICY,
        targets = LANIUS_EMIT_TARGETS,
        target_triples = LANIUS_TARGET_TRIPLES,
        x86_support = LANIUS_X86_64_SUPPORT,
    );
}

fn print_package_help() {
    eprintln!(
        "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path\n\
         Generates package tooling artifacts.\n\
         lock resolves a package manifest and writes a JSON package lockfile."
    );
}

fn print_package_lock_help() {
    eprintln!(
        "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path\n\
         Resolves a package manifest and writes a JSON package lockfile. Package roots and paths are control-plane loading metadata only; semantic module identity remains GPU-parsed."
    );
}

fn print_lsp_help() {
    eprintln!(
        "Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities\n\
         Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio\n\
         capabilities prints no-run JSON metadata for editor experiments: diagnostic registry, LSP source, severity, UTF-16 position encoding, full-document sync mode, formatter metadata, and the supported stdio methods.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for command-line invocation diagnostics before the stdio server starts.\n\
         serve --stdio starts a minimal JSON-RPC LSP server that handles initialize/shutdown without compiling source, tracks opened documents, rejects ranged incremental changes, returns full-document textDocument/formatting edits without GPU work, and returns pull diagnostics through textDocument/diagnostic without target codegen."
    );
}

fn print_diagnostics_help() {
    eprintln!(
        "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] categories\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] formats\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] source-pack-progress --source-pack-artifact-root dir [--emit wasm|x86_64]\n\
         registry prints the combined diagnostic registry JSON: schema version, codes, categories, and unsupported-feature boundaries.\n\
         categories prints stable diagnostic categories with grouped code metadata and unsupported-feature code markers.\n\
         formats prints accepted --diagnostic-format values with output stream, payload, position, and envelope metadata.\n\
         explain prints one code-specific JSON explanation without compiling source.\n\
         source-pack-progress prints the persisted source-pack work-queue progress index for the selected emit target without loading source, creating a GPU device, or running target codegen.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for invocation diagnostics on this no-run tooling surface."
    );
}

fn print_doctor_help() {
    eprintln!(
        "Usage: laniusc doctor [--diagnostic-format text|json|lsp-json]\n\
         Prints a no-run JSON toolchain report for installation checks.\n\
         The report includes compiler version, language edition, target surface, diagnostic format metadata, Slang availability from SLANGC or PATH, build metadata, and explicit no-run guards; it does not compile source, create a GPU device, run generated gates, or invoke Pareas."
    );
}

fn print_fmt_help() {
    eprintln!(
        "Usage: laniusc fmt [--check] [--diagnostic-format text|json|lsp-json] (<input.lani> [more-input.lani...]|--stdin|-)\n\
         Formats one or more source files in place, or formats stdin to stdout with --stdin or -.\n\
         --check verifies formatting without writing.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for check failures."
    );
}

fn print_version() {
    println!(
        "laniusc {}\n\
         language-edition: {}\n\
         edition-policy: {}\n\
         targets: {}\n\
         target-triples: {}\n\
         x86_64: {}\n\
         formatter: {}\n\
         lsp-capabilities-schema: {}\n\
         lsp-experimental-schema: {}\n\
         slangc: {}\n\
         wgpu: {}\n\
         build-profile: {}\n\
         shader-artifact-digest: {}",
        env!("CARGO_PKG_VERSION"),
        LANIUS_LANGUAGE_EDITION,
        LANIUS_EDITION_POLICY,
        LANIUS_EMIT_TARGETS,
        LANIUS_TARGET_TRIPLES,
        LANIUS_X86_64_SUPPORT,
        LANIUS_FORMATTER_CONTRACT,
        LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
        LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
        option_env!("LANIUS_SLANGC_VERSION").unwrap_or("unknown"),
        option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown"),
        option_env!("LANIUS_BUILD_PROFILE").unwrap_or("unknown"),
        option_env!("LANIUS_SHADER_ARTIFACT_DIGEST").unwrap_or("unknown"),
    );
}
