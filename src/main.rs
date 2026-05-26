#[cfg(test)]
use std::{
    collections::{BTreeMap, BTreeSet},
    time::{SystemTime, UNIX_EPOCH},
};
use std::{
    env,
    fs,
    io::{BufRead, BufReader, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

#[cfg(test)]
use laniusc::compiler::ExplicitSourcePackPathManifest;
use laniusc::{
    codegen::unit::{
        CodegenUnitLimits,
        DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES,
        SourcePackArtifactTarget,
        SourcePackBuildShardLimits,
        SourcePackJobBatchLimits,
    },
    compiler::{
        ExplicitSourceLibraryPathDependencyStream,
        SourcePackFilesystemArtifactStore,
        SourcePackFilesystemLibraryMetadataPrepareStepResult,
        SourcePackFilesystemWorkQueueWorkerRunExecutionResult,
        compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen,
        compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen_from_path,
        compile_source_to_x86_64_with_gpu_codegen,
        compile_source_to_x86_64_with_gpu_codegen_from_path,
        execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors,
        execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors,
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target,
        prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target,
    },
    gpu::device,
};

const DEFAULT_SOURCE_PACK_MAX_ITEMS: usize = 64;
const DEFAULT_SOURCE_PACK_MAX_READY_ITEMS: usize = 64;
const DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES: usize = 64;
const DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES: usize =
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
const DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS: usize = 64;
const SOURCE_PACK_LIBRARY_MANIFEST_READ_PROGRESS_VERSION: u32 = 1;
const SOURCE_PACK_LIBRARY_MANIFEST_MAX_LINE_BYTES: usize = 4096;
const SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK: usize = 64;
const SOURCE_PACK_PATH_LIST_MAX_LINE_BYTES: usize = 4096;
const SOURCE_PACK_PATH_LIST_MAX_BLANK_LINES_PER_ITEM: usize = 64;

#[derive(Clone, Debug)]
struct SourcePackCliOptions {
    descriptors: bool,
    legacy_in_memory: bool,
    manifest: Option<PathBuf>,
    library_manifest: Option<PathBuf>,
    metadata_only: bool,
    prepare_only: bool,
    build_from_metadata: bool,
    build_prepare_only: bool,
    metadata_max_libraries: Option<usize>,
    metadata_max_source_files: Option<usize>,
    build_max_items: usize,
    artifact_root: Option<PathBuf>,
    max_items: usize,
    max_ready_items: usize,
}

impl Default for SourcePackCliOptions {
    fn default() -> Self {
        Self {
            descriptors: false,
            legacy_in_memory: false,
            manifest: None,
            library_manifest: None,
            metadata_only: false,
            prepare_only: false,
            build_from_metadata: false,
            build_prepare_only: false,
            metadata_max_libraries: None,
            metadata_max_source_files: None,
            build_max_items: DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
            artifact_root: None,
            max_items: DEFAULT_SOURCE_PACK_MAX_ITEMS,
            max_ready_items: DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
        }
    }
}

enum CliEmission {
    Bytes(Vec<u8>),
    File(PathBuf),
}

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
struct SourcePackLibraryManifestReadProgress {
    version: u32,
    target: SourcePackArtifactTarget,
    manifest_path: PathBuf,
    library_count: usize,
    next_byte_offset: u64,
}

#[derive(Clone, Debug, serde::Deserialize)]
struct SourcePackLibraryPathManifestEntry {
    library_id: u32,
    source_file_count: usize,
    path_list: PathBuf,
    #[serde(default)]
    dependency_library_ids: Vec<u32>,
}

#[derive(Debug)]
struct SourcePackPathListFile {
    path: PathBuf,
    base_dir: PathBuf,
}

impl SourcePackPathListFile {
    fn deferred(path: PathBuf) -> Self {
        let base_dir = path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."));
        Self { path, base_dir }
    }
}

struct SourcePackPathListFileIter {
    path: PathBuf,
    base_dir: PathBuf,
    line_number: usize,
    byte_offset: u64,
    reader: BufReader<fs::File>,
    line: String,
}

impl IntoIterator for SourcePackPathListFile {
    type IntoIter = SourcePackPathListFileIter;
    type Item = PathBuf;

    fn into_iter(self) -> Self::IntoIter {
        let reader = BufReader::new(fs::File::open(&self.path).unwrap_or_else(|err| {
            panic!("open source-pack path list {}: {err}", self.path.display())
        }));
        SourcePackPathListFileIter {
            path: self.path,
            base_dir: self.base_dir,
            line_number: 0,
            byte_offset: 0,
            reader,
            line: String::new(),
        }
    }
}

impl Iterator for SourcePackPathListFileIter {
    type Item = PathBuf;

    fn next(&mut self) -> Option<Self::Item> {
        let mut blank_line_count = 0usize;
        loop {
            let bytes_read = read_source_pack_path_list_line(
                &mut self.reader,
                &mut self.line,
                &self.path,
                self.line_number + 1,
                self.byte_offset,
            )
            .unwrap_or_else(|err| panic!("{err}"));
            if bytes_read == 0 {
                return None;
            }
            self.byte_offset = self
                .byte_offset
                .checked_add(bytes_read as u64)
                .unwrap_or_else(|| {
                    panic!(
                        "source-pack path list {} byte offset overflows",
                        self.path.display()
                    )
                });
            self.line_number += 1;
            let path = self.line.trim();
            if path.is_empty() {
                blank_line_count += 1;
                if blank_line_count > SOURCE_PACK_PATH_LIST_MAX_BLANK_LINES_PER_ITEM {
                    panic!(
                        "source-pack path list {} has more than {SOURCE_PACK_PATH_LIST_MAX_BLANK_LINES_PER_ITEM} blank lines before the next path at line {}; remove blank padding",
                        self.path.display(),
                        self.line_number
                    );
                }
                continue;
            }
            return Some(resolve_manifest_relative_path(
                &self.base_dir,
                Path::new(path),
            ));
        }
    }
}

fn read_source_pack_path_list_line(
    reader: &mut impl BufRead,
    line: &mut String,
    path: &Path,
    line_number: usize,
    byte_offset: u64,
) -> Result<usize, String> {
    read_bounded_utf8_line(
        reader,
        line,
        SOURCE_PACK_PATH_LIST_MAX_LINE_BYTES,
        || {
            format!(
                "source-pack path list {} line {line_number} at byte offset {byte_offset}",
                path.display()
            )
        },
        "split large path-list records",
    )
}

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
        prepare_source_pack_metadata_only(&emit, &stdlib_paths, &inputs, &source_pack)?;
        return Ok(());
    }
    if source_pack.prepare_only {
        prepare_source_pack_inputs_chunk_only(&emit, &stdlib_paths, &inputs, &source_pack)?;
        return Ok(());
    }
    if source_pack.build_prepare_only {
        prepare_source_pack_build_from_metadata_chunk_only(&emit, &source_pack)?;
        return Ok(());
    }

    let emitted = if source_pack.build_from_metadata {
        CliEmission::File(compile_source_pack_from_metadata_with_descriptor_queue(
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

fn parse_usize_arg(flag: &str, value: Option<String>) -> Result<usize, String> {
    let value = value.ok_or_else(|| format!("{flag} requires a non-negative integer"))?;
    parse_usize_value(flag, &value)
}

fn parse_usize_value(flag: &str, value: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|err| format!("{flag} requires a non-negative integer, got {value:?}: {err}"))
}

fn source_pack_metadata_max_libraries(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .metadata_max_libraries
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .max(1)
}

fn source_pack_metadata_max_source_files(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .metadata_max_source_files
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .max(1)
}

fn source_pack_build_max_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .build_max_items
        .min(DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS)
        .max(1)
}

fn source_pack_max_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .max_items
        .min(DEFAULT_SOURCE_PACK_MAX_ITEMS)
        .max(1)
}

fn source_pack_max_ready_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .max_ready_items
        .min(DEFAULT_SOURCE_PACK_MAX_READY_ITEMS)
        .max(1)
}

