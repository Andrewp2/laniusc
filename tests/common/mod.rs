#![allow(dead_code)]

pub mod sample_programs;

use std::{
    collections::HashMap,
    env,
    fmt,
    fs,
    future::Future,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Output, Stdio},
    sync::{
        Mutex,
        MutexGuard,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

use laniusc_compiler::compiler::{
    CompileError,
    compile_source_pack_to_wasm_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen_from_path,
    semantic_interface_for_source_pack_with_dependencies_with_gpu,
    semantic_interface_for_source_pack_with_gpu,
    type_check_source_pack_with_dependency_interfaces_with_gpu,
    type_check_source_pack_with_gpu,
    type_check_source_with_gpu,
    type_check_source_with_gpu_from_path,
};
use log::warn;

static TEMP_ARTIFACT_COUNTER: AtomicU64 = AtomicU64::new(0);
// libtest runs cases concurrently; start GPU timeouts after queued work gets the device.
static GPU_TEST_LOCK: Mutex<()> = Mutex::new(());
// Focused GPU behavior tests are intentionally tiny, but a cold process may
// still pay one-time shader pipeline creation before it reaches the behavior
// under test. Keep this guard above observed cold frontend/type-checker init
// while preserving an explicit timeout for genuine hangs.
const DEFAULT_GPU_TEST_TIMEOUT_MS: u64 = 60_000;
// The default codegen coverage includes small source-pack programs.
// Cold process pipeline setup can dominate the first codegen test, so use the
// same guard as focused GPU type-checking while keeping suite-style loops short.
const DEFAULT_GPU_CODEGEN_TEST_TIMEOUT_MS: u64 = 180_000;
const DEFAULT_GPU_CODEGEN_SUITE_TEST_TIMEOUT_MS: u64 = 5_000;
const DEFAULT_COMPILER_PROCESS_TEST_TIMEOUT_MS: u64 = 4_000;
const DEFAULT_PROCESS_TEST_TIMEOUT_MS: u64 = 500;
const CHILD_PROCESS_POLL_INTERVAL_MS: u64 = 2;
const TEST_TIMEOUT_EXIT_CODE: i32 = 124;

pub struct TempArtifact {
    path: PathBuf,
}

impl TempArtifact {
    pub fn new(prefix: &str, stem: &str, extension: Option<&str>) -> Self {
        Self {
            path: temp_artifact_path(prefix, stem, extension),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn write_bytes(&self, contents: impl AsRef<[u8]>) {
        fs::write(&self.path, contents).unwrap_or_else(|err| {
            panic!("write temporary artifact {}: {err}", self.path.display())
        });
    }

    pub fn write_str(&self, contents: &str) {
        self.write_bytes(contents.as_bytes());
    }
}

impl Drop for TempArtifact {
    fn drop(&mut self) {
        if env_bool_truthy("LANIUS_KEEP_TEMP_ARTIFACTS") {
            eprintln!("kept temp artifact {}", self.path.display());
            return;
        }
        match fs::remove_file(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(err) => warn!(
                "failed to remove temp artifact {}: {err}",
                self.path.display()
            ),
        }
    }
}

fn env_bool_truthy(name: &str) -> bool {
    let Ok(value) = env::var(name) else {
        return false;
    };
    matches!(
        value.as_str(),
        "1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON"
    )
}

pub fn temp_artifact_path(prefix: &str, stem: &str, extension: Option<&str>) -> PathBuf {
    let mut path = std::env::temp_dir().join(format!(
        "{}_{}_{}_{}",
        prefix,
        sanitize_path_component(stem),
        std::process::id(),
        next_temp_artifact_id()
    ));
    if let Some(extension) = extension {
        path.set_extension(extension);
    }
    path
}

pub fn assert_command_success(context: impl fmt::Display, output: &Output) {
    assert!(
        output.status.success(),
        "{context} failed with status {}\nstdout:\n{}\nstderr:\n{}",
        format_exit_status(&output.status),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

pub fn type_check_source_with_timeout(src: &str) -> Result<(), CompileError> {
    let src = src.to_owned();
    run_with_timeout("GPU type check", move || {
        pollster::block_on(type_check_source_with_gpu(&src))
    })
}

pub fn type_check_source_pack_with_timeout(sources: &[&str]) -> Result<(), CompileError> {
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    run_with_timeout("GPU source-pack type check", move || {
        pollster::block_on(type_check_source_pack_with_gpu(&sources))
    })
}

pub fn semantic_interface_with_timeout(
    library_id: u32,
    sources: &[&str],
) -> Result<laniusc_compiler::compiler::GpuSemanticInterfaceArtifact, CompileError> {
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    run_with_timeout("GPU semantic-interface export", move || {
        pollster::block_on(semantic_interface_for_source_pack_with_gpu(
            library_id, &sources,
        ))
    })
}

pub fn semantic_interface_with_dependencies_with_timeout(
    library_id: u32,
    sources: &[&str],
    dependency_interfaces: Vec<laniusc_compiler::compiler::GpuSemanticInterfaceArtifact>,
) -> Result<laniusc_compiler::compiler::GpuSemanticInterfaceArtifact, CompileError> {
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    run_with_timeout("GPU dependency semantic-interface export", move || {
        pollster::block_on(
            semantic_interface_for_source_pack_with_dependencies_with_gpu(
                library_id,
                &sources,
                &dependency_interfaces,
            ),
        )
    })
}

pub fn type_check_source_pack_with_dependencies_with_timeout(
    library_id: u32,
    sources: &[&str],
    dependency_interfaces: Vec<laniusc_compiler::compiler::GpuSemanticInterfaceArtifact>,
) -> Result<(), CompileError> {
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    run_with_timeout("GPU dependency-interface type check", move || {
        pollster::block_on(type_check_source_pack_with_dependency_interfaces_with_gpu(
            library_id,
            &sources,
            &dependency_interfaces,
        ))
    })
}

pub fn type_check_path_with_timeout(path: &Path) -> Result<(), CompileError> {
    let path = path.to_path_buf();
    run_with_timeout("GPU path type check", move || {
        pollster::block_on(type_check_source_with_gpu_from_path(&path))
    })
}

pub fn compile_source_to_wasm_with_timeout(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = src.to_owned();
    run_with_timeout_for("GPU WASM compile", gpu_codegen_test_timeout(), move || {
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(&src))
    })
}

pub fn compile_source_pack_to_wasm_with_timeout(sources: &[&str]) -> Result<Vec<u8>, CompileError> {
    let sources = sources
        .iter()
        .map(|src| (*src).to_owned())
        .collect::<Vec<_>>();
    run_with_timeout_for(
        "GPU source-pack WASM compile",
        gpu_codegen_test_timeout(),
        move || pollster::block_on(compile_source_pack_to_wasm_with_gpu_codegen(&sources)),
    )
}

pub fn compile_path_to_wasm_with_timeout(path: &Path) -> Result<Vec<u8>, CompileError> {
    let path = path.to_path_buf();
    run_with_timeout_for(
        "GPU path WASM compile",
        gpu_codegen_test_timeout(),
        move || pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(&path)),
    )
}

pub fn block_on_gpu_with_timeout<T, F>(context: &str, future: F) -> T
where
    T: Send + 'static,
    F: Future<Output = T> + Send + 'static,
{
    run_with_timeout(context, move || pollster::block_on(future))
}

pub fn run_gpu_codegen_with_timeout<T, F>(context: &str, f: F) -> T
where
    T: Send + 'static,
    F: FnOnce() -> T + Send + 'static,
{
    run_with_timeout_for(context, gpu_codegen_test_timeout(), f)
}

pub fn run_gpu_codegen_suite_with_timeout<T, F>(context: &str, f: F) -> T
where
    T: Send + 'static,
    F: FnOnce() -> T + Send + 'static,
{
    run_with_timeout_for(context, gpu_codegen_suite_test_timeout(), f)
}

pub fn command_output_with_timeout(context: impl fmt::Display, command: &mut Command) -> Output {
    let context = context.to_string();
    let (_guard, gpu_lock_wait) = gpu_test_lock();
    command_output_result_with_timeout(
        &context,
        command,
        compiler_process_test_timeout(),
        TimeoutDetails::with_gpu_lock_wait(gpu_lock_wait),
    )
    .unwrap_or_else(|err| {
        panic!("{context}: spawn command: {err}");
    })
}

pub fn codegen_command_output_with_timeout(
    context: impl fmt::Display,
    command: &mut Command,
) -> Output {
    let context = context.to_string();
    let (_guard, gpu_lock_wait) = gpu_test_lock();
    command_output_result_with_timeout(
        &context,
        command,
        gpu_codegen_test_timeout(),
        TimeoutDetails::with_gpu_lock_wait(gpu_lock_wait),
    )
    .unwrap_or_else(|err| {
        panic!("{context}: spawn command: {err}");
    })
}

pub fn short_process_output_with_timeout(
    context: impl fmt::Display,
    command: &mut Command,
) -> Output {
    let context = context.to_string();
    command_output_result_with_timeout(
        &context,
        command,
        process_test_timeout(),
        TimeoutDetails::default(),
    )
    .unwrap_or_else(|err| {
        panic!("{context}: spawn command: {err}");
    })
}

fn command_output_result_with_timeout(
    context: impl fmt::Display,
    command: &mut Command,
    timeout: Duration,
    details: TimeoutDetails,
) -> io::Result<Output> {
    let context = context.to_string();
    let mut child = match command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) => return Err(err),
    };
    let start = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_status)) => {
                return Ok(child
                    .wait_with_output()
                    .unwrap_or_else(|err| panic!("{context}: collect command output: {err}")));
            }
            Ok(None) => {}
            Err(err) => panic!("{context}: wait for command: {err}"),
        }

        if start.elapsed() >= timeout {
            if let Err(err) = child.kill() {
                warn!("{context}: failed to terminate timed-out helper process: {err}");
            }
            let output = child
                .wait_with_output()
                .unwrap_or_else(|err| panic!("{context}: collect timed-out command output: {err}"));
            exit_after_timeout(format_args!(
                "{}\nstdout:\n{}\nstderr:\n{}",
                timeout_message(&context, timeout, details),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        thread::sleep(Duration::from_millis(CHILD_PROCESS_POLL_INTERVAL_MS));
    }
}

pub fn run_with_timeout<T, F>(context: &str, f: F) -> T
where
    T: Send + 'static,
    F: FnOnce() -> T + Send + 'static,
{
    run_with_timeout_for(context, gpu_test_timeout(), f)
}

fn run_with_timeout_for<T, F>(context: &str, timeout: Duration, f: F) -> T
where
    T: Send + 'static,
    F: FnOnce() -> T + Send + 'static,
{
    let (_guard, gpu_lock_wait) = gpu_test_lock();
    let (tx, rx) = mpsc::channel();
    // GPU compiler construction reflects and validates hundreds of pipelines.
    // Rust's 2 MiB default for spawned test threads is smaller than the
    // production pipeline-initialization workers and can overflow before any
    // GPU work is submitted.
    const GPU_TEST_WORKER_STACK_BYTES: usize = 16 * 1024 * 1024;
    let handle = thread::Builder::new()
        .name("lanius-gpu-test-worker".into())
        .stack_size(GPU_TEST_WORKER_STACK_BYTES)
        .spawn(move || {
            let result = f();
            if let Err(err) = tx.send(result) {
                warn!("failed to send test result from worker thread: {err}");
            }
        })
        .expect("spawn GPU timeout worker");

    match rx.recv_timeout(timeout) {
        Ok(result) => {
            handle
                .join()
                .expect("timeout worker should not panic after sending a result");
            result
        }
        Err(mpsc::RecvTimeoutError::Timeout) => {
            exit_after_timeout(format_args!(
                "{}",
                timeout_message(context, timeout, TimeoutDetails::gpu_worker(gpu_lock_wait))
            ));
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => match handle.join() {
            Ok(()) => panic!("{context} worker exited without sending a result"),
            Err(payload) => std::panic::resume_unwind(payload),
        },
    }
}

fn gpu_test_lock() -> (MutexGuard<'static, ()>, Duration) {
    let start = Instant::now();
    let guard = GPU_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    (guard, start.elapsed())
}

fn gpu_test_timeout() -> Duration {
    env_millis("LANIUS_GPU_TEST_TIMEOUT_MS")
        .or_else(|| env_seconds("LANIUS_GPU_TEST_TIMEOUT_SECS"))
        .unwrap_or_else(|| Duration::from_millis(DEFAULT_GPU_TEST_TIMEOUT_MS))
}

fn gpu_codegen_test_timeout() -> Duration {
    env_millis("LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS")
        .or_else(|| env_millis("LANIUS_GPU_TEST_TIMEOUT_MS"))
        .or_else(|| env_seconds("LANIUS_GPU_TEST_TIMEOUT_SECS"))
        .unwrap_or_else(|| Duration::from_millis(DEFAULT_GPU_CODEGEN_TEST_TIMEOUT_MS))
}

fn gpu_codegen_suite_test_timeout() -> Duration {
    env_millis("LANIUS_GPU_CODEGEN_SUITE_TEST_TIMEOUT_MS")
        .or_else(|| env_millis("LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS"))
        .or_else(|| env_millis("LANIUS_GPU_TEST_TIMEOUT_MS"))
        .unwrap_or_else(|| Duration::from_millis(DEFAULT_GPU_CODEGEN_SUITE_TEST_TIMEOUT_MS))
}

fn compiler_process_test_timeout() -> Duration {
    env_millis("LANIUS_COMPILER_PROCESS_TEST_TIMEOUT_MS")
        .or_else(|| env_millis("LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS"))
        .or_else(|| env_millis("LANIUS_GPU_TEST_TIMEOUT_MS"))
        .unwrap_or_else(|| Duration::from_millis(DEFAULT_COMPILER_PROCESS_TEST_TIMEOUT_MS))
}

fn env_millis(name: &str) -> Option<Duration> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) => {
            warn!("{name} is unset; using caller default");
            return None;
        }
    };
    match value.parse::<u64>() {
        Ok(milliseconds) if milliseconds > 0 => Some(Duration::from_millis(milliseconds)),
        Ok(_) => {
            warn!("{name} is not positive; using caller default");
            None
        }
        Err(err) => {
            warn!("{name} is not a valid timeout millis value '{value}': {err}");
            None
        }
    }
}

