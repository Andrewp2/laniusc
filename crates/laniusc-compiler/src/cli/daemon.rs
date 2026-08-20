#[cfg(unix)]
use std::os::unix::net::UnixListener;
use std::{
    collections::{BTreeSet, HashMap},
    ffi::OsString,
    fs,
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    sync::{
        Arc,
        mpsc::{self, RecvTimeoutError, Sender},
    },
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime},
};

use serde::Deserialize;
use serde_json::{Value, json};

use super::common::{
    CliError,
    missing_cli_option_value_error,
    unknown_cli_option_error,
    unsupported_cli_option_value_error,
};
use crate::{
    codegen::unit::SourcePackArtifactTarget,
    compiler::{
        ExplicitSourcePack,
        ExplicitSourcePackPathManifest,
        GpuCompiler,
        GpuCompilerBackends,
        load_entry_path_manifest_with_source_root_and_stdlib,
        load_entry_path_manifest_with_stdlib,
        load_explicit_source_pack_from_path_manifest,
    },
    gpu::{
        buffers::{buffer_creation_count, buffer_creation_counts_by_label},
        compiler_graph::compiler_graph_diagnostics,
        device,
        passes_core::{
            begin_compute_schedule_job,
            bind_group_creation_count,
            bind_group_creation_counts_by_label,
            bind_group_timing_counters,
            bind_group_timing_enabled,
            compute_pass_breakdown_enabled,
            finish_compute_schedule_job,
            pipeline_creation_count,
            recorded_compute_dispatch_count,
            recorded_compute_pass_count,
            recorded_compute_pass_counts_by_label,
        },
    },
};

const DAEMON_SCHEMA: &str = "lanius.compiler-daemon.v1";
const MAX_REQUEST_BYTES: usize = 1024 * 1024;
const DEFAULT_IDLE_BUFFER_TIMEOUT_MS: u64 = 30_000;

#[derive(Clone, Copy, Debug)]
enum BackendSelection {
    Both,
    Wasm,
    X86,
}

impl BackendSelection {
    fn compiler_backends(self) -> GpuCompilerBackends {
        match self {
            Self::Both => GpuCompilerBackends::all(),
            Self::Wasm => GpuCompilerBackends::wasm_only(),
            Self::X86 => GpuCompilerBackends::x86_only(),
        }
    }

    fn targets(self) -> &'static [&'static str] {
        match self {
            Self::Both => &["x86_64", "wasm"],
            Self::Wasm => &["wasm"],
            Self::X86 => &["x86_64"],
        }
    }

    fn supports(self, emit: &str) -> bool {
        match self {
            Self::Both => emit == "x86_64" || emit == "wasm",
            Self::Wasm => emit == "wasm",
            Self::X86 => emit == "x86_64",
        }
    }
}

#[derive(Debug)]
struct DaemonOptions {
    backend: BackendSelection,
    stdlib_root: Option<PathBuf>,
    transport: DaemonTransport,
    idle_buffer_timeout: Option<Duration>,
}

#[derive(Debug)]
enum DaemonTransport {
    Stdio,
    #[cfg(unix)]
    UnixSocket(PathBuf),
}

#[derive(Deserialize)]
struct DaemonRequest {
    #[serde(default)]
    id: Value,
    command: String,
    #[serde(default)]
    emit: Option<String>,
    #[serde(default)]
    input: Option<PathBuf>,
    #[serde(default)]
    output: Option<PathBuf>,
    #[serde(default)]
    stdlib_root: Option<PathBuf>,
    #[serde(default)]
    source_root: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceFileStamp {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}

struct CachedSourcePack {
    input: PathBuf,
    stdlib_root: PathBuf,
    source_root: Option<PathBuf>,
    source_pack: CachedCompileInput,
    file_stamps: Vec<SourceFileStamp>,
    directory_snapshots: Vec<SourceDirectorySnapshot>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceDirectorySnapshot {
    path: PathBuf,
    source_entries: Vec<(OsString, bool)>,
}

enum CachedCompileInput {
    Resident(ExplicitSourcePack),
    Bounded(ExplicitSourcePackPathManifest),
}

impl CachedCompileInput {
    #[cfg(test)]
    fn resident(&self) -> Option<&ExplicitSourcePack> {
        match self {
            Self::Resident(source_pack) => Some(source_pack),
            Self::Bounded(_) => None,
        }
    }

    #[cfg(test)]
    fn bounded(&self) -> Option<&ExplicitSourcePackPathManifest> {
        match self {
            Self::Bounded(source_pack) => Some(source_pack),
            Self::Resident(_) => None,
        }
    }
}

#[derive(Default)]
struct SourcePackCache {
    entry: Option<CachedSourcePack>,
    transient: Option<CachedCompileInput>,
}

impl SourcePackCache {
    fn load<'a>(
        &'a mut self,
        input: &Path,
        stdlib_root: &Path,
        source_root: Option<&Path>,
        resident_limits: crate::codegen::unit::CompilationUnitLimits,
    ) -> Result<&'a CachedCompileInput, crate::compiler::CompileError> {
        let same_project = self.entry.as_ref().is_some_and(|entry| {
            entry.input == input
                && entry.stdlib_root == stdlib_root
                && entry.source_root.as_deref() == source_root
        });
        if same_project && self.reuse_or_refresh_bounded_file_metadata() {
            return Ok(&self
                .entry
                .as_ref()
                .expect("reused source-pack cache entry disappeared")
                .source_pack);
        }

        self.entry = None;
        self.transient = None;

        let path_manifest = match source_root {
            Some(source_root) => load_entry_path_manifest_with_source_root_and_stdlib(
                input,
                source_root,
                stdlib_root,
            )?,
            None => load_entry_path_manifest_with_stdlib(input, stdlib_root)?,
        };
        let file_stamps = source_file_stamps(&path_manifest);
        let directory_snapshots =
            source_directory_snapshots(&path_manifest, input, stdlib_root, source_root);
        let source_pack = cached_compile_input(path_manifest, resident_limits)?;
        if let (Some(file_stamps), Some(directory_snapshots)) = (file_stamps, directory_snapshots) {
            self.entry = Some(CachedSourcePack {
                input: input.to_path_buf(),
                stdlib_root: stdlib_root.to_path_buf(),
                source_root: source_root.map(Path::to_path_buf),
                source_pack,
                file_stamps,
                directory_snapshots,
            });
            Ok(&self
                .entry
                .as_ref()
                .expect("stored source-pack cache entry disappeared")
                .source_pack)
        } else {
            self.transient = Some(source_pack);
            Ok(self
                .transient
                .as_ref()
                .expect("stored transient source pack disappeared"))
        }
    }