fn prepare_source_pack_metadata_only(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-metadata-only requires --source-pack-artifact-root",
    )?;
    let target = source_pack_artifact_target(emit);
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        eprintln!(
            "source-pack metadata already prepared at {}; target={:?}",
            artifact_root.display(),
            target
        );
        return Ok(());
    }
    if source_pack.library_manifest.is_some()
        || source_pack.metadata_max_libraries.is_some()
        || source_pack.metadata_max_source_files.is_some()
    {
        let max_new_libraries = source_pack_metadata_max_libraries(source_pack);
        let max_new_source_files = source_pack_metadata_max_source_files(source_pack);
        let metadata = prepare_source_pack_metadata_chunk(
            stdlib_paths,
            inputs,
            source_pack,
            artifact_root,
            target,
            max_new_libraries,
            max_new_source_files,
        )?;
        eprintln!(
            "source-pack metadata chunk prepared at {}; target={:?} complete={} libraries={} new_libraries={} source_files={} source_bytes={} source_lines={}",
            artifact_root.display(),
            metadata.target,
            metadata.complete,
            metadata.library_count,
            metadata.new_library_count,
            metadata.source_file_count,
            metadata.source_byte_count,
            metadata.source_line_count
        );
        return Ok(());
    }
    if let Some(manifest_path) = source_pack.manifest.as_deref() {
        return Err(format!(
            "--source-pack-metadata-only with --source-pack-manifest would require reading the whole JSON manifest {}; use --source-pack-library-manifest for bounded JSONL metadata chunks",
            manifest_path.display()
        ));
    }
    if !stdlib_paths.is_empty() || !inputs.is_empty() {
        return Err(
            "--source-pack-metadata-only with raw --stdlib or positional source paths would prepare a whole path list; use --source-pack-library-manifest for bounded JSONL metadata chunks"
                .into(),
        );
    }
    Err(
        "--source-pack-metadata-only requires --source-pack-library-manifest source-pack inputs"
            .into(),
    )
}

fn prepare_source_pack_metadata_chunk(
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
    artifact_root: &PathBuf,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    max_new_source_files: usize,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareStepResult, String> {
    if let Some(library_manifest_path) = source_pack.library_manifest.as_deref() {
        let persisted_library_count =
            source_pack_artifact_root_persisted_library_partition_prefix_count(
                artifact_root,
                target,
            );
        let progress = load_source_pack_library_manifest_read_progress_or_default(
            artifact_root,
            target,
            library_manifest_path,
            persisted_library_count,
        )?;
        if progress.library_count != persisted_library_count {
            return Err(format!(
                "source-pack library manifest {} read progress records {} libraries, but artifact root {} contains {} persisted metadata partitions",
                library_manifest_path.display(),
                progress.library_count,
                artifact_root.display(),
                persisted_library_count
            ));
        }
        let chunk = load_source_pack_library_manifest_entries_chunk_from_offset(
            library_manifest_path,
            progress.next_byte_offset,
            max_new_libraries,
            max_new_source_files,
        )?;
        let manifest_complete_after_input = chunk.manifest_complete_after_input;
        let next_byte_offset = chunk.next_byte_offset;
        let new_entries = chunk.entries;
        let libraries = source_pack_library_manifest_prefix_path_dependency_streams(new_entries)?;
        let result = prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target(
            libraries,
            artifact_root,
            target,
            max_new_libraries,
            manifest_complete_after_input,
        )
        .map_err(|err| err.to_string())?;
        let next_progress = SourcePackLibraryManifestReadProgress {
            library_count: progress
                .library_count
                .checked_add(result.new_library_count)
                .ok_or_else(|| {
                    "source-pack library manifest read progress library count overflows".to_string()
                })?,
            next_byte_offset,
            ..progress
        };
        store_source_pack_library_manifest_read_progress(artifact_root, &next_progress)?;
        Ok(result)
    } else if let Some(manifest_path) = source_pack.manifest.as_deref() {
        Err(format!(
            "--source-pack-metadata chunk limits with --source-pack-manifest would require reading the whole JSON manifest {}; use --source-pack-library-manifest for bounded JSONL metadata chunks",
            manifest_path.display()
        ))
    } else if !stdlib_paths.is_empty() || !inputs.is_empty() {
        Err(
            "--source-pack-metadata chunk limits require --source-pack-manifest or --source-pack-library-manifest for multi-library metadata chunks"
                .into(),
        )
    } else {
        Err("--source-pack-metadata chunk limits require source-pack inputs".into())
    }
}

fn prepare_source_pack_build_from_metadata_chunk_only(
    emit: &str,
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-build-from-metadata requires --source-pack-artifact-root",
    )?;
    let limits = CodegenUnitLimits::default();
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let shard_limits = SourcePackBuildShardLimits::default();
    let step =
        prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            source_pack_artifact_target(emit),
            source_pack_build_max_items(source_pack),
        )
        .map_err(|err| err.to_string())?;
    eprintln!(
        "source-pack build chunk prepared at {}; target={:?} complete={} stage={:?} next_stage={:?} new_items={}",
        artifact_root.display(),
        step.target,
        step.complete,
        step.stage,
        step.next_stage,
        step.new_item_count
    );
    if let Some(prepared) = step.prepared {
        eprintln!(
            "source-pack build prepared at {}; target={:?} libraries={} source_files={} jobs={} batches={} artifact_shards={} work_items={}",
            prepared.artifact_root.display(),
            prepared.target,
            prepared.library_count,
            prepared.source_file_count,
            prepared.scheduled_job_count,
            prepared.batch_count,
            prepared.artifact_shard_count,
            prepared.work_queue_item_count
        );
    }
    Ok(())
}

fn write_cli_emission(
    emitted: CliEmission,
    output: Option<PathBuf>,
    emit: &str,
) -> Result<(), String> {
    match emitted {
        CliEmission::Bytes(bytes) => {
            if let Some(output) = output {
                fs::write(&output, bytes)
                    .map_err(|err| format!("write {}: {err}", output.display()))?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                std::io::stdout()
                    .write_all(&bytes)
                    .map_err(|err| format!("write stdout: {err}"))?;
            }
        }
        CliEmission::File(path) => {
            if let Some(output) = output {
                fs::copy(&path, &output).map_err(|err| {
                    format!(
                        "copy linked output {} to {}: {err}",
                        path.display(),
                        output.display()
                    )
                })?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                let mut file = fs::File::open(&path)
                    .map_err(|err| format!("open linked output {}: {err}", path.display()))?;
                std::io::copy(&mut file, &mut std::io::stdout()).map_err(|err| {
                    format!("stream linked output {} to stdout: {err}", path.display())
                })?;
            }
        }
    }
    Ok(())
}

fn mark_output_executable_if_needed(output: &Path, emit: &str) -> Result<(), String> {
    #[cfg(unix)]
    if emit != "wasm" {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(output)
            .map_err(|err| format!("stat {}: {err}", output.display()))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(output, permissions)
            .map_err(|err| format!("chmod {}: {err}", output.display()))?;
    }
    #[cfg(not(unix))]
    let _ = (output, emit);
    Ok(())
}

fn prepare_source_pack_inputs_chunk_only(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-prepare-only requires --source-pack-artifact-root",
    )?;
    let target = source_pack_artifact_target(emit);
    if !source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        if source_pack.manifest.is_some() || source_pack.library_manifest.is_some() {
            let max_new_libraries = source_pack_metadata_max_libraries(source_pack);
            let max_new_source_files = source_pack_metadata_max_source_files(source_pack);
            let metadata = prepare_source_pack_metadata_chunk(
                stdlib_paths,
                inputs,
                source_pack,
                artifact_root,
                target,
                max_new_libraries,
                max_new_source_files,
            )?;
            eprintln!(
                "source-pack prepare chunk stored metadata at {}; target={:?} complete={} libraries={} new_libraries={} source_files={} source_bytes={} source_lines={}",
                artifact_root.display(),
                metadata.target,
                metadata.complete,
                metadata.library_count,
                metadata.new_library_count,
                metadata.source_file_count,
                metadata.source_byte_count,
                metadata.source_line_count
            );
            return Ok(());
        }
        return Err(
            "--source-pack-prepare-only with raw --stdlib or positional source paths would prepare a whole path list; use --source-pack-library-manifest for bounded JSONL metadata chunks"
                .into(),
        );
    }
    prepare_source_pack_build_from_metadata_chunk_only(emit, source_pack)
}

