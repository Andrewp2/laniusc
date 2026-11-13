//! Hands a one-shot compile to the resident compiler that every process of
//! this build shares.
//!
//! `laniusc --emit x86_64 --stdlib-root DIR -o OUT FILE` connects to a daemon
//! on a socket named after this build and target. When none answers, it
//! starts `laniusc daemon --shared` detached. That daemon stays for later
//! compiles, from this process tree or any other, and exits when it has been
//! idle for some minutes or when the executable is rebuilt. Jobs from every
//! client run one at a time in the order they arrive.
//!
//! The compile runs in this process instead when:
//! - the request is not one entry file with `--stdlib-root` and `-o`, or it
//!   is `check`, a package build or a source-pack command;
//! - `--no-daemon` or `LANIUS_DAEMON=0` was given;
//! - `LANIUS_TRACE`, `LANIUS_REPORT`, `LANIUS_DUMP` or another diagnostic
//!   option is set, because that output comes from the compiling process;
//! - the kernels on disk are not the ones this executable was built with;
//! - the daemon cannot be reached or started, or answers anything other
//!   than success or a compile diagnostic.
//!
//! A compile therefore never needs a daemon in order to succeed.
//!
//! A native link runs the C compiler driver in the daemon, with the
//! environment of the process that started the daemon.