fn env_seconds(name: &str) -> Option<Duration> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) => {
            warn!("{name} is unset; using caller default");
            return None;
        }
    };
    match value.parse::<u64>() {
        Ok(seconds) if seconds > 0 => Some(Duration::from_secs(seconds)),
        Ok(_) => {
            warn!("{name} is not positive; using caller default");
            None
        }
        Err(err) => {
            warn!("{name} is not a valid timeout seconds value '{value}': {err}");
            None
        }
    }
}

fn process_test_timeout() -> Duration {
    env_millis("LANIUS_PROCESS_TEST_TIMEOUT_MS")
        .unwrap_or_else(|| Duration::from_millis(DEFAULT_PROCESS_TEST_TIMEOUT_MS))
}

#[derive(Clone, Copy, Debug, Default)]
struct TimeoutDetails {
    gpu_lock_wait: Option<Duration>,
}

impl TimeoutDetails {
    fn with_gpu_lock_wait(gpu_lock_wait: Duration) -> Self {
        Self {
            gpu_lock_wait: Some(gpu_lock_wait),
        }
    }

    fn gpu_worker(gpu_lock_wait: Duration) -> Self {
        Self::with_gpu_lock_wait(gpu_lock_wait)
    }
}

fn timeout_message(context: &str, timeout: Duration, details: TimeoutDetails) -> String {
    let mut message = format!(
        "{context} timed out after {} ms after acquiring the GPU test lock; aborting this test binary to stop the timed-out worker",
        timeout.as_millis()
    );
    if let Some(wait) = details.gpu_lock_wait {
        message.push_str(&format!(
            "; waited {} ms for the GPU test lock before starting the timeout",
            wait.as_millis()
        ));
    }
    message.push_str(
        "; cold pipeline initialization can dominate the first GPU codegen test, so enable LANIUS_GPU_COMPILE_HOST_TIMING=1 before classifying this as a backend hang",
    );
    message
}