fn compile_source_pack_from_metadata_with_descriptor_queue(
    emit: &str,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-build-from-metadata requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
        emit,
        artifact_root,
        source_pack,
        worker_id,
    )
}

fn compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
    emit: &str,
    artifact_root: &PathBuf,
    source_pack: &SourcePackCliOptions,
    worker_id: String,
) -> Result<PathBuf, String> {
    require_source_pack_prepared_build_for_descriptor_compile(artifact_root, emit)?;
    compile_prepared_source_pack_descriptor_queue(emit, artifact_root, source_pack, worker_id)
}

fn require_source_pack_artifact_root<'a>(
    source_pack: &'a SourcePackCliOptions,
    message: &str,
) -> Result<&'a PathBuf, String> {
    source_pack
        .artifact_root
        .as_ref()
        .ok_or_else(|| message.to_string())
}

fn compile_source_pack_legacy_in_memory(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
) -> Result<Vec<u8>, String> {
    if emit == "wasm" {
        pollster::block_on(
            compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen(
                stdlib_paths,
                inputs,
            ),
        )
        .map_err(|err| err.to_string())
    } else {
        pollster::block_on(
            compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen(
                stdlib_paths,
                inputs,
            ),
        )
        .map_err(|err| err.to_string())
    }
}

fn compile_source_pack_with_descriptor_queue(
    emit: &str,
    _stdlib_paths: &[PathBuf],
    _inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "source-pack descriptor compile requires --source-pack-artifact-root; run --source-pack-prepare-only with --source-pack-artifact-root until preparation completes, then rerun compile",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_direct_compile(artifact_root, emit, source_pack)?;
    unreachable!("prepared metadata requirement should return or fail")
}

fn compile_source_pack_library_manifest_with_descriptor_queue(
    emit: &str,
    _library_manifest_path: &Path,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-library-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_manifest_compile(artifact_root, emit)?;
    compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
        emit,
        artifact_root,
        source_pack,
        worker_id,
    )
}

fn compile_source_pack_manifest_with_descriptor_queue(
    emit: &str,
    _manifest_path: &Path,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_manifest_compile(artifact_root, emit)?;
    compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(
        emit,
        artifact_root,
        source_pack,
        worker_id,
    )
}

fn compile_prepared_source_pack_descriptor_queue(
    emit: &str,
    artifact_root: &PathBuf,
    source_pack: &SourcePackCliOptions,
    worker_id: String,
) -> Result<PathBuf, String> {
    let max_items = source_pack_max_items(source_pack);
    let max_ready_items = source_pack_max_ready_items(source_pack);
    let run = if emit == "wasm" {
        pollster::block_on(
            execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors(
                artifact_root,
                worker_id,
                max_items,
                None,
                max_ready_items,
            ),
        )
        .map_err(|err| err.to_string())?
    } else {
        pollster::block_on(
            execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
                artifact_root,
                worker_id,
                max_items,
                None,
                max_ready_items,
            ),
        )
        .map_err(|err| err.to_string())?
    };
    complete_source_pack_output_path(artifact_root, run)
}

fn source_pack_artifact_root_has_prepared_build(artifact_root: &Path, emit: &str) -> bool {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    store
        .build_state_path_for_target(source_pack_artifact_target(emit))
        .is_file()
}

fn source_pack_artifact_root_has_prepared_metadata(artifact_root: &Path, emit: &str) -> bool {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    store
        .library_partition_index_path_for_target(source_pack_artifact_target(emit))
        .is_file()
}

fn source_pack_artifact_root_persisted_library_partition_prefix_count(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
) -> usize {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    if let Ok(index) = store.load_library_partition_index_for_target(target) {
        return index.partition_count;
    }
    if let Ok(progress) = store.load_library_metadata_prepare_progress_for_target(target) {
        return progress.library_partition_count;
    }
    let mut partition_count = 0usize;
    while store
        .library_partition_path_for_target(target, partition_count)
        .is_file()
    {
        partition_count = partition_count.saturating_add(1);
    }
    partition_count
}

fn require_source_pack_prepared_metadata_for_direct_compile(
    artifact_root: &Path,
    emit: &str,
    _source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit)
        || source_pack_artifact_root_has_prepared_metadata(artifact_root, emit)
    {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn require_source_pack_prepared_metadata_for_manifest_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit)
        || source_pack_artifact_root_has_prepared_metadata(artifact_root, emit)
    {
        return Ok(());
    }
    Err(format!(
        "source-pack manifest descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-library-manifest and --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn require_source_pack_prepared_build_for_descriptor_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has persisted metadata but no prepared build queue for target {emit}; run --source-pack-prepare-only or --source-pack-build-from-metadata --source-pack-build-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn source_pack_artifact_target(emit: &str) -> SourcePackArtifactTarget {
    if emit == "wasm" {
        SourcePackArtifactTarget::Wasm
    } else {
        SourcePackArtifactTarget::X86_64
    }
}

fn source_pack_library_manifest_read_progress_path(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
) -> PathBuf {
    let file_name = target.key_prefix().map_or_else(
        || "source-pack-library-manifest-progress.json".to_string(),
        |prefix| format!("source-pack-library-manifest-progress.{prefix}.json"),
    );
    artifact_root.join(file_name)
}

fn source_pack_library_manifest_identity_path(manifest_path: &Path) -> Result<PathBuf, String> {
    fs::canonicalize(manifest_path).map_err(|err| {
        format!(
            "canonicalize source-pack library manifest {}: {err}",
            manifest_path.display()
        )
    })
}

fn load_source_pack_library_manifest_read_progress_or_default(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
    manifest_path: &Path,
    persisted_library_count: usize,
) -> Result<SourcePackLibraryManifestReadProgress, String> {
    let manifest_path = source_pack_library_manifest_identity_path(manifest_path)?;
    let progress_path = source_pack_library_manifest_read_progress_path(artifact_root, target);
    if progress_path.is_file() {
        let bytes = fs::read(&progress_path).map_err(|err| {
            format!(
                "read source-pack library manifest progress {}: {err}",
                progress_path.display()
            )
        })?;
        let progress = serde_json::from_slice::<SourcePackLibraryManifestReadProgress>(&bytes)
            .map_err(|err| {
                format!(
                    "parse source-pack library manifest progress {}: {err}",
                    progress_path.display()
                )
            })?;
        validate_source_pack_library_manifest_read_progress(&progress, target, &manifest_path)?;
        return Ok(progress);
    }

    let next_byte_offset = source_pack_library_manifest_offset_after_entry_count(
        &manifest_path,
        persisted_library_count,
    )?;
    Ok(SourcePackLibraryManifestReadProgress {
        version: SOURCE_PACK_LIBRARY_MANIFEST_READ_PROGRESS_VERSION,
        target,
        manifest_path,
        library_count: persisted_library_count,
        next_byte_offset,
    })
}

fn validate_source_pack_library_manifest_read_progress(
    progress: &SourcePackLibraryManifestReadProgress,
    target: SourcePackArtifactTarget,
    manifest_path: &Path,
) -> Result<(), String> {
    if progress.version != SOURCE_PACK_LIBRARY_MANIFEST_READ_PROGRESS_VERSION {
        return Err(format!(
            "unsupported source-pack library manifest progress version {}; expected {}",
            progress.version, SOURCE_PACK_LIBRARY_MANIFEST_READ_PROGRESS_VERSION
        ));
    }
    if progress.target != target {
        return Err(format!(
            "source-pack library manifest progress target {:?} does not match requested target {:?}",
            progress.target, target
        ));
    }
    if progress.manifest_path != manifest_path {
        return Err(format!(
            "source-pack library manifest progress was created for {}, not {}",
            progress.manifest_path.display(),
            manifest_path.display()
        ));
    }
    Ok(())
}

fn store_source_pack_library_manifest_read_progress(
    artifact_root: &Path,
    progress: &SourcePackLibraryManifestReadProgress,
) -> Result<(), String> {
    validate_source_pack_library_manifest_read_progress(
        progress,
        progress.target,
        &progress.manifest_path,
    )?;
    let path = source_pack_library_manifest_read_progress_path(artifact_root, progress.target);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            format!(
                "create source-pack library manifest progress directory {}: {err}",
                parent.display()
            )
        })?;
    }
    let bytes = serde_json::to_vec_pretty(progress)
        .map_err(|err| format!("serialize source-pack library manifest progress: {err}"))?;
    fs::write(&path, bytes).map_err(|err| {
        format!(
            "write source-pack library manifest progress {}: {err}",
            path.display()
        )
    })
}