    fn reuse_or_refresh_bounded_file_metadata(&mut self) -> bool {
        let Some(entry) = self.entry.as_mut() else {
            return false;
        };
        if !directory_snapshots_match(&entry.directory_snapshots) {
            return false;
        }
        let Some(changes) = file_stamp_changes(&entry.file_stamps) else {
            return false;
        };
        if changes.is_empty() {
            return true;
        }
        let CachedCompileInput::Bounded(source_pack) = &mut entry.source_pack else {
            return false;
        };
        for (index, stamp) in changes {
            let Some(file) = source_pack.files.get_mut(index) else {
                return false;
            };
            let Ok(byte_len) = usize::try_from(stamp.len) else {
                return false;
            };
            file.byte_len = byte_len;
            file.modified_unix_nanos = stamp
                .modified
                .duration_since(std::time::UNIX_EPOCH)
                .ok()
                .map(|duration| duration.as_nanos());
            file.line_count = None;
            entry.file_stamps[index] = stamp;
        }
        true
    }
}

fn cached_compile_input(
    path_manifest: ExplicitSourcePackPathManifest,
    resident_limits: crate::codegen::unit::CompilationUnitLimits,
) -> Result<CachedCompileInput, crate::compiler::CompileError> {
    let library_count = path_manifest
        .files
        .iter()
        .map(|file| file.library_id)
        .collect::<std::collections::BTreeSet<_>>()
        .len();
    if library_count > 1 || path_manifest.requires_bounded_compilation_with_limits(resident_limits)
    {
        Ok(CachedCompileInput::Bounded(path_manifest))
    } else {
        Ok(CachedCompileInput::Resident(
            load_explicit_source_pack_from_path_manifest(&path_manifest)?,
        ))
    }
}

fn source_file_stamps(
    source_pack: &ExplicitSourcePackPathManifest,
) -> Option<Vec<SourceFileStamp>> {
    source_pack
        .files
        .iter()
        .map(|file| source_file_stamp(&file.path))
        .collect()
}

fn source_file_stamp(path: &Path) -> Option<SourceFileStamp> {
    let (len, modified) = source_file_stamp_values(path)?;
    Some(SourceFileStamp {
        path: path.to_path_buf(),
        len,
        modified,
    })
}

fn source_file_stamp_values(path: &Path) -> Option<(u64, SystemTime)> {
    let metadata = fs::metadata(path).ok()?;
    Some((metadata.len(), metadata.modified().ok()?))
}

#[cfg(test)]
fn file_stamps_match(stamps: &[SourceFileStamp]) -> bool {
    file_stamp_changes(stamps).is_some_and(|changes| changes.is_empty())
}

fn file_stamp_changes(stamps: &[SourceFileStamp]) -> Option<Vec<(usize, SourceFileStamp)>> {
    let mut changes = Vec::new();
    for (index, expected) in stamps.iter().enumerate() {
        let (len, modified) = source_file_stamp_values(&expected.path)?;
        if len != expected.len || modified != expected.modified {
            changes.push((
                index,
                SourceFileStamp {
                    path: expected.path.clone(),
                    len,
                    modified,
                },
            ));
        }
    }
    Some(changes)
}

fn source_directory_snapshots(
    source_pack: &ExplicitSourcePackPathManifest,
    input: &Path,
    stdlib_root: &Path,
    source_root: Option<&Path>,
) -> Option<Vec<SourceDirectorySnapshot>> {
    let roots = [input.parent(), Some(stdlib_root), source_root]
        .into_iter()
        .flatten()
        .flat_map(|root| {
            let canonical = fs::canonicalize(root).ok();
            std::iter::once(root.to_path_buf()).chain(canonical)
        })
        .collect::<Vec<_>>();
    let mut directories = BTreeSet::new();
    for file in &source_pack.files {
        let Some(parent) = file.path.parent() else {
            continue;
        };
        directories.insert(parent.to_path_buf());
        for root in &roots {
            if !parent.starts_with(root) {
                continue;
            }
            let mut ancestor = parent;
            while ancestor != root {
                let Some(next) = ancestor.parent() else {
                    break;
                };
                ancestor = next;
                directories.insert(ancestor.to_path_buf());
            }
        }
    }
    directories
        .into_iter()
        .map(|path| source_directory_snapshot(&path))
        .collect()
}

fn source_directory_snapshot(path: &Path) -> Option<SourceDirectorySnapshot> {
    let mut source_entries = fs::read_dir(path)
        .ok()?
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let file_type = entry.file_type().ok()?;
            let is_directory = file_type.is_dir();
            let is_lanius_source = entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "lani");
            (is_directory || is_lanius_source).then(|| (entry.file_name(), is_directory))
        })
        .collect::<Vec<_>>();
    source_entries.sort_unstable();
    Some(SourceDirectorySnapshot {
        path: path.to_path_buf(),
        source_entries,
    })
}

fn directory_snapshots_match(snapshots: &[SourceDirectorySnapshot]) -> bool {
    snapshots
        .iter()
        .all(|expected| source_directory_snapshot(&expected.path).as_ref() == Some(expected))
}

pub(super) fn run(args: Vec<String>) -> Result<(), CliError> {
    if args.len() == 1 && matches!(args[0].as_str(), "-h" | "--help") {
        print_help();
        return Ok(());
    }
    let options = parse_options(args)?;
    pollster::block_on(run_daemon(options))
}

fn print_help() {
    eprintln!(
        "Usage: laniusc daemon (--stdio | --unix-socket path) [--backend both|x86_64|wasm] [--stdlib-root dir] [--idle-buffer-timeout-ms milliseconds]\n\
         Starts one GPU-resident compiler and accepts newline-delimited JSON compile, trim, status, and shutdown requests."
    );
}