fn exit_after_timeout(args: fmt::Arguments<'_>) -> ! {
    eprintln!("{args}");
    if let Err(err) = io::stderr().flush() {
        warn!("failed to flush stderr during timeout: {err}");
    }
    immediate_process_exit(TEST_TIMEOUT_EXIT_CODE);
}

#[cfg(unix)]
fn immediate_process_exit(code: i32) -> ! {
    unsafe extern "C" {
        fn _exit(status: i32) -> !;
    }

    unsafe { _exit(code) }
}

#[cfg(not(unix))]
fn immediate_process_exit(code: i32) -> ! {
    std::process::exit(code);
}

pub fn stdout_utf8(context: impl fmt::Display, stdout: Vec<u8>) -> String {
    String::from_utf8(stdout).unwrap_or_else(|err| panic!("{context}: stdout was not UTF-8: {err}"))
}

pub fn node_available() -> bool {
    let mut command = Command::new("node");
    command.arg("--version");
    matches!(
        command_output_result_with_timeout(
            "node --version",
            &mut command,
            process_test_timeout(),
            TimeoutDetails::default(),
        ),
        Ok(output) if output.status.success()
    )
}

pub fn require_node() {
    let mut command = Command::new("node");
    command.arg("--version");
    let output = short_process_output_with_timeout("node --version", &mut command);
    assert_command_success("node --version", &output);
}

pub fn run_wasm_main_with_node(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
) -> String {
    let context = context.to_string();
    let output = run_wasm_main_with_node_output(&context, artifact_stem, wasm);
    assert_command_success(format!("{context}: node executing WASM main"), &output);
    stdout_utf8(format!("{context}: node stdout"), output.stdout)
}

pub struct WasmRunResult {
    pub stdout: String,
    pub exit_code: i32,
    pub files: HashMap<String, Vec<u8>>,
}

#[derive(serde::Deserialize, serde::Serialize)]
struct WasmVirtualFile {
    path: String,
    bytes: Vec<u8>,
}

#[derive(serde::Deserialize)]
struct WasmRunDump {
    exit_code: i32,
    files: Vec<WasmVirtualFile>,
}

pub fn run_wasm_main_with_node_and_files(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
    initial_files: &[(String, Vec<u8>)],
) -> WasmRunResult {
    let context = context.to_string();
    let dump_path = TempArtifact::new("laniusc_exec_wasm_files", artifact_stem, Some("json"));
    let output = run_wasm_main_with_node_output_with_virtual_files(
        &context,
        artifact_stem,
        wasm,
        initial_files,
        Some(dump_path.path()),
        true,
    );
    assert_command_success(format!("{context}: node executing WASM main"), &output);
    let stdout = stdout_utf8(format!("{context}: node stdout"), output.stdout);
    let dumped = fs::read(dump_path.path()).unwrap_or_else(|err| {
        panic!(
            "{context}: read WASM virtual filesystem dump {}: {err}",
            dump_path.path().display()
        )
    });
    let dump = serde_json::from_slice::<WasmRunDump>(&dumped)
        .unwrap_or_else(|err| panic!("{context}: parse WASM virtual filesystem dump: {err}"));
    let files = dump
        .files
        .into_iter()
        .map(|file| (file.path, file.bytes))
        .collect();
    WasmRunResult {
        stdout,
        exit_code: dump.exit_code,
        files,
    }
}