fn source_pack_library_manifest_offset_after_entry_count(
    manifest_path: &Path,
    expected_entry_count: usize,
) -> Result<u64, String> {
    if expected_entry_count == 0 {
        return Ok(0);
    }
    let file = fs::File::open(manifest_path).map_err(|err| {
        format!(
            "open source-pack library manifest {}: {err}",
            manifest_path.display()
        )
    })?;
    let mut reader = BufReader::new(file);
    let mut byte_offset = 0u64;
    let mut entry_count = 0usize;
    let mut blank_line_count = 0usize;
    let mut line = String::new();
    loop {
        let bytes_read = read_source_pack_library_manifest_line(
            &mut reader,
            &mut line,
            manifest_path,
            byte_offset,
        )?;
        if bytes_read == 0 {
            return Err(format!(
                "source-pack library manifest {} has only {entry_count} libraries, but persisted metadata records {expected_entry_count}",
                manifest_path.display()
            ));
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| "source-pack library manifest byte offset overflows".to_string())?;
        if line.trim().is_empty() {
            blank_line_count += 1;
            if blank_line_count > SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(format!(
                    "source-pack library manifest {} has more than {SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines before entry {} at byte offset {byte_offset}; remove blank padding",
                    manifest_path.display(),
                    entry_count + 1
                ));
            }
            continue;
        }
        blank_line_count = 0;
        entry_count = entry_count
            .checked_add(1)
            .ok_or_else(|| "source-pack library manifest entry count overflows".to_string())?;
        if entry_count == expected_entry_count {
            return Ok(byte_offset);
        }
    }
}

struct SourcePackLibraryManifestEntryChunk {
    entries: Vec<SourcePackLibraryPathManifestEntry>,
    next_byte_offset: u64,
    manifest_complete_after_input: bool,
}

fn read_bounded_utf8_line(
    reader: &mut impl BufRead,
    line: &mut String,
    max_line_bytes: usize,
    context: impl Fn() -> String,
    advice: &str,
) -> Result<usize, String> {
    line.clear();
    let mut line_bytes = Vec::new();
    loop {
        let available = reader
            .fill_buf()
            .map_err(|err| format!("read {}: {err}", context()))?;
        if available.is_empty() {
            break;
        }
        let newline_position = available.iter().position(|&byte| byte == b'\n');
        let take_len = newline_position
            .map(|position| position + 1)
            .unwrap_or(available.len());
        let next_len = line_bytes
            .len()
            .checked_add(take_len)
            .ok_or_else(|| format!("{} line byte count overflows", context()))?;
        if next_len > max_line_bytes {
            return Err(format!(
                "{} exceeds line byte limit {max_line_bytes}; {advice}",
                context()
            ));
        }
        line_bytes.extend_from_slice(&available[..take_len]);
        reader.consume(take_len);
        if newline_position.is_some() {
            break;
        }
    }
    if line_bytes.is_empty() {
        return Ok(0);
    }
    let text = std::str::from_utf8(&line_bytes)
        .map_err(|err| format!("read {}: invalid UTF-8: {err}", context()))?;
    line.push_str(text);
    Ok(line_bytes.len())
}

fn read_source_pack_library_manifest_line(
    reader: &mut impl BufRead,
    line: &mut String,
    manifest_path: &Path,
    byte_offset: u64,
) -> Result<usize, String> {
    read_bounded_utf8_line(
        reader,
        line,
        SOURCE_PACK_LIBRARY_MANIFEST_MAX_LINE_BYTES,
        || {
            format!(
                "source-pack library manifest {} line at byte offset {byte_offset}",
                manifest_path.display()
            )
        },
        "split large library records",
    )
}

fn load_source_pack_library_manifest_entries_chunk_from_offset(
    manifest_path: &Path,
    start_byte_offset: u64,
    max_entries: usize,
    max_source_files: usize,
) -> Result<SourcePackLibraryManifestEntryChunk, String> {
    let manifest_base_dir = manifest_path
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    let mut file = fs::File::open(manifest_path).map_err(|err| {
        format!(
            "open source-pack library manifest {}: {err}",
            manifest_path.display()
        )
    })?;
    file.seek(SeekFrom::Start(start_byte_offset))
        .map_err(|err| {
            format!(
                "seek source-pack library manifest {} to byte offset {start_byte_offset}: {err}",
                manifest_path.display()
            )
        })?;
    let mut reader = BufReader::new(file);
    let mut entries = Vec::new();
    if max_entries == 0 || max_source_files == 0 {
        return Ok(SourcePackLibraryManifestEntryChunk {
            entries,
            next_byte_offset: start_byte_offset,
            manifest_complete_after_input: false,
        });
    }

    let mut byte_offset = start_byte_offset;
    let mut next_byte_offset = start_byte_offset;
    let mut new_source_file_count = 0usize;
    let mut blank_line_count = 0usize;
    let mut line = String::new();
    while entries.len() < max_entries {
        let line_start = byte_offset;
        let bytes_read = read_source_pack_library_manifest_line(
            &mut reader,
            &mut line,
            manifest_path,
            line_start,
        )?;
        if bytes_read == 0 {
            if entries.is_empty() {
                return Err(format!(
                    "source-pack library manifest {} has no libraries at byte offset {start_byte_offset}",
                    manifest_path.display()
                ));
            }
            return Ok(SourcePackLibraryManifestEntryChunk {
                entries,
                next_byte_offset,
                manifest_complete_after_input: true,
            });
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| "source-pack library manifest byte offset overflows".to_string())?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            blank_line_count += 1;
            if blank_line_count > SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(format!(
                    "source-pack library manifest {} has more than {SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines in one metadata chunk before byte offset {byte_offset}; remove blank padding",
                    manifest_path.display()
                ));
            }
            next_byte_offset = byte_offset;
            continue;
        }
        blank_line_count = 0;
        let mut entry = serde_json::from_str::<SourcePackLibraryPathManifestEntry>(trimmed)
            .map_err(|err| {
                format!(
                    "parse source-pack library manifest {} at byte offset {line_start}: {err}",
                    manifest_path.display()
                )
            })?;
        let next_source_file_count = new_source_file_count
            .checked_add(entry.source_file_count)
            .ok_or_else(|| {
                "source-pack library manifest chunk source-file count overflows".to_string()
            })?;
        if next_source_file_count > max_source_files {
            if entries.is_empty() {
                return Err(format!(
                    "source-pack library manifest library {} has {} source files, exceeding the per-chunk source-file limit {}; split the library path list into smaller library records",
                    entry.library_id, entry.source_file_count, max_source_files
                ));
            }
            return Ok(SourcePackLibraryManifestEntryChunk {
                entries,
                next_byte_offset: line_start,
                manifest_complete_after_input: false,
            });
        }
        entry.path_list = resolve_manifest_relative_path(&manifest_base_dir, &entry.path_list);
        new_source_file_count = next_source_file_count;
        entries.push(entry);
        next_byte_offset = byte_offset;
    }

    let mut manifest_complete_after_input = true;
    let mut trailing_blank_line_count = 0usize;
    loop {
        let line_start = byte_offset;
        let bytes_read = read_source_pack_library_manifest_line(
            &mut reader,
            &mut line,
            manifest_path,
            line_start,
        )?;
        if bytes_read == 0 {
            break;
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| "source-pack library manifest byte offset overflows".to_string())?;
        if line.trim().is_empty() {
            trailing_blank_line_count += 1;
            if trailing_blank_line_count > SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(format!(
                    "source-pack library manifest {} has more than {SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines after a metadata chunk before byte offset {byte_offset}; remove blank padding",
                    manifest_path.display()
                ));
            }
        } else {
            manifest_complete_after_input = false;
            break;
        }
    }

    Ok(SourcePackLibraryManifestEntryChunk {
        entries,
        next_byte_offset,
        manifest_complete_after_input,
    })
}