fn parse_options(args: Vec<String>) -> Result<DaemonOptions, CliError> {
    let mut backend = BackendSelection::Both;
    let mut stdlib_root = None;
    let mut stdio = false;
    let mut unix_socket = None;
    let mut idle_buffer_timeout_ms = DEFAULT_IDLE_BUFFER_TIMEOUT_MS;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--stdio" => stdio = true,
            "--unix-socket" => {
                unix_socket = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--unix-socket", "a socket path")
                })?));
            }
            "--backend" => {
                backend = parse_backend(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--backend", "both, x86_64, or wasm")
                })?)?;
            }
            "--stdlib-root" => {
                stdlib_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error("--stdlib-root", "a directory path")
                })?));
            }
            "--idle-buffer-timeout-ms" => {
                idle_buffer_timeout_ms =
                    parse_idle_buffer_timeout_ms(args.next().ok_or_else(|| {
                        missing_cli_option_value_error(
                            "--idle-buffer-timeout-ms",
                            "a non-negative integer",
                        )
                    })?)?;
            }
            value if value.starts_with("--backend=") => {
                backend = parse_backend(value.trim_start_matches("--backend=").to_string())?;
            }
            value if value.starts_with("--stdlib-root=") => {
                stdlib_root = Some(PathBuf::from(value.trim_start_matches("--stdlib-root=")));
            }
            value if value.starts_with("--unix-socket=") => {
                unix_socket = Some(PathBuf::from(value.trim_start_matches("--unix-socket=")));
            }
            value if value.starts_with("--idle-buffer-timeout-ms=") => {
                idle_buffer_timeout_ms = parse_idle_buffer_timeout_ms(
                    value.trim_start_matches("--idle-buffer-timeout-ms="),
                )?;
            }
            flag => {
                return Err(unknown_cli_option_error(
                    "laniusc daemon",
                    flag,
                    "--stdio, --unix-socket, --backend, --stdlib-root, --idle-buffer-timeout-ms",
                ));
            }
        }
    }
    let transport = match (stdio, unix_socket) {
        (true, None) => DaemonTransport::Stdio,
        #[cfg(unix)]
        (false, Some(path)) => DaemonTransport::UnixSocket(path),
        #[cfg(not(unix))]
        (false, Some(_)) => {
            return Err(CliError::from(
                "laniusc daemon --unix-socket is only supported on Unix hosts",
            ));
        }
        (false, None) => {
            return Err(CliError::from(
                "laniusc daemon requires exactly one transport: --stdio or --unix-socket",
            ));
        }
        (true, Some(_)) => {
            return Err(CliError::from(
                "laniusc daemon accepts only one transport: --stdio or --unix-socket",
            ));
        }
    };
    Ok(DaemonOptions {
        backend,
        stdlib_root,
        transport,
        idle_buffer_timeout: (idle_buffer_timeout_ms != 0)
            .then(|| Duration::from_millis(idle_buffer_timeout_ms)),
    })
}

fn parse_idle_buffer_timeout_ms(value: impl AsRef<str>) -> Result<u64, CliError> {
    let value = value.as_ref();
    value.parse::<u64>().map_err(|err| {
        unsupported_cli_option_value_error(
            "--idle-buffer-timeout-ms",
            value,
            "a non-negative integer; zero disables automatic trimming",
            Some(err.to_string()),
        )
    })
}

fn parse_backend(value: String) -> Result<BackendSelection, CliError> {
    match value.as_str() {
        "both" => Ok(BackendSelection::Both),
        "wasm" => Ok(BackendSelection::Wasm),
        "x86_64" => Ok(BackendSelection::X86),
        _ => Err(unsupported_cli_option_value_error(
            "--backend",
            &value,
            "both, x86_64, wasm",
            None,
        )),
    }
}

async fn run_daemon(options: DaemonOptions) -> Result<(), CliError> {
    let startup = Instant::now();
    let compiler: Arc<GpuCompiler<'static>> = Arc::new(
        GpuCompiler::new_with_backends(options.backend.compiler_backends())
            .await
            .map_err(CliError::from_compile_error)?,
    );
    #[cfg(not(debug_assertions))]
    if matches!(options.backend, BackendSelection::X86) {
        device::global().persist_and_release_pipeline_cache();
    }
    let startup_ms = startup.elapsed().as_secs_f64() * 1000.0;

    match &options.transport {
        DaemonTransport::Stdio => {
            let stdin = io::stdin();
            let input = stdin.lock();
            let stdout = io::stdout();
            let output = stdout.lock();
            run_session(compiler.clone(), &options, startup_ms, input, output).await
        }
        #[cfg(unix)]
        DaemonTransport::UnixSocket(path) => {
            let listener = UnixListener::bind(path).map_err(|err| {
                CliError::from(format!("bind daemon socket {}: {err}", path.display()))
            })?;
            let _socket_cleanup = UnixSocketCleanup(path.clone());
            let (stream, _) = listener.accept().map_err(|err| {
                CliError::from(format!("accept daemon socket {}: {err}", path.display()))
            })?;
            let input = io::BufReader::new(stream.try_clone().map_err(|err| {
                CliError::from(format!("clone daemon socket {}: {err}", path.display()))
            })?);
            run_session(compiler.clone(), &options, startup_ms, input, stream).await
        }
    }
}

#[cfg(unix)]
struct UnixSocketCleanup(PathBuf);

