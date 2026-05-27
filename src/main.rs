use std::{env, path::PathBuf};

use laniusc::{
    compiler::{
        compile_source_to_wasm_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen_from_path,
        compile_source_to_x86_64_with_gpu_codegen,
        compile_source_to_x86_64_with_gpu_codegen_from_path,
    },
    gpu::device,
};

mod cli;

use cli::{
    CliEmission,
    SourcePackCliOptions,
    parse_usize_arg,
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
    write_cli_emission,
};

fn main() {
    if let Err(err) = run() {
        eprintln!("laniusc: {err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut inputs: Vec<PathBuf> = Vec::new();
    let mut stdlib_paths: Vec<PathBuf> = Vec::new();
    let mut output: Option<PathBuf> = None;
    let mut emit = "wasm".to_string();
    let mut source_pack = SourcePackCliOptions::default();

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            "--emit" => {
                emit = args
                    .next()
                    .ok_or_else(|| "--emit requires a target".to_string())?;
            }
            "--stdlib" => {
                stdlib_paths
                    .push(PathBuf::from(args.next().ok_or_else(|| {
                        "--stdlib requires a source file path".to_string()
                    })?));
            }
            "--source-pack-descriptors" => {
                source_pack.descriptors = true;
            }
            "--source-pack-legacy-in-memory" => {
                source_pack.legacy_in_memory = true;
            }
            "--source-pack-manifest" => {
                source_pack.manifest =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        "--source-pack-manifest requires a path".to_string()
                    })?));
            }
            "--source-pack-library-manifest" => {
                source_pack.library_manifest =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        "--source-pack-library-manifest requires a path".to_string()
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
                source_pack.metadata_max_libraries = Some(parse_usize_arg(
                    "--source-pack-metadata-max-libraries",
                    args.next(),
                )?);
            }
            "--source-pack-metadata-max-source-files" => {
                source_pack.metadata_max_source_files = Some(parse_usize_arg(
                    "--source-pack-metadata-max-source-files",
                    args.next(),
                )?);
            }
            "--source-pack-build-max-items" => {
                source_pack.build_max_items =
                    parse_usize_arg("--source-pack-build-max-items", args.next())?;
            }
            "--source-pack-artifact-root" => {
                source_pack.artifact_root =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        "--source-pack-artifact-root requires a path".to_string()
                    })?));
            }
            "--source-pack-max-items" => {
                source_pack.max_items = parse_usize_arg("--source-pack-max-items", args.next())?;
            }
            "--source-pack-max-ready-items" => {
                source_pack.max_ready_items =
                    parse_usize_arg("--source-pack-max-ready-items", args.next())?;
            }
            "-o" | "--out" => {
                output = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| format!("{arg} requires an output path"))?,
                ));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with("--stdlib=") => {
                stdlib_paths.push(PathBuf::from(flag.trim_start_matches("--stdlib=")));
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
                source_pack.metadata_max_libraries = Some(parse_usize_value(
                    "--source-pack-metadata-max-libraries",
                    flag.trim_start_matches("--source-pack-metadata-max-libraries="),
                )?);
            }
            flag if flag.starts_with("--source-pack-metadata-max-source-files=") => {
                source_pack.metadata_max_source_files = Some(parse_usize_value(
                    "--source-pack-metadata-max-source-files",
                    flag.trim_start_matches("--source-pack-metadata-max-source-files="),
                )?);
            }
            flag if flag.starts_with("--source-pack-build-max-items=") => {
                source_pack.build_max_items = parse_usize_value(
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
                source_pack.max_items = parse_usize_value(
                    "--source-pack-max-items",
                    flag.trim_start_matches("--source-pack-max-items="),
                )?;
            }
            flag if flag.starts_with("--source-pack-max-ready-items=") => {
                source_pack.max_ready_items = parse_usize_value(
                    "--source-pack-max-ready-items",
                    flag.trim_start_matches("--source-pack-max-ready-items="),
                )?;
            }
            flag if flag.starts_with('-') => {
                return Err(format!("unknown flag {flag}"));
            }
            path => {
                inputs.push(PathBuf::from(path));
            }
        }
    }

    if emit != "wasm" && emit != "x86_64" {
        return Err(format!(
            "unsupported emit target {emit:?}; accepted targets: wasm, x86_64 (x86_64 currently supports bounded GPU HIR main-return, resolver-backed scalar-const, and direct scalar helper-call source-pack slices)"
        ));
    }
    if source_pack.descriptors && source_pack.legacy_in_memory {
        return Err(
            "--source-pack-descriptors and --source-pack-legacy-in-memory are mutually exclusive"
                .into(),
        );
    }
    if source_pack.manifest.is_some() && source_pack.legacy_in_memory {
        return Err("--source-pack-manifest requires descriptor mode; it cannot be combined with --source-pack-legacy-in-memory".into());
    }
    if source_pack.library_manifest.is_some() && source_pack.legacy_in_memory {
        return Err("--source-pack-library-manifest requires descriptor mode; it cannot be combined with --source-pack-legacy-in-memory".into());
    }
    if source_pack.manifest.is_some() && source_pack.library_manifest.is_some() {
        return Err(
            "--source-pack-manifest and --source-pack-library-manifest are mutually exclusive"
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
        return Err("--source-pack-prepare-only and --source-pack-build-prepare-only are mutually exclusive".into());
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
        && (!stdlib_paths.is_empty() || !inputs.is_empty())
    {
        return Err(
            "--source-pack-manifest and --source-pack-library-manifest describe all source-pack libraries; do not also pass --stdlib or positional input files"
                .into(),
        );
    }

    let source_pack_requested = source_pack.manifest.is_some()
        || source_pack.library_manifest.is_some()
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
        CliEmission::File(compile_from_metadata_with_descriptor_queue(
            &emit,
            &source_pack,
        )?)
    } else if let Some(library_manifest_path) = source_pack.library_manifest.as_deref() {
        CliEmission::File(compile_source_pack_library_manifest_with_descriptor_queue(
            &emit,
            library_manifest_path,
            &source_pack,
        )?)
    } else if let Some(manifest_path) = source_pack.manifest.as_deref() {
        CliEmission::File(compile_source_pack_manifest_with_descriptor_queue(
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
            CliEmission::File(compile_source_pack_with_descriptor_queue(
                &emit,
                &stdlib_paths,
                &inputs,
                &source_pack,
            )?)
        }
    } else if let Some(input) = inputs.first() {
        if emit == "wasm" {
            CliEmission::Bytes(
                pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(input))
                    .map_err(|err| err.to_string())?,
            )
        } else {
            CliEmission::Bytes(
                pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(input))
                    .map_err(|err| err.to_string())?,
            )
        }
    } else if emit == "wasm" {
        CliEmission::Bytes(
            pollster::block_on(compile_source_to_wasm_with_gpu_codegen("let x = 7;\n"))
                .map_err(|err| err.to_string())?,
        )
    } else {
        CliEmission::Bytes(
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
                "fn main() { return 7; }\n",
            ))
            .map_err(|err| err.to_string())?,
        )
    };
    device::persist_pipeline_cache();
    write_cli_emission(emitted, output, &emit)?;
    Ok(())
}