use std::{
    fs::{self, DirBuilder, OpenOptions},
    io::{BufRead, BufReader, Write},
    os::unix::{fs::DirBuilderExt, net::UnixStream, process::CommandExt},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

use serde_json::{Value, json};

use super::{
    args::CompileRequest,
    common::DiagnosticFormat,
    daemon::{DAEMON_SCHEMA, RENDERED_DIAGNOSTICS_CAPABILITY, WORKING_DIRECTORY_CAPABILITY},
    dispatch::Completion,
};
use crate::compiler::NativeLinkOptions;

/// How long a client waits for a daemon it started to accept a connection.
/// The daemon listens before it creates its GPU device, so this covers
/// process start only.
const CONNECT_LIMIT: Duration = Duration::from_secs(10);
const CONNECT_POLL: Duration = Duration::from_millis(5);

/// Linux allows 108 bytes in a socket path and macOS 104.
const MAX_SOCKET_PATH_BYTES: usize = 100;

const MAX_LOG_BYTES: u64 = 1024 * 1024;

/// Changes when the way a client finds or starts its daemon changes, so that
/// builds on either side of the change do not share a socket.
const SHARED_PROTOCOL: u64 = 1;

/// Runs `request` in the shared daemon. Returns `None` when the compile has
/// to run in this process.
pub(super) fn compile(request: &CompileRequest, format: DiagnosticFormat) -> Option<Completion> {
    let job = Job::from_request(request, format)?;
    let executable = std::env::current_exe().ok()?;
    let socket = socket_path(&executable, &job.emit)?;
    // A daemon that reaches its idle limit while this client connects closes
    // the connection without a response. The second attempt starts a new one.
    for _ in 0..2 {
        let stream = connect(&socket, &executable, &job.emit)?;
        match job.run(&stream) {
            Attempt::Done(completion) => return Some(completion),
            Attempt::Unanswered => {}
            Attempt::Declined => return None,
        }
    }
    None
}

/// One compile request line and the target it compiles for.
struct Job {
    line: String,
    emit: String,
}

enum Attempt {
    Done(Completion),
    /// The connection closed before a response arrived.
    Unanswered,
    /// The daemon answered something this client cannot report.
    Declined,
}

impl Job {
    fn from_request(request: &CompileRequest, format: DiagnosticFormat) -> Option<Self> {
        let expressible = request.shared_daemon
            && !request.check_only
            && !request.uses_source_pack
            && request.stdlib_paths.is_empty()
            && request.package_manifest.is_none()
            && request.package_lockfile.is_none()
            && request.inputs.len() == 1
            && matches!(request.emit.as_str(), "x86_64" | "wasm");
        if !expressible
            || !crate::options::get().shared_daemon
            || crate::options::environment_asks_for_diagnostics()
            || crate::shader_artifacts::kernel_pairing_problem().is_some()
        {
            return None;
        }
        // A path that is not UTF-8 has no JSON form.
        let texts = |paths: &[PathBuf]| -> Option<Vec<String>> {
            paths.iter().map(|path| Some(path.to_str()?.to_owned())).collect()
        };
        let mut line = json!({
            "id": "cli",
            "command": "compile",
            "emit": request.emit,
            "input": request.inputs[0].to_str()?,
            "output": request.output.as_ref()?.to_str()?,
            "stdlib_root": request.stdlib_root.as_ref()?.to_str()?,
            "source_roots": texts(&request.source_roots)?,
            "working_directory": std::env::current_dir().ok()?.to_str()?,
            "diagnostic_format": format.name(),
        });
        if let Some(native) = &request.native_link {
            let defaults = NativeLinkOptions::default();
            if native.timeout != defaults.timeout
                || native.max_output_bytes != defaults.max_output_bytes
            {
                return None;
            }
            line["native_link"] = true.into();
            line["native_libraries"] = json!(native.libraries);
            line["native_objects"] = json!(texts(&native.objects)?);
            line["native_library_paths"] = json!(texts(&native.library_paths)?);
            if let Some(linker) = &native.linker {
                line["native_linker"] = linker.to_str()?.into();
            }
        }
        let mut line = line.to_string();
        line.push('\n');
        Some(Self {
            line,
            emit: request.emit.clone(),
        })
    }

    fn run(&self, stream: &UnixStream) -> Attempt {
        let mut responses = BufReader::new(stream);
        let Some(ready) = read_json_line(&mut responses) else {
            return Attempt::Unanswered;
        };
        let has = |capability: &str| {
            ready["capabilities"]
                .as_array()
                .is_some_and(|list| list.iter().any(|name| name == capability))
        };
        if ready["schema"] != DAEMON_SCHEMA
            || !has(RENDERED_DIAGNOSTICS_CAPABILITY)
            || !has(WORKING_DIRECTORY_CAPABILITY)
        {
            return Attempt::Declined;
        }
        let mut requests = stream;
        if requests.write_all(self.line.as_bytes()).is_err() {
            return Attempt::Unanswered;
        }
        let Some(response) = read_json_line(&mut responses) else {
            return Attempt::Unanswered;
        };
        if response["ok"] == true {
            return Attempt::Done(Completion::Success);
        }
        match response["rendered_diagnostic"].as_str() {
            Some(rendered) => {
                eprintln!("{rendered}");
                Attempt::Done(Completion::ReportedFailure)
            }
            None => Attempt::Declined,
        }
    }
}

fn read_json_line(input: &mut impl BufRead) -> Option<Value> {
    let mut line = String::new();
    if input.read_line(&mut line).ok()? == 0 {
        return None;
    }
    serde_json::from_str(&line).ok()
}

/// The socket of the daemon that serves `emit` for this build. Two builds
/// never share a name: it covers the executable's path, length and
/// modification time and the digest of the kernels it was built with. It
/// also covers the device options of this process, which a daemon takes from
/// the environment of the client that starts it.
fn socket_path(executable: &Path, emit: &str) -> Option<PathBuf> {
    let metadata = fs::metadata(executable).ok()?;
    let modified = metadata
        .modified()
        .ok()?
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_nanos();
    // An identity, not a security boundary: the directory is private.
    let mut identity = Fnv1a::default();
    identity.write(executable.as_os_str().as_encoded_bytes());
    identity.write(&metadata.len().to_le_bytes());
    identity.write(&modified.to_le_bytes());
    identity.write(crate::shader_artifacts::built_kernel_digest().as_bytes());
    identity.write(&crate::options::device_environment());
    identity.write(&SHARED_PROTOCOL.to_le_bytes());
    let path = socket_directory()?.join(format!("{:016x}-{emit}.sock", identity.0));
    (path.as_os_str().len() <= MAX_SOCKET_PATH_BYTES).then_some(path)
}

/// A directory only this user can enter: the user's runtime directory, or
/// the cache directory under the home directory.
fn socket_directory() -> Option<PathBuf> {
    let candidates = [
        std::env::var_os("XDG_RUNTIME_DIR")
            .filter(|root| !root.is_empty())
            .map(|root| PathBuf::from(root).join("laniusc-daemons")),
        std::env::var_os("HOME")
            .filter(|home| !home.is_empty())
            .map(|home| PathBuf::from(home).join(".cache/laniusc/daemons")),
    ];
    candidates.into_iter().flatten().find(|directory| {
        directory.is_absolute()
            && DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(directory)
                .is_ok()
    })
}

struct Fnv1a(u64);

impl Default for Fnv1a {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Fnv1a {
    fn write(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.0 = (self.0 ^ u64::from(*byte)).wrapping_mul(0x0000_0100_0000_01b3);
        }
    }
}

/// Connects to the daemon on `socket`, starting one when none answers.
fn connect(socket: &Path, executable: &Path, emit: &str) -> Option<UnixStream> {
    if let Ok(stream) = UnixStream::connect(socket) {
        return Some(stream);
    }
    // Under systemd the daemon gets a scope of its own. Without one it stays
    // in the control group of this process, and whatever stops that group
    // when this command ends stops the daemon too.
    let mut launchers = [Launcher::SystemdScope, Launcher::Direct].into_iter();
    let mut child = launchers.find_map(|launcher| launcher.start(socket, executable, emit))?;
    let deadline = Instant::now() + CONNECT_LIMIT;
    loop {
        if let Ok(stream) = UnixStream::connect(socket) {
            return Some(stream);
        }
        // A daemon that ends with status 0 found another one holding the
        // socket's lock. That one is about to listen.
        if matches!(child.try_wait(), Ok(Some(status)) if !status.success()) {
            child = launchers.find_map(|launcher| launcher.start(socket, executable, emit))?;
        }
        if Instant::now() >= deadline {
            return None;
        }
        thread::sleep(CONNECT_POLL);
    }
}

#[derive(Clone, Copy)]
enum Launcher {
    SystemdScope,
    Direct,
}

impl Launcher {
    fn start(self, socket: &Path, executable: &Path, emit: &str) -> Option<Child> {
        let mut command = match self {
            Self::SystemdScope => {
                let mut command = Command::new("systemd-run");
                let unit = socket.file_stem()?.to_str()?;
                command
                    .args(["--user", "--scope", "--quiet", "--collect"])
                    .arg(format!("--unit=laniusc-daemon-{unit}-{}", std::process::id()))
                    .arg("--")
                    .arg(executable);
                command
            }
            Self::Direct => Command::new(executable),
        };
        // The log holds what the daemons on this socket wrote to stderr.
        // A daemon that is running may be writing to it, so it is appended
        // to and only emptied by a start that finds it large.
        let log_path = socket.with_extension("log");
        if fs::metadata(&log_path).is_ok_and(|log| log.len() > MAX_LOG_BYTES) {
            let _ = fs::remove_file(&log_path);
        }
        let log = OpenOptions::new().create(true).append(true).open(&log_path).ok()?;
        command
            .args(["daemon", "--shared", "--backend", emit, "--unix-socket"])
            .arg(socket)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(log)
            // Its own process group: a signal sent to this command's group,
            // such as an interrupt from the terminal, does not reach it.
            .process_group(0)
            .spawn()
            .ok()
    }
}