#[cfg(unix)]
impl Drop for UnixSocketCleanup {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

async fn run_session(
    compiler: Arc<GpuCompiler<'static>>,
    options: &DaemonOptions,
    startup_ms: f64,
    mut input: impl BufRead,
    mut output: impl Write,
) -> Result<(), CliError> {
    let reaper = ResidentBufferReaper::start(compiler.clone(), options.idle_buffer_timeout);
    write_response(
        &mut output,
        &json!({
            "schema": DAEMON_SCHEMA,
            "event": "ready",
            "startup_ms": startup_ms,
            "pid": std::process::id(),
            "resident_set_bytes": resident_set_bytes(),
            "tracked_gpu_buffers": tracked_gpu_buffer_metrics(),
            "wgpu_resources": wgpu_resource_metrics(),
            "compute_pipelines_created": pipeline_creation_count(),
            "recorded_compute_passes": recorded_compute_pass_count(),
            "recorded_compute_dispatches": recorded_compute_dispatch_count(),
            "idle_buffer_timeout_ms": options
                .idle_buffer_timeout
                .map(|timeout| timeout.as_millis() as u64),
            "targets": options.backend.targets(),
        }),
    )?;

    let mut line = String::new();
    let mut source_pack_cache = SourcePackCache::default();
    loop {
        line.clear();
        let read = input
            .read_line(&mut line)
            .map_err(|err| CliError::from(format!("read daemon request: {err}")))?;
        if read == 0 {
            break;
        }
        if line.len() > MAX_REQUEST_BYTES {
            write_response(
                &mut output,
                &protocol_error(Value::Null, "request exceeds the 1 MiB limit"),
            )?;
            continue;
        }
        let request = match serde_json::from_str::<DaemonRequest>(&line) {
            Ok(request) => request,
            Err(err) => {
                write_response(
                    &mut output,
                    &protocol_error(Value::Null, &format!("invalid request JSON: {err}")),
                )?;
                continue;
            }
        };
        if request.command == "shutdown" {
            write_response(
                &mut output,
                &json!({
                    "schema": DAEMON_SCHEMA,
                    "id": request.id,
                    "ok": true,
                    "event": "shutdown",
                }),
            )?;
            break;
        }
        if request.command == "trim" {
            let before = tracked_gpu_buffer_metrics();
            compiler.release_resident_job_buffers().await;
            reaper.disarm();
            write_response(
                &mut output,
                &json!({
                    "schema": DAEMON_SCHEMA,
                    "id": request.id,
                    "ok": true,
                    "event": "trimmed",
                    "tracked_gpu_buffers_before": before,
                    "tracked_gpu_buffers": tracked_gpu_buffer_metrics(),
                    "resident_set_bytes": resident_set_bytes(),
                    "wgpu_resources": wgpu_resource_metrics(),
                    "recorded_compute_passes": recorded_compute_pass_count(),
                    "recorded_compute_dispatches": recorded_compute_dispatch_count(),
                }),
            )?;
            continue;
        }
        if request.command == "clear-compiled-unit-cache" {
            let before = compiler.compiled_unit_cache_stats();
            compiler.clear_compiled_unit_cache();
            let after = compiler.compiled_unit_cache_stats();
            write_response(
                &mut output,
                &json!({
                    "schema": DAEMON_SCHEMA,
                    "id": request.id,
                    "ok": true,
                    "event": "compiled-unit-cache-cleared",
                    "entries_before": before.entries,
                    "resident_bytes_before": before.resident_bytes,
                    "entries_after": after.entries,
                    "resident_bytes_after": after.resident_bytes,
                }),
            )?;
            continue;
        }
        if request.command == "clear-project-compiled-unit-cache" {
            let before = compiler.compiled_unit_cache_stats();
            compiler.clear_project_compiled_unit_cache();
            let after = compiler.compiled_unit_cache_stats();
            write_response(
                &mut output,
                &json!({
                    "schema": DAEMON_SCHEMA,
                    "id": request.id,
                    "ok": true,
                    "event": "project-compiled-unit-cache-cleared",
                    "entries_before": before.entries,
                    "resident_bytes_before": before.resident_bytes,
                    "entries_after": after.entries,
                    "resident_bytes_after": after.resident_bytes,
                }),
            )?;
            continue;
        }
        if request.command == "status" {
            write_response(
                &mut output,
                &json!({
                    "schema": DAEMON_SCHEMA,
                    "id": request.id,
                    "ok": true,
                    "event": "status",
                    "tracked_gpu_buffers": tracked_gpu_buffer_metrics(),
                    "resident_set_bytes": resident_set_bytes(),
                    "wgpu_resources": wgpu_resource_metrics(),
                    "recorded_compute_passes": recorded_compute_pass_count(),
                    "recorded_compute_dispatches": recorded_compute_dispatch_count(),
                }),
            )?;
            continue;
        }
        if request.command != "compile" {
            write_response(
                &mut output,
                &protocol_error(
                    request.id,
                    "command must be compile, clear-compiled-unit-cache, clear-project-compiled-unit-cache, trim, status, or shutdown",
                ),
            )?;
            continue;
        }
        // A compilation is active rather than idle. Cancel the previous idle
        // deadline before it can contend for the resident pipeline lock.
        reaper.disarm();
        let compute_passes_before = recorded_compute_pass_count();
        let compute_dispatches_before = recorded_compute_dispatch_count();
        let compute_schedule_job = begin_compute_schedule_job();
        let compute_pass_breakdown_before =
            compute_pass_breakdown_enabled().then(recorded_compute_pass_counts_by_label);
        let resources_before = job_resource_creation_counts();
        let bind_group_timing_before = bind_group_timing_counters();
        let bind_group_job = crate::gpu::passes_core::begin_reflected_bind_group_job();
        let resource_breakdown_enabled =
            crate::gpu::env::env_bool_strict("LANIUS_GPU_BUFFER_BREAKDOWN", false)
                || (resources_before.bind_groups > 0
                    && crate::gpu::env::env_bool_strict(
                        "LANIUS_GPU_RESOURCE_CREATION_BREAKDOWN",
                        false,
                    ));
        let breakdown_before = resource_breakdown_enabled.then(job_resource_creation_breakdown);
        let job_trace_name = request.id.as_str().map_or_else(
            || format!("daemon.job.{}", request.id),
            |id| format!("daemon.job.{id}"),
        );
        let job_trace_started = Instant::now();
        let mut response =
            compile_request(&compiler, options, &mut source_pack_cache, request).await;
        crate::gpu::trace::record_host_span(
            "host.daemon",
            &job_trace_name,
            job_trace_started,
            Instant::now(),
        );
        let resources_after = job_resource_creation_counts();
        let recorded_compute_passes_during_job =
            recorded_compute_pass_count().saturating_sub(compute_passes_before);
        let recorded_compute_dispatches_during_job =
            recorded_compute_dispatch_count().saturating_sub(compute_dispatches_before);
        let compute_submission_schedule = finish_compute_schedule_job(compute_schedule_job);
        let compute_pass_breakdown_after = compute_pass_breakdown_before
            .as_ref()
            .map(|_| recorded_compute_pass_counts_by_label());
        let bind_group_timing =
            bind_group_timing_counters().saturating_sub(bind_group_timing_before);
        let created = resources_after.saturating_sub(resources_before);
        let successful = response.get("ok").and_then(Value::as_bool).unwrap_or(false);
        crate::gpu::passes_core::finish_reflected_bind_group_job(
            bind_group_job,
            successful && created.buffers > 0,
        );
        let breakdown_after = breakdown_before
            .as_ref()
            .map(|_| job_resource_creation_breakdown());
        if let Some(response) = response.as_object_mut() {
            response.insert(
                "resource_creations_before_job".into(),
                resources_before.to_json(),
            );
            response.insert(
                "resource_creations_after_job".into(),
                resources_after.to_json(),
            );
            response.insert("resources_created_during_job".into(), created.to_json());
            response.insert(
                "recorded_compute_passes_during_job".into(),
                json!(recorded_compute_passes_during_job),
            );
            response.insert(
                "recorded_compute_dispatches_during_job".into(),
                json!(recorded_compute_dispatches_during_job),
            );
            if let (Some(before), Some(after)) = (
                &compute_pass_breakdown_before,
                &compute_pass_breakdown_after,
            ) {
                response.insert(
                    "recorded_compute_pass_breakdown".into(),
                    compute_pass_delta_rows(after, before),
                );
            }
            if !compute_submission_schedule.is_empty() {
                response.insert(
                    "recorded_compute_submission_schedule".into(),
                    json!(compute_submission_schedule),
                );
            }
            let compiler_graphs = compiler_graph_diagnostics();
            if !compiler_graphs.is_empty() {
                response.insert("compiler_graphs".into(), json!(compiler_graphs));
            }
            if bind_group_timing_enabled() {
                response.insert(
                    "bind_group_timing_ms".into(),
                    json!({
                        "resource_plan": bind_group_timing.resource_plan_ns as f64 / 1_000_000.0,
                        "cache": bind_group_timing.cache_ns as f64 / 1_000_000.0,
                        "wgpu_create": bind_group_timing.wgpu_create_ns as f64 / 1_000_000.0,
                    }),
                );
            }
            response.insert(
                "workspace_request_kind".into(),
                if created.buffers == 0 && created.bind_groups == 0 {
                    "retained_capacity"
                } else {
                    "cold_or_grown_workspace"
                }
                .into(),
            );
            // Keep stdio responses bounded: a cold/growth job can create hundreds
            // of distinct labels and fill the child's captured-output pipe before
            // the test harness starts reading it. The focused diagnostic is for
            // small unexpected deltas on otherwise resident jobs.
            if created.buffers.saturating_add(created.bind_groups) <= 32
                && let (Some(before), Some(after)) = (&breakdown_before, &breakdown_after)
            {
                response.insert(
                    "resource_creation_breakdown".into(),
                    after.delta_json(before),
                );
            }
        }
        write_response(&mut output, &response)?;
        reaper.arm();
    }
    crate::gpu::trace::flush();
    device::persist_pipeline_cache();
    Ok(())
}

#[derive(Clone, Copy)]
struct JobResourceCreationCounts {
    buffers: u64,
    bind_groups: u64,
    compute_pipelines: u64,
}

impl JobResourceCreationCounts {
    fn saturating_sub(self, before: Self) -> Self {
        Self {
            buffers: self.buffers.saturating_sub(before.buffers),
            bind_groups: self.bind_groups.saturating_sub(before.bind_groups),
            compute_pipelines: self
                .compute_pipelines
                .saturating_sub(before.compute_pipelines),
        }
    }