pub fn run_wasm_main_with_node_output(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
) -> Output {
    run_wasm_main_with_node_output_with_virtual_files(
        context,
        artifact_stem,
        wasm,
        &[],
        None,
        false,
    )
}

fn run_wasm_main_with_node_output_with_virtual_files(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
    initial_files: &[(String, Vec<u8>)],
    dump_path: Option<&Path>,
    allow_nonzero_main: bool,
) -> Output {
    let context = context.to_string();
    let wasm_path = TempArtifact::new("laniusc_exec_wasm", artifact_stem, Some("wasm"));
    wasm_path.write_bytes(wasm);

    let script = r#"
const fs = require('fs');
(async () => {
  let stdout = '';
  let instance = null;
  const laniusArgs = ['program', 'LANIUS_TEST_ENV'];
  const cwd = '/lanius/test/cwd';
  const laniusEnv = { LANIUS_TEST_ENV: 'present' };
  const envKeys = Object.keys(laniusEnv);
  const stdinBytes = Buffer.from('S', 'utf8');
  const fileStore = new Map();
  const dirStore = new Set();
  const fileHandles = new Map();
  let nextFileHandle = 3;
  let heapPtr = 1024;
  for (const file of JSON.parse(process.env.LANIUS_WASM_INITIAL_FILES || '[]')) {
    fileStore.set(file.path, Buffer.from(file.bytes));
  }
  function memory() {
    const memory = instance && instance.exports && instance.exports.memory;
    if (!memory) {
      throw new Error('missing exported memory');
    }
    return memory;
  }
  function alignUp(value, align) {
    const a = Math.max(1, align >>> 0);
    return (value + a - 1) & ~(a - 1);
  }
  function allocMemory(size, align) {
    const start = alignUp(heapPtr, align);
    const end = start + (size >>> 0);
    if (end > memory().buffer.byteLength) {
      return 0;
    }
    heapPtr = end;
    return start | 0;
  }
  function reallocMemory(ptr, oldSize, newSize, align) {
    const next = allocMemory(newSize, align);
    if (next === 0) return 0;
    const count = Math.min(oldSize >>> 0, newSize >>> 0);
    const source = new Uint8Array(memory().buffer, ptr >>> 0, count);
    new Uint8Array(memory().buffer, next >>> 0, count).set(source);
    return next | 0;
  }
  function writeBytes(ptr, len, text) {
    const bytes = Buffer.from(text, 'utf8');
    const start = ptr >>> 0;
    const count = Math.min(len >>> 0, bytes.length);
    new Uint8Array(memory().buffer, start, count).set(bytes.subarray(0, count));
    return count | 0;
  }
  function readString(ptr, len) {
    const start = ptr >>> 0;
    const count = len >>> 0;
    const bytes = new Uint8Array(memory().buffer, start, count);
    return Buffer.from(bytes).toString('utf8');
  }
  function readBytes(ptr, len) {
    const start = ptr >>> 0;
    const count = len >>> 0;
    return Buffer.from(new Uint8Array(memory().buffer, start, count));
  }
  function writeTimespec(ptr, len, seconds, nanoseconds) {
    if ((len >>> 0) < 16) return -1;
    const view = new DataView(memory().buffer);
    view.setBigInt64(ptr >>> 0, BigInt(seconds), true);
    view.setBigInt64((ptr >>> 0) + 8, BigInt(nanoseconds), true);
    return 0;
  }
  function decodeLaniusStringLiteral(ptr, len) {
    const bytes = readBytes(ptr, len);
    let out = '';
    for (let i = 0; i < bytes.length; i += 1) {
      const ch = bytes[i];
      if (ch !== 92 || i + 1 >= bytes.length) {
        out += String.fromCharCode(ch);
        continue;
      }
      const next = bytes[++i];
      if (next === 110) {
        out += '\n';
      } else if (next === 114) {
        out += '\r';
      } else if (next === 116) {
        out += '\t';
      } else if (next === 92) {
        out += '\\';
      } else if (next === 34) {
        out += '"';
      } else {
        out += String.fromCharCode(next);
      }
    }
    return out;
  }
  function openFile(path, mode) {
    if (mode === 'read' && !fileStore.has(path)) {
      return -1;
    }
    if (mode === 'write') {
      fileStore.set(path, Buffer.alloc(0));
    } else if (mode === 'append' && !fileStore.has(path)) {
      fileStore.set(path, Buffer.alloc(0));
    }
    const handle = nextFileHandle++;
    fileHandles.set(handle, { path, offset: mode === 'append' ? fileStore.get(path).length : 0, mode });
    return handle | 0;
  }
  function removeFile(path) {
    if (!fileStore.has(path)) return -1;
    fileStore.delete(path);
    return 0;
  }
  function createDir(path) {
    if (fileStore.has(path) || dirStore.has(path)) return -1;
    dirStore.add(path);
    return 0;
  }
  function removeDir(path) {
    if (!dirStore.has(path)) return -1;
    const prefix = path.endsWith('/') ? path : path + '/';
    for (const name of fileStore.keys()) if (name.startsWith(prefix)) return -1;
    for (const name of dirStore) if (name !== path && name.startsWith(prefix)) return -1;
    dirStore.delete(path);
    return 0;
  }
  function renamePath(from, to) {
    if (from === to && (fileStore.has(from) || dirStore.has(from))) return 0;
    if (fileStore.has(to) || dirStore.has(to)) return -1;
    if (fileStore.has(from)) {
      const bytes = fileStore.get(from);
      fileStore.delete(from);
      fileStore.set(to, bytes);
      for (const record of fileHandles.values()) if (record.path === from) record.path = to;
      return 0;
    }
    if (!dirStore.has(from)) return -1;
    const prefix = from.endsWith('/') ? from : from + '/';
    const replacement = to.endsWith('/') ? to : to + '/';
    const files = Array.from(fileStore.entries());
    const dirs = Array.from(dirStore);
    dirStore.delete(from);
    dirStore.add(to);
    for (const [name, bytes] of files) if (name.startsWith(prefix)) {
      fileStore.delete(name);
      fileStore.set(replacement + name.slice(prefix.length), bytes);
    }
    for (const name of dirs) if (name.startsWith(prefix)) {
      dirStore.delete(name);
      dirStore.add(replacement + name.slice(prefix.length));
    }
    for (const record of fileHandles.values()) if (record.path.startsWith(prefix)) {
      record.path = replacement + record.path.slice(prefix.length);
    }
    return 0;
  }
  function fileRead(handle, ptr, len) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return -1;
    }
    const data = fileStore.get(record.path) || Buffer.alloc(0);
    const count = Math.min(len >>> 0, Math.max(0, data.length - record.offset));
    new Uint8Array(memory().buffer, ptr >>> 0, count).set(data.subarray(record.offset, record.offset + count));
    record.offset += count;
    return count | 0;
  }
  function fileWriteBuffer(handle, bytes) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return -1;
    }
    const before = fileStore.get(record.path) || Buffer.alloc(0);
    const prefix = before.subarray(0, record.offset);
    const suffixStart = record.offset + bytes.length;
    const suffix = suffixStart < before.length ? before.subarray(suffixStart) : Buffer.alloc(0);
    fileStore.set(record.path, Buffer.concat([prefix, bytes, suffix]));
    record.offset += bytes.length;
    return bytes.length | 0;
  }
  function fileWrite(handle, ptr, len) {
    return fileWriteBuffer(handle, readBytes(ptr, len));
  }
  function fileReadI32(handle, fallback) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return fallback | 0;
    }
    const data = fileStore.get(record.path) || Buffer.alloc(0);
    let offset = record.offset;
    while (offset < data.length && data[offset] <= 32) {
      offset += 1;
    }
    const start = offset;
    if (offset < data.length && (data[offset] === 43 || data[offset] === 45)) {
      offset += 1;
    }
    const digitsStart = offset;
    while (offset < data.length && data[offset] >= 48 && data[offset] <= 57) {
      offset += 1;
    }
    if (offset === digitsStart) {
      return fallback | 0;
    }
    record.offset = offset;
    return Number.parseInt(data.subarray(start, offset).toString('utf8'), 10) | 0;
  }
  const imports = {
    env: {
      print_i64(value) {
        stdout += value.toString() + '\n';
      },
      argc() {
        return laniusArgs.length;
      },
      arg_len(index) {
        const arg = laniusArgs[index | 0];
        return typeof arg === 'string' ? Buffer.byteLength(arg, 'utf8') : -1;
      },
      arg_read(index, ptr, len) {
        const arg = laniusArgs[index | 0];
        if (typeof arg !== 'string') {
          return -1;
        }
        const memory = instance && instance.exports && instance.exports.memory;
        if (!memory) {
          throw new Error('missing exported memory');
        }
        const bytes = Buffer.from(arg, 'utf8');
        const start = ptr >>> 0;
        const count = Math.min(len >>> 0, bytes.length);
        new Uint8Array(memory.buffer, start, count).set(bytes.subarray(0, count));
        return count | 0;
      },
      exit(code) {
        throw { laniusExitCode: code | 0 };
      },
      secure_u32() {
        return 1234567;
      },
      fill_secure_bytes(ptr, len) {
        const memory = instance && instance.exports && instance.exports.memory;
        if (!memory) {
          return -1;
        }
        const start = ptr >>> 0;
        const count = len >>> 0;
        const bytes = new Uint8Array(memory.buffer, start, count);
        for (let i = 0; i < count; i += 1) {
          bytes[i] = (i * 37 + 11) & 255;
        }
        return count | 0;
      },
      unix_seconds() {
        return 1234567890;
      },
      monotonic_read(ptr, len) {
        return writeTimespec(ptr, len, 123, 456000000);
      },
      system_read(ptr, len) {
        return writeTimespec(ptr, len, 1234567890, 789000000);
      },
      sleep_ms_i32(milliseconds) {
        return (milliseconds | 0) < 0 ? -1 : 0;
      },
      current_dir_read(ptr, len) {
        return writeBytes(ptr, len, cwd);
      },
      current_dir_len() {
        return Buffer.byteLength(cwd, 'utf8');
      },
      var_count() {
        return envKeys.length;
      },
      var_key_len(index) {
        const key = envKeys[index | 0];
        return typeof key === 'string' ? Buffer.byteLength(key, 'utf8') : -1;
      },
      var_key_read(index, ptr, len) {
        const key = envKeys[index | 0];
        return typeof key === 'string' ? writeBytes(ptr, len, key) : -1;
      },
      var_len(keyPtr, keyLen) {
        const key = readString(keyPtr, keyLen);
        const value = laniusEnv[key];
        return typeof value === 'string' ? Buffer.byteLength(value, 'utf8') : -1;
      },
      var_read(keyPtr, keyLen, valuePtr, valueLen) {
        const key = readString(keyPtr, keyLen);
        const value = laniusEnv[key];
        return typeof value === 'string' ? writeBytes(valuePtr, valueLen, value) : -1;
      },
      close(handle) {
        return fileHandles.delete(handle | 0) ? 0 : -1;
      },
      read(handle, ptr, len) {
        return fileRead(handle, ptr, len);
      },
      write(handle, ptr, len) {
        return fileWrite(handle, ptr, len);
      },
      open_read(ptr, len) {
        return openFile(readString(ptr, len), 'read');
      },
      open_write(ptr, len) {
        return openFile(readString(ptr, len), 'write');
      },
      open_append(ptr, len) {
        return openFile(readString(ptr, len), 'append');
      },
      remove_file(ptr, len) {
        return removeFile(readString(ptr, len));
      },
      create_dir(ptr, len) {
        return createDir(readString(ptr, len));
      },
      remove_dir(ptr, len) {
        return removeDir(readString(ptr, len));
      },
      rename(fromPtr, fromLen, toPtr, toLen) {
        return renamePath(readString(fromPtr, fromLen), readString(toPtr, toLen));
      },
      open_read_path(ptr, len) {
        return openFile(decodeLaniusStringLiteral(ptr, len), 'read');
      },
      open_write_path(ptr, len) {
        return openFile(decodeLaniusStringLiteral(ptr, len), 'write');
      },
      write_text(handle, ptr, len) {
        return fileWriteBuffer(handle, Buffer.from(decodeLaniusStringLiteral(ptr, len), 'utf8'));
      },
      read_i32(handle, fallback) {
        return fileReadI32(handle, fallback);
      },
      write_i32(handle, value) {
        return fileWriteBuffer(handle, Buffer.from(String(value | 0), 'utf8'));
      },
      write_byte(handle, value) {
        return fileWriteBuffer(handle, Buffer.from([value & 255]));
      },
      write_newline(handle) {
        return fileWriteBuffer(handle, Buffer.from('\n', 'utf8'));
      },
      write_stderr(_ptr, len) {
        return len | 0;
      },
      read_stdin(ptr, len) {
        const count = Math.min(len >>> 0, stdinBytes.length);
        new Uint8Array(memory().buffer, ptr >>> 0, count).set(stdinBytes.subarray(0, count));
        return count | 0;
      },
      alloc(size, align) {
        return allocMemory(size, align);
      },
      realloc(ptr, oldSize, newSize, align) {
        return reallocMemory(ptr, oldSize, newSize, align);
      },
      alloc_failed(_size, _align) {
        throw { laniusExitCode: 1 };
      },
      dealloc(_ptr, _size, _align) {},
      write_stdout(ptr, len) {
        const memory = instance && instance.exports && instance.exports.memory;
        if (!memory) {
          throw new Error('missing exported memory');
        }
        const start = ptr >>> 0;
        const count = len >>> 0;
        const bytes = new Uint8Array(memory.buffer, start, count);
        stdout += Buffer.from(bytes).toString('utf8');
        return count | 0;
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  instance = module.instance;
  const main = instance.exports.main;
  if (typeof main !== 'function') {
    throw new Error('missing exported main function');
  }
  let status;
  try {
    status = main();
  } catch (err) {
    if (err && Number.isInteger(err.laniusExitCode)) {
      status = err.laniusExitCode | 0;
    } else {
      throw err;
    }
  }
  if (!Number.isInteger(status)) {
    throw new Error(`main returned non-integer ${String(status)}`);
  }
  const allowNonzeroMain = process.env.LANIUS_WASM_ALLOW_NONZERO_RETURN === '1';
  if (status !== 0 && !allowNonzeroMain) {
    console.error(`main returned ${String(status)}`);
    process.exit(1);
  }
  const dumpPath = process.env.LANIUS_WASM_FILE_DUMP;
  if (dumpPath) {
    const files = Array.from(fileStore.entries()).map(([path, bytes]) => ({
      path,
      bytes: Array.from(bytes.values())
    }));
    fs.writeFileSync(dumpPath, JSON.stringify({ exit_code: status | 0, files }));
  }
  process.stdout.write(stdout);
})().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
"#;

    let mut command = Command::new("node");
    let virtual_files = initial_files
        .iter()
        .map(|(path, bytes)| WasmVirtualFile {
            path: path.clone(),
            bytes: bytes.clone(),
        })
        .collect::<Vec<_>>();
    let virtual_files = serde_json::to_string(&virtual_files)
        .unwrap_or_else(|err| panic!("{context}: serialize WASM initial files: {err}"));
    command.arg("-e").arg(script).arg(wasm_path.path());
    command.env("LANIUS_WASM_INITIAL_FILES", virtual_files);
    if let Some(dump_path) = dump_path {
        command.env("LANIUS_WASM_FILE_DUMP", dump_path);
    }
    if allow_nonzero_main {
        command.env("LANIUS_WASM_ALLOW_NONZERO_RETURN", "1");
    }
    short_process_output_with_timeout(
        format!("{context}: run node for {}", wasm_path.path().display()),
        &mut command,
    )
}

