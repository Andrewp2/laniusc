#![allow(dead_code)]

pub mod sample_programs;

use std::{
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

use laniusc::compiler::{
    CompileError,
    compile_source_pack_to_wasm_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen_from_path,
    type_check_source_pack_with_gpu,
    type_check_source_with_gpu,
    type_check_source_with_gpu_from_path,
};
use log::warn;

static TEMP_ARTIFACT_COUNTER: AtomicU64 = AtomicU64::new(0);
// libtest runs cases concurrently; start GPU timeouts after queued work gets the device.
static GPU_TEST_LOCK: Mutex<()> = Mutex::new(());
const DEFAULT_GPU_TEST_TIMEOUT_MS: u64 = 15_000;
// The default codegen coverage now includes small source-pack GPU fixtures.
// Pipeline setup can exceed a couple of seconds on cold runs, so keep this
// below the outer command watchdog while avoiding false timeout failures.
const DEFAULT_GPU_CODEGEN_TEST_TIMEOUT_MS: u64 = 30_000;
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
    let _guard = gpu_test_lock();
    command_output_result_with_timeout(&context, command, compiler_process_test_timeout())
        .unwrap_or_else(|err| {
            panic!("{context}: spawn command: {err}");
        })
}

pub fn short_process_output_with_timeout(
    context: impl fmt::Display,
    command: &mut Command,
) -> Output {
    let context = context.to_string();
    command_output_result_with_timeout(&context, command, process_test_timeout()).unwrap_or_else(
        |err| {
            panic!("{context}: spawn command: {err}");
        },
    )
}

fn command_output_result_with_timeout(
    context: impl fmt::Display,
    command: &mut Command,
    timeout: Duration,
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
                timeout_message(&context, timeout),
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
    let _guard = gpu_test_lock();
    let (tx, rx) = mpsc::channel();
    let handle = thread::spawn(move || {
        let result = f();
        if let Err(err) = tx.send(result) {
            warn!("failed to send test result from worker thread: {err}");
        }
    });

    match rx.recv_timeout(timeout) {
        Ok(result) => {
            handle
                .join()
                .expect("timeout worker should not panic after sending a result");
            result
        }
        Err(mpsc::RecvTimeoutError::Timeout) => {
            exit_after_timeout(format_args!("{}", timeout_message(context, timeout)));
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => match handle.join() {
            Ok(()) => panic!("{context} worker exited without sending a result"),
            Err(payload) => std::panic::resume_unwind(payload),
        },
    }
}

fn gpu_test_lock() -> MutexGuard<'static, ()> {
    GPU_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
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

fn timeout_message(context: &str, timeout: Duration) -> String {
    format!(
        "{context} timed out after {} ms; aborting this test binary to stop the timed-out worker",
        timeout.as_millis()
    )
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
        command_output_result_with_timeout("node --version", &mut command, process_test_timeout()),
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

pub fn run_wasm_main_with_node_output(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
) -> Output {
    let context = context.to_string();
    let wasm_path = TempArtifact::new("laniusc_exec_wasm", artifact_stem, Some("wasm"));
    wasm_path.write_bytes(wasm);

    let script = r#"
const fs = require('fs');
(async () => {
  let stdout = '';
  const imports = {
    env: {
      print_i64(value) {
        stdout += value.toString() + '\n';
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  const main = module.instance.exports.main;
  if (typeof main !== 'function') {
    throw new Error('missing exported main function');
  }
  const status = main();
  if (status !== 0) {
    console.error(`main returned ${String(status)}`);
    process.exit(1);
  }
  process.stdout.write(stdout);
})().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
"#;

    let mut command = Command::new("node");
    command.arg("-e").arg(script).arg(wasm_path.path());
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
  const imports = { env: { print_i64(_value) {} } };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  const main = module.instance.exports.main;
  if (typeof main !== 'function') {
    throw new Error('missing exported main function');
  }
  const status = main();
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
