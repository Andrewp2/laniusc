#[cfg(unix)]
use std::os::unix::net::UnixListener;
use std::{
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
    compiler::{ExplicitSourcePack, GpuCompiler, GpuCompilerBackends, load_entry_with_stdlib},
    gpu::device,
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
    source_pack: ExplicitSourcePack,
    file_stamps: Vec<SourceFileStamp>,
}

#[derive(Default)]
struct SourcePackCache {
    entry: Option<CachedSourcePack>,
    transient: Option<ExplicitSourcePack>,
}

impl SourcePackCache {
    fn load<'a>(
        &'a mut self,
        input: &Path,
        stdlib_root: &Path,
    ) -> Result<&'a ExplicitSourcePack, crate::compiler::CompileError> {
        let cache_hit = self.entry.as_ref().is_some_and(|entry| {
            entry.input == input
                && entry.stdlib_root == stdlib_root
                && file_stamps_match(&entry.file_stamps)
        });
        if cache_hit {
            return Ok(&self
                .entry
                .as_ref()
                .expect("source-pack cache hit lost its entry")
                .source_pack);
        }

        self.entry = None;
        self.transient = None;

        let source_pack = load_entry_with_stdlib(input, stdlib_root)?;
        if let Some(file_stamps) = source_file_stamps(&source_pack) {
            self.entry = Some(CachedSourcePack {
                input: input.to_path_buf(),
                stdlib_root: stdlib_root.to_path_buf(),
                source_pack,
                file_stamps,
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
}

fn source_file_stamps(source_pack: &ExplicitSourcePack) -> Option<Vec<SourceFileStamp>> {
    source_pack
        .source_paths
        .iter()
        .map(|path| source_file_stamp(path.as_deref()?))
        .collect()
}

fn source_file_stamp(path: &Path) -> Option<SourceFileStamp> {
    let metadata = fs::metadata(path).ok()?;
    Some(SourceFileStamp {
        path: path.to_path_buf(),
        len: metadata.len(),
        modified: metadata.modified().ok()?,
    })
}

fn file_stamps_match(stamps: &[SourceFileStamp]) -> bool {
    stamps
        .iter()
        .all(|expected| source_file_stamp(&expected.path).as_ref() == Some(expected))
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
        GpuCompiler::new_with_device_and_backends(
            device::global(),
            options.backend.compiler_backends(),
        )
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
            let trimmed = compiler.release_resident_job_buffers().await;
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
                    "x86_pooled_buffers_released": trimmed.x86_pooled_buffer_count,
                    "x86_pooled_buffer_bytes_released": trimmed.x86_pooled_buffer_bytes,
                    "resident_set_bytes": resident_set_bytes(),
                    "wgpu_resources": wgpu_resource_metrics(),
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
                }),
            )?;
            continue;
        }
        if request.command != "compile" {
            write_response(
                &mut output,
                &protocol_error(
                    request.id,
                    "command must be compile, trim, status, or shutdown",
                ),
            )?;
            continue;
        }
        // A compilation is active rather than idle. Cancel the previous idle
        // deadline before it can contend for the resident pipeline lock.
        reaper.disarm();
        let response = compile_request(&compiler, options, &mut source_pack_cache, request).await;
        write_response(&mut output, &response)?;
        reaper.arm();
    }
    crate::gpu::trace::flush();
    device::persist_pipeline_cache();
    Ok(())
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

    let load_started = Instant::now();
    let source_pack = match source_pack_cache.load(&input, &stdlib_root) {
        Ok(source_pack) => source_pack,
        Err(err) => return compile_error_response(id, started, err),
    };
    let load_ms = load_started.elapsed().as_secs_f64() * 1000.0;
    let compile_started = Instant::now();
    let emitted = match emit.as_str() {
        "wasm" => {
            compiler
                .compile_source_pack_manifest_to_wasm(source_pack)
                .await
        }
        "x86_64" => {
            compiler
                .compile_source_pack_manifest_to_x86_64(source_pack)
                .await
        }
        _ => unreachable!("backend support check accepted an unknown target"),
    };
    let compile_ms = compile_started.elapsed().as_secs_f64() * 1000.0;
    let bytes = match emitted {
        Ok(bytes) => bytes,
        Err(err) => return compile_error_response(id, started, err),
    };
    let write_started = Instant::now();
    if let Err(err) = write_artifact(&output, &bytes, &emit) {
        return job_error(id, started, err);
    }
    let write_ms = write_started.elapsed().as_secs_f64() * 1000.0;
    json!({
        "schema": DAEMON_SCHEMA,
        "id": id,
        "ok": true,
        "emit": emit,
        "input": input,
        "output": output,
        "output_bytes": bytes.len(),
        "load_ms": load_ms,
        "compile_ms": compile_ms,
        "write_ms": write_ms,
        "elapsed_ms": started.elapsed().as_secs_f64() * 1000.0,
        "resident_set_bytes": resident_set_bytes(),
        "tracked_gpu_buffers": tracked_gpu_buffer_metrics(),
        "wgpu_resources": wgpu_resource_metrics(),
    })
}

fn tracked_gpu_buffer_metrics() -> Value {
    let stats = crate::gpu::buffers::tracked_buffer_allocation_stats();
    json!({
        "allocations": stats.allocations,
        "bytes": stats.bytes,
        "scope": "live LaniusBuffer allocations; raw wgpu buffers are excluded",
    })
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
        let source_pack = ExplicitSourcePack::new(vec!["fn main() {}\n".into()], vec![1])
            .and_then(|pack| pack.with_source_paths(vec![Some(path.clone())]))
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
        let first = cache
            .load(&entry, &stdlib_root)
            .expect("load initial cached source pack");
        assert!(
            first
                .sources
                .iter()
                .any(|source| source.contains("return;"))
        );

        fs::write(&entry, "fn main() { print(17); return; }\n")
            .expect("change cached entry fixture");
        let second = cache
            .load(&entry, &stdlib_root)
            .expect("reload changed source pack");
        assert!(
            second
                .sources
                .iter()
                .any(|source| source.contains("print(17)"))
        );

        fs::remove_dir_all(root).expect("remove source cache fixture tree");
    }
}