pub fn run_wasm_main_return_with_node(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
) -> i32 {
    let context = context.to_string();
    let wasm_path = TempArtifact::new("laniusc_exec_wasm", artifact_stem, Some("wasm"));
    wasm_path.write_bytes(wasm);

    let script = r#"
const fs = require('fs');
(async () => {
  let instance = null;
  const laniusArgs = ['program', 'LANIUS_TEST_ENV'];
  const cwd = '/lanius/test/cwd';
  const laniusEnv = { LANIUS_TEST_ENV: 'present' };
  const envKeys = Object.keys(laniusEnv);
  const stdinBytes = Buffer.from('S', 'utf8');
  const fileStore = new Map();
  const dirStore = new Set();
  const fileHandles = new Map();
  let nextFileHandle = 3;
  let heapPtr = 1024;
  function memory() {
    const memory = instance && instance.exports && instance.exports.memory;
    if (!memory) {
      throw new Error('missing exported memory');
    }
    return memory;
  }
  function alignUp(value, align) {
    const a = Math.max(1, align >>> 0);
    return (value + a - 1) & ~(a - 1);
  }
  function allocMemory(size, align) {
    const start = alignUp(heapPtr, align);
    const end = start + (size >>> 0);
    if (end > memory().buffer.byteLength) {
      return 0;
    }
    heapPtr = end;
    return start | 0;
  }
  function reallocMemory(ptr, oldSize, newSize, align) {
    const next = allocMemory(newSize, align);
    if (next === 0) return 0;
    const count = Math.min(oldSize >>> 0, newSize >>> 0);
    const source = new Uint8Array(memory().buffer, ptr >>> 0, count);
    new Uint8Array(memory().buffer, next >>> 0, count).set(source);
    return next | 0;
  }
  function writeBytes(ptr, len, text) {
    const bytes = Buffer.from(text, 'utf8');
    const start = ptr >>> 0;
    const count = Math.min(len >>> 0, bytes.length);
    new Uint8Array(memory().buffer, start, count).set(bytes.subarray(0, count));
    return count | 0;
  }
  function readString(ptr, len) {
    const start = ptr >>> 0;
    const count = len >>> 0;
    const bytes = new Uint8Array(memory().buffer, start, count);
    return Buffer.from(bytes).toString('utf8');
  }
  function readBytes(ptr, len) {
    const start = ptr >>> 0;
    const count = len >>> 0;
    return Buffer.from(new Uint8Array(memory().buffer, start, count));
  }
  function writeTimespec(ptr, len, seconds, nanoseconds) {
    if ((len >>> 0) < 16) return -1;
    const view = new DataView(memory().buffer);
    view.setBigInt64(ptr >>> 0, BigInt(seconds), true);
    view.setBigInt64((ptr >>> 0) + 8, BigInt(nanoseconds), true);
    return 0;
  }
  function decodeLaniusStringLiteral(ptr, len) {
    const bytes = readBytes(ptr, len);
    let out = '';
    for (let i = 0; i < bytes.length; i += 1) {
      const ch = bytes[i];
      if (ch !== 92 || i + 1 >= bytes.length) {
        out += String.fromCharCode(ch);
        continue;
      }
      const next = bytes[++i];
      if (next === 110) {
        out += '\n';
      } else if (next === 114) {
        out += '\r';
      } else if (next === 116) {
        out += '\t';
      } else if (next === 92) {
        out += '\\';
      } else if (next === 34) {
        out += '"';
      } else {
        out += String.fromCharCode(next);
      }
    }
    return out;
  }
  function openFile(path, mode) {
    if (mode === 'read' && !fileStore.has(path)) {
      return -1;
    }
    if (mode === 'write') {
      fileStore.set(path, Buffer.alloc(0));
    } else if (mode === 'append' && !fileStore.has(path)) {
      fileStore.set(path, Buffer.alloc(0));
    }
    const handle = nextFileHandle++;
    fileHandles.set(handle, { path, offset: mode === 'append' ? fileStore.get(path).length : 0, mode });
    return handle | 0;
  }
  function removeFile(path) {
    if (!fileStore.has(path)) return -1;
    fileStore.delete(path);
    return 0;
  }
  function createDir(path) {
    if (fileStore.has(path) || dirStore.has(path)) return -1;
    dirStore.add(path);
    return 0;
  }
  function removeDir(path) {
    if (!dirStore.has(path)) return -1;
    const prefix = path.endsWith('/') ? path : path + '/';
    for (const name of fileStore.keys()) if (name.startsWith(prefix)) return -1;
    for (const name of dirStore) if (name !== path && name.startsWith(prefix)) return -1;
    dirStore.delete(path);
    return 0;
  }
  function renamePath(from, to) {
    if (from === to && (fileStore.has(from) || dirStore.has(from))) return 0;
    if (fileStore.has(to) || dirStore.has(to)) return -1;
    if (fileStore.has(from)) {
      const bytes = fileStore.get(from);
      fileStore.delete(from);
      fileStore.set(to, bytes);
      for (const record of fileHandles.values()) if (record.path === from) record.path = to;
      return 0;
    }
    if (!dirStore.has(from)) return -1;
    const prefix = from.endsWith('/') ? from : from + '/';
    const replacement = to.endsWith('/') ? to : to + '/';
    const files = Array.from(fileStore.entries());
    const dirs = Array.from(dirStore);
    dirStore.delete(from);
    dirStore.add(to);
    for (const [name, bytes] of files) if (name.startsWith(prefix)) {
      fileStore.delete(name);
      fileStore.set(replacement + name.slice(prefix.length), bytes);
    }
    for (const name of dirs) if (name.startsWith(prefix)) {
      dirStore.delete(name);
      dirStore.add(replacement + name.slice(prefix.length));
    }
    for (const record of fileHandles.values()) if (record.path.startsWith(prefix)) {
      record.path = replacement + record.path.slice(prefix.length);
    }
    return 0;
  }
  function fileRead(handle, ptr, len) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return -1;
    }
    const data = fileStore.get(record.path) || Buffer.alloc(0);
    const count = Math.min(len >>> 0, Math.max(0, data.length - record.offset));
    new Uint8Array(memory().buffer, ptr >>> 0, count).set(data.subarray(record.offset, record.offset + count));
    record.offset += count;
    return count | 0;
  }
  function fileWriteBuffer(handle, bytes) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return -1;
    }
    const before = fileStore.get(record.path) || Buffer.alloc(0);
    const prefix = before.subarray(0, record.offset);
    const suffixStart = record.offset + bytes.length;
    const suffix = suffixStart < before.length ? before.subarray(suffixStart) : Buffer.alloc(0);
    fileStore.set(record.path, Buffer.concat([prefix, bytes, suffix]));
    record.offset += bytes.length;
    return bytes.length | 0;
  }
  function fileWrite(handle, ptr, len) {
    return fileWriteBuffer(handle, readBytes(ptr, len));
  }
  function fileReadI32(handle, fallback) {
    const record = fileHandles.get(handle | 0);
    if (!record) {
      return fallback | 0;
    }
    const data = fileStore.get(record.path) || Buffer.alloc(0);
    let offset = record.offset;
    while (offset < data.length && data[offset] <= 32) {
      offset += 1;
    }
    const start = offset;
    if (offset < data.length && (data[offset] === 43 || data[offset] === 45)) {
      offset += 1;
    }
    const digitsStart = offset;
    while (offset < data.length && data[offset] >= 48 && data[offset] <= 57) {
      offset += 1;
    }
    if (offset === digitsStart) {
      return fallback | 0;
    }
    record.offset = offset;
    return Number.parseInt(data.subarray(start, offset).toString('utf8'), 10) | 0;
  }
  const imports = {
    env: {
      print_i64(_value) {},
      argc() {
        return laniusArgs.length;
      },
      arg_len(index) {
        const arg = laniusArgs[index | 0];
        return typeof arg === 'string' ? Buffer.byteLength(arg, 'utf8') : -1;
      },
      arg_read(index, ptr, len) {
        const arg = laniusArgs[index | 0];
        if (typeof arg !== 'string') {
          return -1;
        }
        const memory = instance && instance.exports && instance.exports.memory;
        if (!memory) {
          throw new Error('missing exported memory');
        }
        const bytes = Buffer.from(arg, 'utf8');
        const start = ptr >>> 0;
        const count = Math.min(len >>> 0, bytes.length);
        new Uint8Array(memory.buffer, start, count).set(bytes.subarray(0, count));
        return count | 0;
      },
      exit(code) {
        throw { laniusExitCode: code | 0 };
      },
      secure_u32() {
        return 1234567;
      },
      fill_secure_bytes(ptr, len) {
        const memory = instance && instance.exports && instance.exports.memory;
        if (!memory) {
          return -1;
        }
        const start = ptr >>> 0;
        const count = len >>> 0;
        const bytes = new Uint8Array(memory.buffer, start, count);
        for (let i = 0; i < count; i += 1) {
          bytes[i] = (i * 37 + 11) & 255;
        }
        return count | 0;
      },
      unix_seconds() {
        return 1234567890;
      },
      monotonic_read(ptr, len) {
        return writeTimespec(ptr, len, 123, 456000000);
      },
      system_read(ptr, len) {
        return writeTimespec(ptr, len, 1234567890, 789000000);
      },
      sleep_ms_i32(milliseconds) {
        return (milliseconds | 0) < 0 ? -1 : 0;
      },
      current_dir_read(ptr, len) {
        return writeBytes(ptr, len, cwd);
      },
      current_dir_len() {
        return Buffer.byteLength(cwd, 'utf8');
      },
      var_count() {
        return envKeys.length;
      },
      var_key_len(index) {
        const key = envKeys[index | 0];
        return typeof key === 'string' ? Buffer.byteLength(key, 'utf8') : -1;
      },
      var_key_read(index, ptr, len) {
        const key = envKeys[index | 0];
        return typeof key === 'string' ? writeBytes(ptr, len, key) : -1;
      },
      var_len(keyPtr, keyLen) {
        const key = readString(keyPtr, keyLen);
        const value = laniusEnv[key];
        return typeof value === 'string' ? Buffer.byteLength(value, 'utf8') : -1;
      },
      var_read(keyPtr, keyLen, valuePtr, valueLen) {
        const key = readString(keyPtr, keyLen);
        const value = laniusEnv[key];
        return typeof value === 'string' ? writeBytes(valuePtr, valueLen, value) : -1;
      },
      close(handle) {
        return fileHandles.delete(handle | 0) ? 0 : -1;
      },
      read(handle, ptr, len) {
        return fileRead(handle, ptr, len);
      },
      write(handle, ptr, len) {
        return fileWrite(handle, ptr, len);
      },
      open_read(ptr, len) {
        return openFile(readString(ptr, len), 'read');
      },
      open_write(ptr, len) {
        return openFile(readString(ptr, len), 'write');
      },
      open_append(ptr, len) {
        return openFile(readString(ptr, len), 'append');
      },
      remove_file(ptr, len) {
        return removeFile(readString(ptr, len));
      },
      create_dir(ptr, len) {
        return createDir(readString(ptr, len));
      },
      remove_dir(ptr, len) {
        return removeDir(readString(ptr, len));
      },
      rename(fromPtr, fromLen, toPtr, toLen) {
        return renamePath(readString(fromPtr, fromLen), readString(toPtr, toLen));
      },
      open_read_path(ptr, len) {
        return openFile(decodeLaniusStringLiteral(ptr, len), 'read');
      },
      open_write_path(ptr, len) {
        return openFile(decodeLaniusStringLiteral(ptr, len), 'write');
      },
      write_text(handle, ptr, len) {
        return fileWriteBuffer(handle, Buffer.from(decodeLaniusStringLiteral(ptr, len), 'utf8'));
      },
      read_i32(handle, fallback) {
        return fileReadI32(handle, fallback);
      },
      write_i32(handle, value) {
        return fileWriteBuffer(handle, Buffer.from(String(value | 0), 'utf8'));
      },
      write_byte(handle, value) {
        return fileWriteBuffer(handle, Buffer.from([value & 255]));
      },
      write_newline(handle) {
        return fileWriteBuffer(handle, Buffer.from('\n', 'utf8'));
      },
      write_stderr(_ptr, len) {
        return len | 0;
      },
      read_stdin(ptr, len) {
        const count = Math.min(len >>> 0, stdinBytes.length);
        new Uint8Array(memory().buffer, ptr >>> 0, count).set(stdinBytes.subarray(0, count));
        return count | 0;
      },
      alloc(size, align) {
        return allocMemory(size, align);
      },
      realloc(ptr, oldSize, newSize, align) {
        return reallocMemory(ptr, oldSize, newSize, align);
      },
      alloc_failed(_size, _align) {
        throw { laniusExitCode: 1 };
      },
      dealloc(_ptr, _size, _align) {},
      write_stdout(_ptr, len) {
        return len | 0;
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  instance = module.instance;
  const main = instance.exports.main;
  if (typeof main !== 'function') {
    throw new Error('missing exported main function');
  }
  let status;
  try {
    status = main();
  } catch (err) {
    if (err && Number.isInteger(err.laniusExitCode)) {
      status = err.laniusExitCode | 0;
    } else {
      throw err;
    }
  }
  if (!Number.isInteger(status)) {
    throw new Error(`main returned non-integer ${String(status)}`);
  }
  process.stdout.write(String(status));
})().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
"#;

    let mut command = Command::new("node");
    command.arg("-e").arg(script).arg(wasm_path.path());
    let output = short_process_output_with_timeout(
        format!("{context}: run node for {}", wasm_path.path().display()),
        &mut command,
    );
    assert_command_success(format!("{context}: node executing WASM main"), &output);
    stdout_utf8(format!("{context}: node stdout"), output.stdout)
        .trim()
        .parse::<i32>()
        .unwrap_or_else(|err| panic!("{context}: parse WASM main return value: {err}"))
}