    fn to_json(self) -> Value {
        json!({
            "buffers": self.buffers,
            "bind_groups": self.bind_groups,
            "compute_pipelines": self.compute_pipelines,
        })
    }
}

fn job_resource_creation_counts() -> JobResourceCreationCounts {
    JobResourceCreationCounts {
        buffers: buffer_creation_count(),
        bind_groups: bind_group_creation_count(),
        compute_pipelines: pipeline_creation_count(),
    }
}

fn compute_pass_delta_rows(after: &HashMap<String, u64>, before: &HashMap<String, u64>) -> Value {
    let mut rows = after
        .iter()
        .filter_map(|(label, &count)| {
            let delta = count.saturating_sub(before.get(label).copied().unwrap_or(0));
            (delta > 0).then(|| (label, delta))
        })
        .collect::<Vec<_>>();
    rows.sort_unstable_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(right.0)));
    Value::Array(
        rows.into_iter()
            .map(|(label, count)| json!({"label": label, "passes": count}))
            .collect(),
    )
}

struct JobResourceCreationBreakdown {
    buffers: HashMap<String, u64>,
    bind_groups: HashMap<String, u64>,
}

impl JobResourceCreationBreakdown {
    fn delta_json(&self, before: &Self) -> Value {
        fn rows(after: &HashMap<String, u64>, before: &HashMap<String, u64>) -> Value {
            let mut rows = after
                .iter()
                .filter_map(|(label, &count)| {
                    let created = count.saturating_sub(before.get(label).copied().unwrap_or(0));
                    (created > 0).then(|| (label, created))
                })
                .collect::<Vec<_>>();
            rows.sort_unstable_by(|left, right| {
                right.1.cmp(&left.1).then_with(|| left.0.cmp(right.0))
            });
            Value::Array(
                rows.into_iter()
                    .map(|(label, created)| json!({"label": label, "created": created}))
                    .collect(),
            )
        }
        json!({
            "buffers": rows(&self.buffers, &before.buffers),
            "bind_groups": rows(&self.bind_groups, &before.bind_groups),
        })
    }
}

fn job_resource_creation_breakdown() -> JobResourceCreationBreakdown {
    JobResourceCreationBreakdown {
        buffers: buffer_creation_counts_by_label()
            .into_iter()
            .map(|(label, count)| (label.to_string(), count))
            .collect(),
        bind_groups: bind_group_creation_counts_by_label(),
    }
}

enum ResidentBufferReaperMessage {
    Arm,
    Disarm,
    Stop,
}

struct ResidentBufferReaper {
    sender: Option<Sender<ResidentBufferReaperMessage>>,
    thread: Option<JoinHandle<()>>,
}

impl ResidentBufferReaper {
    fn start(
        compiler: Arc<GpuCompiler<'static>>,
        timeout: Option<Duration>,
    ) -> ResidentBufferReaper {
        let Some(timeout) = timeout else {
            return Self {
                sender: None,
                thread: None,
            };
        };
        let (sender, receiver) = mpsc::channel();
        let thread = std::thread::spawn(move || {
            let mut armed = false;
            loop {
                let message = if armed {
                    match receiver.recv_timeout(timeout) {
                        Ok(message) => message,
                        Err(RecvTimeoutError::Timeout) => {
                            pollster::block_on(compiler.release_resident_job_buffers());
                            armed = false;
                            continue;
                        }
                        Err(RecvTimeoutError::Disconnected) => break,
                    }
                } else {
                    match receiver.recv() {
                        Ok(message) => message,
                        Err(_) => break,
                    }
                };
                match message {
                    ResidentBufferReaperMessage::Arm => armed = true,
                    ResidentBufferReaperMessage::Disarm => armed = false,
                    ResidentBufferReaperMessage::Stop => break,
                }
            }
        });
        Self {
            sender: Some(sender),
            thread: Some(thread),
        }
    }

    fn arm(&self) {
        if let Some(sender) = &self.sender {
            let _ = sender.send(ResidentBufferReaperMessage::Arm);
        }
    }

    fn disarm(&self) {
        if let Some(sender) = &self.sender {
            let _ = sender.send(ResidentBufferReaperMessage::Disarm);
        }
    }
}