fn source_pack_library_manifest_prefix_path_dependency_streams(
    entries: Vec<SourcePackLibraryPathManifestEntry>,
) -> Result<Vec<ExplicitSourceLibraryPathDependencyStream<SourcePackPathListFile, Vec<u32>>>, String>
{
    let mut streams = Vec::with_capacity(entries.len());
    for mut entry in entries {
        if entry.source_file_count == 0 {
            return Err(format!(
                "source-pack library manifest library {} has no source files",
                entry.library_id
            ));
        }
        entry.dependency_library_ids.sort_unstable();
        entry.dependency_library_ids.dedup();
        if entry.dependency_library_ids.contains(&entry.library_id) {
            return Err(format!(
                "source-pack library manifest library {} depends on itself",
                entry.library_id
            ));
        }
        streams.push(ExplicitSourceLibraryPathDependencyStream {
            library_id: entry.library_id,
            source_file_count: entry.source_file_count,
            paths: SourcePackPathListFile::deferred(entry.path_list),
            dependency_library_count: entry.dependency_library_ids.len(),
            dependency_library_ids: entry.dependency_library_ids,
        });
    }
    Ok(streams)
}

fn resolve_manifest_relative_path(base_dir: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base_dir.join(path)
    }
}

#[cfg(test)]
fn source_pack_manifest_ordered_path_dependency_streams(
    manifest: ExplicitSourcePackPathManifest,
) -> Result<Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>>, String> {
    if manifest.files.is_empty() {
        return Err("source-pack manifest has no source files".into());
    }
    let mut paths_by_library = BTreeMap::<u32, Vec<PathBuf>>::new();
    for file in manifest.files {
        paths_by_library
            .entry(file.library_id)
            .or_default()
            .push(file.path);
    }

    let mut dependencies_by_library = BTreeMap::<u32, BTreeSet<u32>>::new();
    for dependency in manifest.library_dependencies {
        if dependency.library_id == dependency.depends_on_library_id {
            return Err(format!(
                "source-pack manifest library {} depends on itself",
                dependency.library_id
            ));
        }
        if !paths_by_library.contains_key(&dependency.library_id) {
            return Err(format!(
                "source-pack manifest dependency references missing library {}",
                dependency.library_id
            ));
        }
        if !paths_by_library.contains_key(&dependency.depends_on_library_id) {
            return Err(format!(
                "source-pack manifest dependency references missing library {}",
                dependency.depends_on_library_id
            ));
        }
        dependencies_by_library
            .entry(dependency.library_id)
            .or_default()
            .insert(dependency.depends_on_library_id);
    }

    let mut visiting = BTreeSet::<u32>::new();
    let mut visited = BTreeSet::<u32>::new();
    let mut ordered_library_ids = Vec::with_capacity(paths_by_library.len());
    for library_id in paths_by_library.keys().copied().collect::<Vec<_>>() {
        visit_source_pack_manifest_library(
            library_id,
            &paths_by_library,
            &dependencies_by_library,
            &mut visiting,
            &mut visited,
            &mut ordered_library_ids,
        )?;
    }

    let mut streams = Vec::with_capacity(ordered_library_ids.len());
    for library_id in ordered_library_ids {
        let paths = paths_by_library
            .remove(&library_id)
            .expect("ordered source-pack manifest library must have path records");
        let dependency_library_ids = dependencies_by_library
            .get(&library_id)
            .map(|dependencies| dependencies.iter().copied().collect::<Vec<_>>())
            .unwrap_or_default();
        streams.push(ExplicitSourceLibraryPathDependencyStream {
            library_id,
            source_file_count: paths.len(),
            paths,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        });
    }
    Ok(streams)
}

#[cfg(test)]
fn visit_source_pack_manifest_library(
    library_id: u32,
    paths_by_library: &BTreeMap<u32, Vec<PathBuf>>,
    dependencies_by_library: &BTreeMap<u32, BTreeSet<u32>>,
    visiting: &mut BTreeSet<u32>,
    visited: &mut BTreeSet<u32>,
    ordered_library_ids: &mut Vec<u32>,
) -> Result<(), String> {
    if visited.contains(&library_id) {
        return Ok(());
    }
    if !paths_by_library.contains_key(&library_id) {
        return Err(format!(
            "source-pack manifest dependency references missing library {library_id}"
        ));
    }
    if !visiting.insert(library_id) {
        return Err(format!(
            "source-pack manifest library dependency cycle includes library {library_id}"
        ));
    }
    if let Some(dependencies) = dependencies_by_library.get(&library_id) {
        for dependency_library_id in dependencies {
            visit_source_pack_manifest_library(
                *dependency_library_id,
                paths_by_library,
                dependencies_by_library,
                visiting,
                visited,
                ordered_library_ids,
            )?;
        }
    }
    visiting.remove(&library_id);
    visited.insert(library_id);
    ordered_library_ids.push(library_id);
    Ok(())
}