#[cfg(all(unix, target_arch = "x86_64"))]
pub fn run_x86_64_elf(context: impl fmt::Display, artifact_stem: &str, elf: &[u8]) -> String {
    let context = context.to_string();
    let output = run_x86_64_elf_output(&context, artifact_stem, elf);
    assert_command_success(format!("{context}: native ELF execution"), &output);
    stdout_utf8(format!("{context}: native stdout"), output.stdout)
}

#[cfg(all(unix, target_arch = "x86_64"))]
pub fn run_x86_64_elf_output(
    context: impl fmt::Display,
    artifact_stem: &str,
    elf: &[u8],
) -> Output {
    run_x86_64_elf_output_with_args(context, artifact_stem, elf, &[])
}

#[cfg(all(unix, target_arch = "x86_64"))]
pub fn run_x86_64_elf_output_with_args(
    context: impl fmt::Display,
    artifact_stem: &str,
    elf: &[u8],
    args: &[&str],
) -> Output {
    use std::os::unix::fs::PermissionsExt;

    let context = context.to_string();
    let exe_path = TempArtifact::new("laniusc_sample_x86", artifact_stem, None);
    exe_path.write_bytes(elf);

    let mut permissions = fs::metadata(exe_path.path())
        .unwrap_or_else(|err| {
            panic!(
                "{context}: stat temporary ELF {}: {err}",
                exe_path.path().display()
            )
        })
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(exe_path.path(), permissions).unwrap_or_else(|err| {
        panic!(
            "{context}: chmod temporary ELF {}: {err}",
            exe_path.path().display()
        )
    });

    let mut command = Command::new(exe_path.path());
    command.args(args);
    short_process_output_with_timeout(
        format!("{context}: run native ELF {}", exe_path.path().display()),
        &mut command,
    )
}

fn sanitize_path_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn format_exit_status(status: &ExitStatus) -> String {
    status
        .code()
        .map(|code| code.to_string())
        .unwrap_or_else(|| "terminated by signal".to_string())
}

fn next_temp_artifact_id() -> u64 {
    TEMP_ARTIFACT_COUNTER.fetch_add(1, Ordering::Relaxed)
}