impl Drop for ResidentBufferReaper {
    fn drop(&mut self) {
        if let Some(sender) = self.sender.take() {
            let _ = sender.send(ResidentBufferReaperMessage::Stop);
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

async fn compile_request(
    compiler: &GpuCompiler<'_>,
    options: &DaemonOptions,
    source_pack_cache: &mut SourcePackCache,
    request: DaemonRequest,
) -> Value {
    let started = Instant::now();
    let id = request.id;
    let emit = request.emit.unwrap_or_default();
    if !options.backend.supports(&emit) {
        return job_error(
            id,
            started,
            format!("emit target {emit:?} was not initialized by this daemon"),
        );
    }
    let Some(input) = request.input else {
        return job_error(id, started, "compile request is missing input".into());
    };
    let Some(output) = request.output else {
        return job_error(id, started, "compile request is missing output".into());
    };
    let Some(stdlib_root) = request.stdlib_root.or_else(|| options.stdlib_root.clone()) else {
        return job_error(
            id,
            started,
            "compile request needs stdlib_root or daemon --stdlib-root".into(),
        );
    };
    let source_root = request.source_root;

    let load_started = Instant::now();
    let source_pack = match source_pack_cache.load(
        &input,
        &stdlib_root,
        source_root.as_deref(),
        compiler.resident_source_unit_limits(),
    ) {
        Ok(source_pack) => source_pack,
        Err(err) => return compile_error_response(id, started, err),
    };
    let load_ms = load_started.elapsed().as_secs_f64() * 1000.0;
    crate::gpu::buffers::reset_tracked_buffer_allocation_peaks();
    crate::gpu::buffers::begin_tracked_buffer_residency_timeline(crate::gpu::env::env_bool_strict(
        "LANIUS_GPU_MEMORY_TIMELINE",
        false,
    ));
    let unit_cache_before = compiler.compiled_unit_cache_stats();
    let compile_started = Instant::now();
    enum EmittedArtifact {
        Bytes(Vec<u8>),
        File(u64),
    }

    let emitted = match (emit.as_str(), source_pack) {
        ("wasm", CachedCompileInput::Resident(source_pack)) => compiler
            .compile_source_pack_manifest_to_wasm(source_pack)
            .await
            .map(EmittedArtifact::Bytes),
        ("wasm", CachedCompileInput::Bounded(source_pack)) => compiler
            .compile_path_manifest_to_file(source_pack, SourcePackArtifactTarget::Wasm, &output)
            .await
            .map(EmittedArtifact::File),
        ("x86_64", CachedCompileInput::Resident(source_pack)) => compiler
            .compile_source_pack_manifest_to_x86_64(source_pack)
            .await
            .map(EmittedArtifact::Bytes),
        ("x86_64", CachedCompileInput::Bounded(source_pack)) => compiler
            .compile_path_manifest_to_file(source_pack, SourcePackArtifactTarget::X86_64, &output)
            .await
            .map(EmittedArtifact::File),
        _ => unreachable!("backend support check accepted an unknown target"),
    };
    let compile_ms = compile_started.elapsed().as_secs_f64() * 1000.0;
    let unit_cache_after = compiler.compiled_unit_cache_stats();
    let emitted = match emitted {
        Ok(emitted) => emitted,
        Err(err) => return compile_error_response(id, started, err),
    };
    let write_started = Instant::now();
    let output_bytes = match emitted {
        EmittedArtifact::Bytes(bytes) => {
            if let Err(err) = write_artifact(&output, &bytes, &emit) {
                return job_error(id, started, err);
            }
            bytes.len() as u64
        }
        EmittedArtifact::File(byte_len) => byte_len,
    };
    let write_ms = write_started.elapsed().as_secs_f64() * 1000.0;
    json!({
        "schema": DAEMON_SCHEMA,
        "id": id,
        "ok": true,
        "emit": emit,
        "input": input,
        "source_root": source_root,
        "output": output,
        "output_bytes": output_bytes,
        "load_ms": load_ms,
        "compile_ms": compile_ms,
        "compiled_unit_cache": {
            "hits_during_job": unit_cache_after.hits.saturating_sub(unit_cache_before.hits),
            "misses_during_job": unit_cache_after.misses.saturating_sub(unit_cache_before.misses),
            "evictions_during_job": unit_cache_after.evictions.saturating_sub(unit_cache_before.evictions),
            "entries_after_job": unit_cache_after.entries,
            "resident_bytes_after_job": unit_cache_after.resident_bytes,
        },
        "write_ms": write_ms,
        "elapsed_ms": started.elapsed().as_secs_f64() * 1000.0,
        "resident_set_bytes": resident_set_bytes(),
        "tracked_gpu_buffers": tracked_gpu_buffer_metrics(),
        "wgpu_resources": wgpu_resource_metrics(),
    })
}

fn tracked_gpu_buffer_metrics() -> Value {
    let stats = crate::gpu::buffers::tracked_buffer_allocation_stats();
    let peak = crate::gpu::buffers::tracked_buffer_allocation_peak_stats();
    let user_owned_wgpu_buffers = device::global()
        .resource_stats()
        .map(|stats| stats.buffers.kept_from_user as u64);
    let untracked_allocations =
        user_owned_wgpu_buffers.map(|buffers| buffers.saturating_sub(stats.allocations));
    let mut metrics = json!({
        "allocations": stats.allocations,
        "bytes": stats.bytes,
        "peak_allocations": peak.allocations,
        "peak_bytes": peak.bytes,
        "user_owned_wgpu_buffers": user_owned_wgpu_buffers,
        "untracked_allocations": untracked_allocations,
        "scope": "live LaniusBuffer allocation identities and bytes; untracked_allocations counts raw user-owned wgpu buffers whose byte sizes are unavailable",
        "phase_snapshots": crate::gpu::buffers::tracked_buffer_phase_snapshots()
            .into_iter()
            .map(|snapshot| json!({
                "phase": snapshot.phase.as_ref(),
                "allocations": snapshot.stats.allocations,
                "bytes": snapshot.stats.bytes,
            }))
            .collect::<Vec<_>>(),
    });
    let residency_timeline = crate::gpu::buffers::tracked_buffer_residency_timeline();
    if !residency_timeline.is_empty() {
        metrics.as_object_mut().expect("tracked GPU buffer metrics object").insert(
            "residency_timeline".into(),
            json!({
                "origin": "compile_start",
                "semantics": "exact tracked physical LaniusBuffer residency after each allocation or final release",
                "points": residency_timeline.into_iter().map(|point| json!({
                    "elapsed_ms": point.elapsed_ns as f64 / 1_000_000.0,
                    "allocations": point.allocations,
                    "bytes": point.bytes,
                    "event": point.event,
                    "allocation_id": point.allocation_id,
                    "label": point.label.as_deref(),
                    "changed_bytes": point.changed_bytes,
                })).collect::<Vec<_>>(),
            }),
        );
    }
    if crate::gpu::env::env_bool_strict("LANIUS_GPU_BUFFER_BREAKDOWN", false) {
        for snapshot in crate::gpu::buffers::tracked_buffer_phase_snapshots() {
            eprintln!(
                "gpu_buffer_phase phase=\"{}\" allocations={} bytes={}",
                snapshot.phase, snapshot.stats.allocations, snapshot.stats.bytes,
            );
        }
        const DEFAULT_MAX_LABEL_ROWS: usize = 64;
        const MAX_CONFIGURED_LABEL_ROWS: usize = 16_384;
        let max_label_rows = std::env::var("LANIUS_GPU_BUFFER_BREAKDOWN_LIMIT")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .filter(|&value| value > 0)
            .unwrap_or(DEFAULT_MAX_LABEL_ROWS)
            .min(MAX_CONFIGURED_LABEL_ROWS);
        let rows = crate::gpu::buffers::tracked_buffer_allocation_stats_by_label();
        let listed_bytes = rows
            .iter()
            .take(max_label_rows)
            .map(|row| row.bytes)
            .sum::<u64>();
        let breakdown = rows
            .iter()
            .take(max_label_rows)
            .map(|row| {
                json!({
                    "label": row.label.as_ref(),
                    "allocations": row.allocations,
                    "bytes": row.bytes,
                })
            })
            .collect::<Vec<_>>();
        metrics["largest_allocations_by_label"] = breakdown.into();
        metrics["largest_allocations_listed_bytes"] = listed_bytes.into();
        metrics["largest_allocations_omitted_bytes"] =
            stats.bytes.saturating_sub(listed_bytes).into();
    }
    metrics
}

fn wgpu_resource_metrics() -> Value {
    let Some(stats) = device::global().resource_stats() else {
        return Value::Null;
    };
    let registry = |stats: crate::gpu::device::WgpuRegistryStats| {
        json!({
            "kept_from_user": stats.kept_from_user,
            "released_from_user": stats.released_from_user,
        })
    };
    json!({
        "buffers": registry(stats.buffers),
        "bind_groups": registry(stats.bind_groups),
        "command_encoders": registry(stats.command_encoders),
        "command_buffers": registry(stats.command_buffers),
        "compute_pipelines": registry(stats.compute_pipelines),
        "query_sets": registry(stats.query_sets),
    })
}

fn compile_error_response(
    id: Value,
    started: Instant,
    err: crate::compiler::CompileError,
) -> Value {
    json!({
        "schema": DAEMON_SCHEMA,
        "id": id,
        "ok": false,
        "elapsed_ms": started.elapsed().as_secs_f64() * 1000.0,
        "diagnostic": err.into_public_diagnostic(),
    })
}

fn protocol_error(id: Value, message: &str) -> Value {
    json!({
        "schema": DAEMON_SCHEMA,
        "id": id,
        "ok": false,
        "protocol_error": message,
    })
}

fn job_error(id: Value, started: Instant, message: String) -> Value {
    json!({
        "schema": DAEMON_SCHEMA,
        "id": id,
        "ok": false,
        "elapsed_ms": started.elapsed().as_secs_f64() * 1000.0,
        "job_error": message,
    })
}

fn write_response(output: &mut impl Write, response: &Value) -> Result<(), CliError> {
    serde_json::to_writer(&mut *output, response)
        .map_err(|err| CliError::from(format!("serialize daemon response: {err}")))?;
    output
        .write_all(b"\n")
        .and_then(|()| output.flush())
        .map_err(|err| CliError::from(format!("write daemon response: {err}")))
}

fn write_artifact(path: &Path, bytes: &[u8], emit: &str) -> Result<(), String> {
    fs::write(path, bytes).map_err(|err| format!("write output {}: {err}", path.display()))?;
    #[cfg(unix)]
    if emit == "x86_64" {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .map_err(|err| format!("stat output {}: {err}", path.display()))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions)
            .map_err(|err| format!("chmod output {}: {err}", path.display()))?;
    }
    Ok(())
}

fn resident_set_bytes() -> Option<u64> {
    let status = fs::read_to_string("/proc/self/status").ok()?;
    let line = status.lines().find(|line| line.starts_with("VmRSS:"))?;
    let kib = line.split_whitespace().nth(1)?.parse::<u64>().ok()?;
    kib.checked_mul(1024)
}

#[cfg(test)]
mod tests {
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn compute_pass_breakdown_reports_sorted_per_job_deltas() {
        let before = HashMap::from([("parser".to_owned(), 20), ("typecheck".to_owned(), 100)]);
        let after = HashMap::from([
            ("parser".to_owned(), 23),
            ("typecheck".to_owned(), 107),
            ("lowering".to_owned(), 5),
        ]);

        assert_eq!(
            compute_pass_delta_rows(&after, &before),
            json!([
                {"label": "typecheck", "passes": 7},
                {"label": "lowering", "passes": 5},
                {"label": "parser", "passes": 3},
            ])
        );
    }

    #[test]
    fn daemon_options_select_one_backend_and_default_stdlib() {
        let options = parse_options(vec![
            "--stdio".into(),
            "--backend=x86_64".into(),
            "--stdlib-root".into(),
            "stdlib".into(),
        ])
        .expect("daemon options should parse");
        assert!(matches!(options.backend, BackendSelection::X86));
        assert_eq!(options.stdlib_root, Some(PathBuf::from("stdlib")));
        assert_eq!(
            options.idle_buffer_timeout,
            Some(Duration::from_millis(DEFAULT_IDLE_BUFFER_TIMEOUT_MS))
        );
    }

    #[test]
    fn daemon_compile_request_accepts_a_project_source_root() {
        let request: DaemonRequest = serde_json::from_str(
            r#"{"id":"project","command":"compile","input":"main.lani","output":"app","source_root":"src"}"#,
        )
        .expect("daemon compile request with source root should deserialize");
        assert_eq!(request.source_root, Some(PathBuf::from("src")));
    }

    #[test]
    fn daemon_idle_buffer_timeout_is_configurable_and_zero_disables_it() {
        let options = parse_options(vec![
            "--stdio".into(),
            "--idle-buffer-timeout-ms=1250".into(),
        ])
        .expect("idle buffer timeout should parse");
        assert_eq!(
            options.idle_buffer_timeout,
            Some(Duration::from_millis(1250))
        );

        let options = parse_options(vec![
            "--stdio".into(),
            "--idle-buffer-timeout-ms".into(),
            "0".into(),
        ])
        .expect("zero idle buffer timeout should parse");
        assert_eq!(options.idle_buffer_timeout, None);
    }

    #[test]
    fn daemon_requires_exactly_one_explicit_transport() {
        let err = parse_options(Vec::new()).expect_err("missing transport should fail");
        assert!(err.to_string().contains("requires exactly one transport"));
        let err = parse_options(vec![
            "--stdio".into(),
            "--unix-socket=/tmp/laniusc.sock".into(),
        ])
        .expect_err("multiple transports should fail");
        assert!(err.to_string().contains("accepts only one transport"));
    }

    #[cfg(unix)]
    #[test]
    fn daemon_options_accept_unix_socket_transport() {
        let options = parse_options(vec![
            "--unix-socket".into(),
            "/tmp/laniusc.sock".into(),
            "--backend=wasm".into(),
        ])
        .expect("Unix socket transport should parse");
        assert!(matches!(options.backend, BackendSelection::Wasm));
        assert!(matches!(
            options.transport,
            DaemonTransport::UnixSocket(path) if path == PathBuf::from("/tmp/laniusc.sock")
        ));
    }

    #[test]
    fn source_pack_file_stamps_invalidate_after_change_and_removal() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should follow the Unix epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "laniusc-daemon-source-cache-{}-{unique}.lani",
            std::process::id()
        ));
        fs::write(&path, "fn main() {}\n").expect("write source cache fixture");
        let source_pack = ExplicitSourcePackPathManifest::from_libraries(vec![
            crate::compiler::ExplicitSourceLibraryPaths {
                library_id: 1,
                paths: vec![path.clone()],
                dependency_library_ids: Vec::new(),
            },
        ])
        .expect("build source cache fixture pack");
        let stamps = source_file_stamps(&source_pack).expect("source paths should be cacheable");
        assert!(file_stamps_match(&stamps));