fn complete_source_pack_output_path(
    artifact_root: &PathBuf,
    run: SourcePackFilesystemWorkQueueWorkerRunExecutionResult,
) -> Result<PathBuf, String> {
    if !run.progress.complete {
        return Err(format!(
            "source-pack descriptor build stopped before completion at {}; executed_items={} completed_items={} work_items={} ready_items={}; rerun with --source-pack-artifact-root {} to continue the bounded work queue, or pass --source-pack-legacy-in-memory for the old whole-pack path",
            artifact_root.display(),
            run.executed_item_count,
            run.progress.completed_item_count,
            run.progress.work_item_count,
            run.progress.ready_item_count,
            artifact_root.display(),
        ));
    }
    let linked_output_path = run.linked_output_path.ok_or_else(|| {
        "completed source-pack descriptor build did not report a linked output path".to_string()
    })?;
    if !linked_output_path.is_file() {
        return Err(format!(
            "completed source-pack linked output is missing at {}",
            linked_output_path.display()
        ));
    }
    Ok(linked_output_path)
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

#[cfg(test)]
mod tests {
    use laniusc::{
        codegen::unit::SourcePackLibraryDependency,
        compiler::{ExplicitSourcePackPathManifest, ExplicitSourcePathFile},
    };

    use super::*;

    fn manifest_file(library_id: u32, path: &str) -> ExplicitSourcePathFile {
        ExplicitSourcePathFile {
            library_id,
            path: PathBuf::from(path),
            byte_len: 1,
            modified_unix_nanos: None,
            line_count: None,
        }
    }

    #[test]
    fn source_pack_manifest_orders_dependencies_before_users() {
        let streams =
            source_pack_manifest_ordered_path_dependency_streams(ExplicitSourcePackPathManifest {
                files: vec![
                    manifest_file(2, "app.lani"),
                    manifest_file(1, "core.lani"),
                    manifest_file(3, "cli.lani"),
                ],
                library_dependencies: vec![
                    SourcePackLibraryDependency {
                        library_id: 2,
                        depends_on_library_id: 1,
                    },
                    SourcePackLibraryDependency {
                        library_id: 3,
                        depends_on_library_id: 2,
                    },
                ],
            })
            .expect("manifest dependency streams should be ordered");

        let library_ids = streams
            .iter()
            .map(|stream| stream.library_id)
            .collect::<Vec<_>>();
        assert_eq!(library_ids, vec![1, 2, 3]);
        assert_eq!(streams[1].dependency_library_ids, vec![1]);
        assert_eq!(streams[2].dependency_library_ids, vec![2]);
    }

    #[test]
    fn source_pack_manifest_rejects_dependency_cycles() {
        let err =
            source_pack_manifest_ordered_path_dependency_streams(ExplicitSourcePackPathManifest {
                files: vec![manifest_file(1, "a.lani"), manifest_file(2, "b.lani")],
                library_dependencies: vec![
                    SourcePackLibraryDependency {
                        library_id: 1,
                        depends_on_library_id: 2,
                    },
                    SourcePackLibraryDependency {
                        library_id: 2,
                        depends_on_library_id: 1,
                    },
                ],
            })
            .expect_err("manifest dependency cycles must be rejected");
        assert!(err.contains("dependency cycle"));
    }

    #[test]
    fn cli_file_emission_copies_linked_output_without_byte_vec() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-file-emission-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create file emission root");
        let linked_output = root.join("linked-output.bin");
        let output = root.join("out.bin");
        fs::write(&linked_output, b"linked bytes").expect("write linked output");

        write_cli_emission(
            CliEmission::File(linked_output.clone()),
            Some(output.clone()),
            "wasm",
        )
        .expect("copy file emission");

        assert_eq!(
            fs::read(&output).expect("read copied output"),
            b"linked bytes"
        );
        assert!(linked_output.is_file());

        fs::remove_dir_all(&root).expect("remove temp file emission root");
    }

    #[test]
    fn source_pack_metadata_only_stores_persisted_library_records() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-metadata-only-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
        fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write core path list");
        fs::write(
            root.join("app.paths"),
            format!("{}\n", source_root.join("app.lani").display()),
        )
        .expect("write app path list");
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.metadata_only = true;
        source_pack.artifact_root = Some(artifact_root.clone());
        prepare_source_pack_metadata_only("wasm", &[], &[], &source_pack)
            .expect("prepare metadata only");

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file()
        );
        assert!(
            !store
                .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "metadata-only phase must not prepare the work queue build state"
        );

        let library_manifest_path = source_pack
            .library_manifest
            .as_ref()
            .expect("test source pack should keep a library manifest path")
            .clone();
        fs::remove_file(&library_manifest_path).expect("remove library manifest after metadata");
        fs::remove_dir_all(&source_root).expect("remove source files after metadata");
        prepare_source_pack_metadata_only("wasm", &[], &[], &source_pack)
            .expect("metadata-only rerun should reuse the completed persisted metadata marker");

        fs::remove_dir_all(&root).expect("remove temp metadata-only root");
    }

    #[test]
    fn source_pack_metadata_only_library_manifest_defaults_to_bounded_chunk() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-metadata-only-default-chunk-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");

        let mut manifest = String::new();
        for index in 0..DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES {
            let library_id = (index + 1) as u32;
            let source_file_name = format!("lib_{library_id}.lani");
            let source_path = source_root.join(&source_file_name);
            fs::write(
                &source_path,
                format!("let lib_{library_id} = {library_id};\n"),
            )
            .expect("write source");
            let path_list_name = format!("lib_{library_id}.paths");
            fs::write(
                root.join(&path_list_name),
                format!("{}\n", source_path.display()),
            )
            .expect("write path list");
            manifest.push_str(&format!(
                "{{\"library_id\":{library_id},\"source_file_count\":1,\"path_list\":\"{path_list_name}\"}}\n"
            ));
        }
        manifest.push_str(&format!(
            "{{\"library_id\":{},\"source_file_count\":1,\"path_list\":\"missing-later.paths\"}}\n",
            DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES + 1
        ));
        let manifest_path = root.join("libraries.jsonl");
        fs::write(&manifest_path, manifest).expect("write library manifest");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.metadata_only = true;
        source_pack.artifact_root = Some(artifact_root.clone());

        prepare_source_pack_metadata_only("wasm", &[], &[], &source_pack)
            .expect("metadata-only should stop after the default bounded chunk");

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_path_for_target(
                    SourcePackArtifactTarget::Wasm,
                    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES - 1
                )
                .is_file()
        );
        assert!(
            !store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "metadata-only must leave a later library manifest entry for a future chunk"
        );
        let progress_path = source_pack_library_manifest_read_progress_path(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
        );
        let progress = serde_json::from_slice::<SourcePackLibraryManifestReadProgress>(
            &fs::read(&progress_path).expect("read manifest progress"),
        )
        .expect("parse manifest progress");
        assert_eq!(
            progress.library_count,
            DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES
        );

        fs::remove_dir_all(&root).expect("remove temp metadata-only default chunk root");
    }

    #[test]
    fn source_pack_library_manifest_reader_rejects_overlong_records() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-library-manifest-line-cap-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create line cap root");
        let manifest_path = root.join("libraries.jsonl");
        let overlong_path = "x".repeat(SOURCE_PACK_LIBRARY_MANIFEST_MAX_LINE_BYTES);
        fs::write(
            &manifest_path,
            format!(
                "{{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"{overlong_path}\"}}\n"
            ),
        )
        .expect("write overlong library manifest record");

        let chunk_err = match load_source_pack_library_manifest_entries_chunk_from_offset(
            &manifest_path,
            0,
            1,
            1,
        ) {
            Ok(_) => panic!("chunked manifest reader should reject an overlong record"),
            Err(err) => err,
        };
        assert!(
            chunk_err.contains("exceeds line byte limit"),
            "unexpected overlong chunk error: {chunk_err}"
        );

        let progress_err = source_pack_library_manifest_offset_after_entry_count(&manifest_path, 1)
            .expect_err("progress replay should reject an overlong record");
        assert!(
            progress_err.contains("exceeds line byte limit"),
            "unexpected overlong progress error: {progress_err}"
        );

        fs::remove_dir_all(&root).expect("remove line cap root");
    }

    #[test]
    fn source_pack_path_list_reader_rejects_overlong_records() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-path-list-line-cap-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create path-list line cap root");
        let path_list = root.join("library.paths");
        let overlong_path = "x".repeat(SOURCE_PACK_PATH_LIST_MAX_LINE_BYTES);
        fs::write(&path_list, format!("{overlong_path}\n")).expect("write overlong path list");

        let mut paths = SourcePackPathListFile::deferred(path_list).into_iter();
        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = paths.next();
        }))
        .expect_err("path-list iterator should reject an overlong path record");
        let message = panic
            .downcast_ref::<String>()
            .map(String::as_str)
            .or_else(|| panic.downcast_ref::<&str>().copied())
            .unwrap_or("<non-string panic>");
        assert!(
            message.contains("exceeds line byte limit"),
            "unexpected overlong path-list error: {message}"
        );

        fs::remove_dir_all(&root).expect("remove path-list line cap root");
    }

    #[test]
    fn source_pack_stream_readers_reject_unbounded_blank_records() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-stream-blank-cap-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create blank cap root");

        let blank_manifest_prefix =
            "\n".repeat(SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK + 1);
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            format!(
                "{blank_manifest_prefix}{{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"library.paths\"}}\n"
            ),
        )
        .expect("write blank-heavy library manifest");

        let chunk_err = match load_source_pack_library_manifest_entries_chunk_from_offset(
            &manifest_path,
            0,
            1,
            1,
        ) {
            Ok(_) => panic!("manifest chunk reader should reject too many blank records"),
            Err(err) => err,
        };
        assert!(
            chunk_err.contains("blank lines"),
            "unexpected manifest blank chunk error: {chunk_err}"
        );

        let progress_err = source_pack_library_manifest_offset_after_entry_count(&manifest_path, 1)
            .expect_err("manifest progress replay should reject too many blank records");
        assert!(
            progress_err.contains("blank lines"),
            "unexpected manifest blank progress error: {progress_err}"
        );

        let path_list = root.join("library.paths");
        fs::write(
            &path_list,
            format!(
                "{}{}\n",
                "\n".repeat(SOURCE_PACK_PATH_LIST_MAX_BLANK_LINES_PER_ITEM + 1),
                root.join("source.lani").display()
            ),
        )
        .expect("write blank-heavy path list");
        let mut paths = SourcePackPathListFile::deferred(path_list).into_iter();
        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = paths.next();
        }))
        .expect_err("path-list iterator should reject too many blank records");
        let message = panic
            .downcast_ref::<String>()
            .map(String::as_str)
            .or_else(|| panic.downcast_ref::<&str>().copied())
            .unwrap_or("<non-string panic>");
        assert!(
            message.contains("blank lines"),
            "unexpected path-list blank error: {message}"
        );

        fs::remove_dir_all(&root).expect("remove blank cap root");
    }

    #[test]
    fn source_pack_metadata_chunk_limits_cap_unbounded_cli_values() {
        let mut source_pack = SourcePackCliOptions::default();
        assert_eq!(
            source_pack_metadata_max_libraries(&source_pack),
            DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES
        );
        assert_eq!(
            source_pack_metadata_max_source_files(&source_pack),
            DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES
        );

        source_pack.metadata_max_libraries = Some(3);
        source_pack.metadata_max_source_files = Some(5);
        assert_eq!(source_pack_metadata_max_libraries(&source_pack), 3);
        assert_eq!(source_pack_metadata_max_source_files(&source_pack), 5);

        source_pack.metadata_max_libraries = Some(usize::MAX);
        source_pack.metadata_max_source_files = Some(usize::MAX);
        assert_eq!(
            source_pack_metadata_max_libraries(&source_pack),
            DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES
        );
        assert_eq!(
            source_pack_metadata_max_source_files(&source_pack),
            DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES
        );
    }

    #[test]
    fn source_pack_descriptor_item_limits_cap_unbounded_cli_values() {
        let mut source_pack = SourcePackCliOptions::default();
        assert_eq!(
            source_pack_build_max_items(&source_pack),
            DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS
        );
        assert_eq!(
            source_pack_max_items(&source_pack),
            DEFAULT_SOURCE_PACK_MAX_ITEMS
        );
        assert_eq!(
            source_pack_max_ready_items(&source_pack),
            DEFAULT_SOURCE_PACK_MAX_READY_ITEMS
        );

        source_pack.build_max_items = 3;
        source_pack.max_items = 5;
        source_pack.max_ready_items = 7;
        assert_eq!(source_pack_build_max_items(&source_pack), 3);
        assert_eq!(source_pack_max_items(&source_pack), 5);
        assert_eq!(source_pack_max_ready_items(&source_pack), 7);

        source_pack.build_max_items = usize::MAX;
        source_pack.max_items = usize::MAX;
        source_pack.max_ready_items = usize::MAX;
        assert_eq!(
            source_pack_build_max_items(&source_pack),
            DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS
        );
        assert_eq!(
            source_pack_max_items(&source_pack),
            DEFAULT_SOURCE_PACK_MAX_ITEMS
        );
        assert_eq!(
            source_pack_max_ready_items(&source_pack),
            DEFAULT_SOURCE_PACK_MAX_READY_ITEMS
        );
    }

    #[test]
    fn source_pack_build_prepare_only_runs_one_bounded_metadata_chunk() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-build-prepare-only-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
        fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write core path list");
        fs::write(
            root.join("app.paths"),
            format!("{}\n", source_root.join("app.lani").display()),
        )
        .expect("write app path list");
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

        let mut metadata_pack = SourcePackCliOptions::default();
        metadata_pack.library_manifest = Some(manifest_path);
        metadata_pack.metadata_only = true;
        metadata_pack.artifact_root = Some(artifact_root.clone());
        prepare_source_pack_metadata_only("wasm", &[], &[], &metadata_pack)
            .expect("prepare metadata only before build chunk");
        fs::remove_dir_all(&source_root).expect("remove source files after metadata");

        let mut build_pack = SourcePackCliOptions::default();
        build_pack.build_from_metadata = true;
        build_pack.build_prepare_only = true;
        build_pack.build_max_items = 1;
        build_pack.artifact_root = Some(artifact_root.clone());
        prepare_source_pack_build_from_metadata_chunk_only("wasm", &build_pack)
            .expect("prepare one bounded build chunk from metadata");

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file()
        );
        assert!(
            !store
                .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
                .is_file(),
            "prepare-only chunk must not loop through every metadata-derived library"
        );
        assert!(
            !store
                .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "prepare-only chunk must not submit work or mark the build prepared"
        );

        fs::remove_dir_all(&root).expect("remove temp build-prepare-only root");
    }

    #[test]
    fn source_pack_prepare_only_advances_metadata_then_build_chunks_without_submission() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-prepare-only-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write core source");
        fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write app source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write core path list");
        fs::write(
            root.join("app.paths"),
            format!("{}\n", source_root.join("app.lani").display()),
        )
        .expect("write app path list");
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(1);
        source_pack.build_max_items = 1;
        source_pack.artifact_root = Some(artifact_root.clone());

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("prepare first source-pack metadata chunk");
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file()
        );
        let progress = store
            .load_library_metadata_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
            .expect("first metadata chunk should persist resumable progress");
        assert_eq!(progress.library_partition_count, 1);
        assert_eq!(progress.source_file_count, 1);
        assert!(
            !store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "first prepare-only chunk must stop before finalizing all metadata"
        );
        assert!(
            !store
                .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "metadata chunks must not submit descriptor work"
        );

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("prepare final source-pack metadata chunk");
        assert!(
            store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file()
        );
        fs::remove_dir_all(&source_root).expect("remove source files after metadata");

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("prepare one build chunk from source-pack metadata");
        assert!(
            store
                .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file()
        );
        assert!(
            !store
                .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "source-pack prepare-only mode must not submit descriptor work or complete the full build in one bounded chunk"
        );

        fs::remove_dir_all(&root).expect("remove temp prepare-only root");
    }

    #[test]
    fn source_pack_prepare_only_library_manifest_chunk_does_not_open_later_path_lists() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-library-manifest-prefix-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write first path list");
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"missing.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest with missing later path list");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(1);
        source_pack.artifact_root = Some(artifact_root.clone());

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("first metadata chunk should not open a later library path list");
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file()
        );
        assert!(
            !store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "a later manifest entry must keep the metadata chunk incomplete"
        );

        fs::remove_dir_all(&root).expect("remove temp library manifest prefix root");
    }

    #[test]
    fn source_pack_prepare_only_library_manifest_chunk_stops_at_source_file_limit() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-library-manifest-source-limit-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write first path list");
        let first_line =
            "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n";
        let second_line = "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"missing.paths\",\"dependency_library_ids\":[1]}\n";
        let manifest_path = root.join("libraries.jsonl");
        fs::write(&manifest_path, format!("{first_line}{second_line}"))
            .expect("write library manifest with missing later path list");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(64);
        source_pack.metadata_max_source_files = Some(1);
        source_pack.artifact_root = Some(artifact_root.clone());

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("first metadata chunk should stop before the source-file limit overflow");
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file()
        );
        assert!(
            !store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "a later source-file-limited manifest entry must keep metadata incomplete"
        );
        let progress_path = source_pack_library_manifest_read_progress_path(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
        );
        let progress = serde_json::from_slice::<SourcePackLibraryManifestReadProgress>(
            &fs::read(&progress_path).expect("read manifest progress"),
        )
        .expect("parse manifest progress");
        assert_eq!(progress.library_count, 1);
        assert_eq!(progress.next_byte_offset, first_line.len() as u64);

        fs::remove_dir_all(&root).expect("remove temp library manifest source-limit root");
    }

    #[test]
    fn source_pack_prepare_only_rejects_single_library_over_source_file_limit_before_path_list_open()
     {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-library-manifest-oversized-library-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&root).expect("create root dir");
        let manifest_path = root.join("libraries.jsonl");
        fs::write(
            &manifest_path,
            "{\"library_id\":1,\"source_file_count\":2,\"path_list\":\"missing.paths\"}\n",
        )
        .expect("write oversized library manifest");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path);
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(64);
        source_pack.metadata_max_source_files = Some(1);
        source_pack.artifact_root = Some(artifact_root);

        let err = prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect_err("oversized single-library chunk should fail before opening path list");
        assert!(err.contains("per-chunk source-file limit"));
        assert!(
            !err.contains("missing.paths"),
            "single-library source-file limit rejection should happen before opening path list"
        );

        fs::remove_dir_all(&root).expect("remove temp oversized library root");
    }

    #[test]
    fn source_pack_prepare_only_library_manifest_chunk_resumes_from_byte_offset() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-library-manifest-offset-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        fs::create_dir_all(&source_root).expect("create source dir");
        fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write core source");
        fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write app source");
        fs::write(
            root.join("core.paths"),
            format!("{}\n", source_root.join("core.lani").display()),
        )
        .expect("write core path list");
        fs::write(
            root.join("app.paths"),
            format!("{}\n", source_root.join("app.lani").display()),
        )
        .expect("write app path list");
        let manifest_path = root.join("libraries.jsonl");
        let first_line =
            "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n";
        let second_line = "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n";
        fs::write(&manifest_path, format!("{first_line}{second_line}"))
            .expect("write library manifest");

        let mut source_pack = SourcePackCliOptions::default();
        source_pack.library_manifest = Some(manifest_path.clone());
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(1);
        source_pack.artifact_root = Some(artifact_root.clone());

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("prepare first metadata chunk");
        let progress_path = source_pack_library_manifest_read_progress_path(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
        );
        let progress = serde_json::from_slice::<SourcePackLibraryManifestReadProgress>(
            &fs::read(&progress_path).expect("read manifest progress"),
        )
        .expect("parse manifest progress");
        assert_eq!(progress.library_count, 1);
        assert_eq!(progress.next_byte_offset, first_line.len() as u64);

        let invalid_first_line = format!("{}\n", "x".repeat(first_line.len() - 1));
        assert_eq!(invalid_first_line.len(), first_line.len());
        fs::write(&manifest_path, format!("{invalid_first_line}{second_line}"))
            .expect("rewrite earlier manifest prefix with invalid JSON");

        prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect("second metadata chunk should seek past the prior manifest entry");
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        assert!(
            store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            "second chunk should complete metadata without reparsing the corrupted prefix"
        );

        fs::remove_dir_all(&root).expect("remove temp library manifest offset root");
    }

    #[test]
    fn source_pack_prepare_only_rejects_json_manifest_chunks_before_manifest_read() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-json-manifest-chunk-reject-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let missing_manifest = root.join("missing-source-pack.json");
        let mut source_pack = SourcePackCliOptions::default();
        source_pack.manifest = Some(missing_manifest);
        source_pack.prepare_only = true;
        source_pack.metadata_max_libraries = Some(1);
        source_pack.artifact_root = Some(artifact_root);

        let err = prepare_source_pack_inputs_chunk_only("wasm", &[], &[], &source_pack)
            .expect_err("chunked JSON manifest metadata prep should be rejected as unbounded");
        assert!(err.contains("--source-pack-library-manifest"));
        assert!(
            !err.contains("read source-pack manifest"),
            "chunked JSON manifest rejection should happen before reading the manifest"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn source_pack_metadata_only_rejects_json_manifest_before_manifest_read() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-json-manifest-metadata-reject-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let missing_manifest = root.join("missing-source-pack.json");
        let mut source_pack = SourcePackCliOptions::default();
        source_pack.manifest = Some(missing_manifest);
        source_pack.metadata_only = true;
        source_pack.artifact_root = Some(artifact_root);

        let err = prepare_source_pack_metadata_only("wasm", &[], &[], &source_pack)
            .expect_err("metadata-only JSON manifest prep should be rejected as unbounded");
        assert!(err.contains("--source-pack-library-manifest"));
        assert!(
            !err.contains("read source-pack manifest"),
            "metadata-only JSON manifest rejection should happen before reading the manifest"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn source_pack_prepare_only_rejects_raw_paths_before_source_metadata_read() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-raw-path-prepare-reject-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let missing_source = root.join("missing.lani");
        let mut source_pack = SourcePackCliOptions::default();
        source_pack.prepare_only = true;
        source_pack.artifact_root = Some(artifact_root);

        let err = prepare_source_pack_inputs_chunk_only(
            "wasm",
            &[],
            std::slice::from_ref(&missing_source),
            &source_pack,
        )
        .expect_err("raw path prepare-only should be rejected as unbounded");
        assert!(err.contains("--source-pack-library-manifest"));
        assert!(
            !err.contains("missing.lani"),
            "raw path prepare-only rejection should happen before reading source metadata"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn source_pack_direct_descriptor_compile_requires_prepared_artifact_root_before_source_parse() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-direct-prepare-required-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let missing_manifest = root.join("missing-source-pack.json");
        let missing_library_manifest = root.join("missing-libraries.jsonl");
        let missing_source = root.join("missing.lani");
        let mut source_pack = SourcePackCliOptions::default();
        source_pack.artifact_root = Some(artifact_root);

        let manifest_err = compile_source_pack_manifest_with_descriptor_queue(
            "wasm",
            &missing_manifest,
            &source_pack,
        )
        .expect_err("fresh explicit artifact roots must be prepared before manifest parsing");
        assert!(manifest_err.contains("no persisted metadata"));
        assert!(manifest_err.contains("--source-pack-prepare-only"));
        assert!(
            !manifest_err.contains("read source-pack manifest"),
            "compile should fail before reading source-pack manifests"
        );

        let library_manifest_err = compile_source_pack_library_manifest_with_descriptor_queue(
            "wasm",
            &missing_library_manifest,
            &source_pack,
        )
        .expect_err(
            "fresh explicit artifact roots must be prepared before library manifest parsing",
        );
        assert!(library_manifest_err.contains("no persisted metadata"));
        assert!(
            !library_manifest_err.contains("open source-pack library manifest"),
            "compile should fail before reading source-pack library manifests"
        );

        let default_manifest_err = compile_source_pack_manifest_with_descriptor_queue(
            "wasm",
            &missing_manifest,
            &SourcePackCliOptions::default(),
        )
        .expect_err("manifest descriptor compile must name an artifact root before parsing");
        assert!(default_manifest_err.contains("--source-pack-artifact-root"));
        assert!(
            !default_manifest_err.contains("read source-pack manifest"),
            "manifest compile without an artifact root should fail before reading source-pack manifests"
        );

        let default_library_manifest_err =
            compile_source_pack_library_manifest_with_descriptor_queue(
                "wasm",
                &missing_library_manifest,
                &SourcePackCliOptions::default(),
            )
            .expect_err(
                "library manifest descriptor compile must name an artifact root before parsing",
            );
        assert!(default_library_manifest_err.contains("--source-pack-artifact-root"));
        assert!(
            !default_library_manifest_err.contains("open source-pack library manifest"),
            "library manifest compile without an artifact root should fail before reading source-pack library manifests"
        );

        let default_source_err = compile_source_pack_with_descriptor_queue(
            "wasm",
            &[],
            &[missing_source.clone()],
            &SourcePackCliOptions::default(),
        )
        .expect_err(
            "source-pack descriptor compile must name an artifact root before reading sources",
        );
        assert!(default_source_err.contains("--source-pack-artifact-root"));
        assert!(
            !default_source_err.contains("missing.lani"),
            "source-pack compile without an artifact root should fail before touching explicit source paths"
        );

        let source_err =
            compile_source_pack_with_descriptor_queue("wasm", &[], &[missing_source], &source_pack)
                .expect_err("fresh explicit artifact roots must be prepared before source parsing");
        assert!(source_err.contains("no persisted metadata"));
        assert!(
            !source_err.contains("missing.lani"),
            "compile should fail before touching explicit source paths"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn source_pack_descriptor_compile_requires_prepared_build_queue_after_metadata() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-build-queue-required-test-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        let metadata_index_path =
            store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm);
        fs::create_dir_all(
            metadata_index_path
                .parent()
                .expect("metadata index path should have a parent"),
        )
        .expect("create metadata index dir");
        fs::write(&metadata_index_path, b"{}").expect("write metadata index marker");
        let mut source_pack = SourcePackCliOptions::default();
        source_pack.artifact_root = Some(artifact_root.clone());

        let err = compile_source_pack_from_metadata_with_descriptor_queue("wasm", &source_pack)
            .expect_err("metadata alone must not trigger full build-queue preparation");
        assert!(err.contains("no prepared build queue"));
        assert!(err.contains("--source-pack-build-from-metadata --source-pack-build-prepare-only"));
        assert!(
            !store
                .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                .exists(),
            "descriptor compile must not synthesize build state in the compile path"
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn source_pack_resume_detection_is_target_specific() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let artifact_root = env::temp_dir().join(format!(
            "laniusc-cli-resume-detection-test-{}-{suffix}",
            std::process::id()
        ));
        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        let wasm_state_path = store.build_state_path_for_target(SourcePackArtifactTarget::Wasm);
        fs::create_dir_all(
            wasm_state_path
                .parent()
                .expect("target build state path should have a parent"),
        )
        .expect("create build state dir");
        fs::write(&wasm_state_path, b"{}").expect("write wasm build state marker");

        assert!(source_pack_artifact_root_has_prepared_build(
            &artifact_root,
            "wasm"
        ));
        assert!(!source_pack_artifact_root_has_prepared_build(
            &artifact_root,
            "x86_64"
        ));

        fs::remove_dir_all(&artifact_root).expect("remove temp artifact root");
    }
}