fn print_help() {
    eprintln!(
        "Usage: laniusc [--emit x86_64|wasm] [--stdlib path]... [-o output] [--source-pack-descriptors] [--source-pack-manifest path] [--source-pack-library-manifest path] [--source-pack-artifact-root path] [--source-pack-metadata-only] [--source-pack-prepare-only] [--source-pack-metadata-max-libraries N] [--source-pack-metadata-max-source-files N] [--source-pack-build-from-metadata] [--source-pack-build-prepare-only] [--source-pack-build-max-items N] [--source-pack-max-items N] [--source-pack-max-ready-items N] [--source-pack-legacy-in-memory] <input.lani> [more-input.lani...]\n\
         Emits the selected target using GPU lexing, GPU parsing, GPU type checking, and GPU emission.\n\
         Repeating --stdlib adds explicitly supplied source-pack files before positional user files; multi-file source-pack inputs compile only from an explicit prepared descriptor artifact root.\n\
         --source-pack-manifest names a previously prepared JSON ExplicitSourcePackPathManifest artifact root; use --source-pack-library-manifest for bounded metadata preparation.\n\
         --source-pack-library-manifest reads newline-delimited JSON library records, each with library_id, source_file_count, path_list, and dependency_library_ids; each path_list is streamed line by line.\n\
         --source-pack-metadata-only stores source-pack metadata and exits; JSONL library manifests store one bounded chunk by default, --source-pack-metadata-max-libraries overrides how many new libraries that metadata pass stores, and --source-pack-metadata-max-source-files bounds the source-file records consumed by that chunk; --source-pack-build-from-metadata builds and runs from persisted metadata.\n\
         --source-pack-prepare-only performs one bounded preparation chunk from source-pack inputs and exits: metadata first, then build preparation after metadata is complete.\n\
         --source-pack-build-prepare-only performs one bounded build-preparation chunk from persisted metadata and exits; --source-pack-build-max-items bounds that preparation chunk and defaults to 64.\n\
         --source-pack-descriptors is the default source-pack mode; --source-pack-artifact-root selects the persisted descriptor directory; --source-pack-max-items limits how many queued work items this invocation submits and is capped at 64; --source-pack-legacy-in-memory opts into the old whole-pack path.\n\
         x86_64 currently supports bounded GPU HIR main-return, resolver-backed scalar-const, and direct scalar helper-call source-pack slices and rejects unsupported source shapes through GPU status.\n\
         Without an input file, compiles a tiny built-in sample to stdout."
    );
}