        fs::write(&path, "fn main() { return; }\n").expect("change source cache fixture");
        assert!(!file_stamps_match(&stamps));

        fs::remove_file(&path).expect("remove source cache fixture");
        assert!(!file_stamps_match(&stamps));
    }

    #[test]
    fn source_pack_cache_reloads_changed_entry_source() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should follow the Unix epoch")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc-daemon-load-cache-{}-{unique}",
            std::process::id()
        ));
        let stdlib_root = root.join("stdlib");
        let entry = root.join("main.lani");
        fs::create_dir_all(&stdlib_root).expect("create source cache stdlib fixture");
        fs::write(&entry, "fn main() { return; }\n").expect("write cached entry fixture");

        let mut cache = SourcePackCache::default();
        let resident_limits = crate::codegen::unit::CompilationUnitLimits::default();
        let first = cache
            .load(&entry, &stdlib_root, None, resident_limits)
            .expect("load initial cached source pack");
        assert!(first.resident().is_some_and(|source_pack| {
            source_pack
                .sources
                .iter()
                .any(|source| source.contains("return;"))
        }));

        fs::write(&entry, "fn main() { print(17); return; }\n")
            .expect("change cached entry fixture");
        let second = cache
            .load(&entry, &stdlib_root, None, resident_limits)
            .expect("reload changed source pack");
        assert!(second.resident().is_some_and(|source_pack| {
            source_pack
                .sources
                .iter()
                .any(|source| source.contains("print(17)"))
        }));

        fs::remove_dir_all(root).expect("remove source cache fixture tree");
    }

    #[test]
    fn bounded_source_pack_cache_refreshes_edits_and_rediscovers_new_files() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should follow the Unix epoch")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc-daemon-bounded-cache-{}-{unique}",
            std::process::id()
        ));
        let stdlib_root = root.join("stdlib");
        let source_root = root.join("src");
        let entry = root.join("main.lani");
        let unit = source_root.join("unit.lani");
        fs::create_dir_all(&stdlib_root).expect("create bounded cache stdlib fixture");
        fs::create_dir_all(&source_root).expect("create bounded cache source fixture");
        fs::write(&entry, "import unit;\nfn main() { return; }\n")
            .expect("write bounded cache entry");
        fs::write(&unit, "module unit;\nfn unit() { return; }\n")
            .expect("write bounded cache unit");

        let mut cache = SourcePackCache::default();
        let limits = crate::codegen::unit::CompilationUnitLimits {
            max_source_bytes: 1,
            max_source_files: 1,
        };
        let initial_count = cache
            .load(&entry, &stdlib_root, Some(&source_root), limits)
            .expect("load initial bounded source pack")
            .bounded()
            .expect("tiny limits should select bounded input")
            .files
            .len();

        let changed_source = "module unit;\nfn unit() { print(123456); return; }\n";
        fs::write(&unit, changed_source).expect("change bounded cache unit");
        let refreshed = cache
            .load(&entry, &stdlib_root, Some(&source_root), limits)
            .expect("incrementally refresh bounded source pack")
            .bounded()
            .expect("refreshed input should remain bounded");
        assert_eq!(refreshed.files.len(), initial_count);
        assert_eq!(
            refreshed
                .files
                .iter()
                .find(|file| file
                    .path
                    .file_name()
                    .is_some_and(|name| name == "unit.lani"))
                .expect("refreshed unit remains in manifest")
                .byte_len,
            changed_source.len()
        );

        fs::write(
            source_root.join("added.lani"),
            "module added;\nfn added() { return; }\n",
        )
        .expect("add bounded cache source");
        fs::write(
            &entry,
            "import unit;\nimport added;\nfn main() { return; }\n",
        )
        .expect("import added bounded cache source");
        let rediscovered_count = cache
            .load(&entry, &stdlib_root, Some(&source_root), limits)
            .expect("rediscover bounded source pack after source addition")
            .bounded()
            .expect("rediscovered input should remain bounded")
            .files
            .len();
        assert_eq!(rediscovered_count, initial_count + 1);

        fs::remove_dir_all(root).expect("remove bounded source cache fixture tree");
    }

    #[test]
    fn daemon_keeps_large_source_packs_path_backed() {
        let limits = crate::codegen::unit::CompilationUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 100,
        };
        let path_manifest = ExplicitSourcePackPathManifest {
            files: (0..=limits.max_source_files)
                .map(|index| crate::compiler::ExplicitSourcePathFile {
                    library_id: 1,
                    path: PathBuf::from(format!("not-loaded-{index}.lani")),
                    byte_len: 1,
                    modified_unix_nanos: None,
                    line_count: None,
                })
                .collect(),
            library_dependencies: Vec::new(),
        };

        assert!(matches!(
            cached_compile_input(path_manifest, limits),
            Ok(CachedCompileInput::Bounded(_))
        ));
    }

    #[test]
    fn daemon_keeps_multiple_library_identities_path_backed() {
        let limits = crate::codegen::unit::CompilationUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 100,
        };
        let path_manifest = ExplicitSourcePackPathManifest {
            files: vec![
                crate::compiler::ExplicitSourcePathFile {
                    library_id: 0,
                    path: PathBuf::from("stdlib.lani"),
                    byte_len: 1,
                    modified_unix_nanos: None,
                    line_count: None,
                },
                crate::compiler::ExplicitSourcePathFile {
                    library_id: 1,
                    path: PathBuf::from("main.lani"),
                    byte_len: 1,
                    modified_unix_nanos: None,
                    line_count: None,
                },
            ],
            library_dependencies: Vec::new(),
        };

        assert!(matches!(
            cached_compile_input(path_manifest, limits),
            Ok(CachedCompileInput::Bounded(_))
        ));
    }
}
