//! Real-process advisory flock handshakes, with observed pending kernel calls.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    ffi::c_int,
    fs::{self, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::{
        fd::AsRawFd,
        unix::{fs::PermissionsExt, process::CommandExt},
    },
    path::{Path, PathBuf},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    sync::OnceLock,
    thread,
    time::{Duration, Instant},
};

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}
unsafe extern "C" {
    fn flock(fd: c_int, operation: c_int) -> c_int;
    fn poll(descriptors: *mut PollFd, count: usize, timeout: c_int) -> c_int;
    fn kill(pid: c_int, signal: c_int) -> c_int;
}
const SHARED: c_int = 1;
const EXCLUSIVE: c_int = 2;
const NONBLOCKING: c_int = 4;
const UNLOCK: c_int = 8;
const DEADLINE: Duration = Duration::from_secs(5);

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_flock_process", "directory", None);
        fs::create_dir(path.path()).unwrap();
        fs::write(path.path().join("input"), contents()).unwrap();
        Self(path)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
    fn unchanged(&self) {
        assert_eq!(fs::read(self.path().join("input")).unwrap(), contents());
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}
fn contents() -> Vec<u8> {
    (0..128)
        .map(|index| ((index * 73 + 19) % 256) as u8)
        .collect()
}

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_foundation/file_lock_process/peer.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("process flock peer", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("process flock peer: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("laniusc_flock_process", "peer", None);
        file.write_bytes(bytes);
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}

// Independent host flock control. Opening creates a different description;
// no conversion is used to infer what happens to a failed conversion's lock.
struct Control(File);
impl Control {
    fn new(directory: &Directory) -> Self {
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(directory.path().join("input"))
            .unwrap();
        file.seek(SeekFrom::Start(19)).unwrap();
        Self(file)
    }
    fn try_lock(&self, mode: c_int) -> bool {
        let result = unsafe { flock(self.0.as_raw_fd(), mode | NONBLOCKING) };
        if result == 0 {
            return true;
        }
        assert_eq!(io::Error::last_os_error().kind(), io::ErrorKind::WouldBlock);
        false
    }
    fn unlock(&self) {
        assert_eq!(unsafe { flock(self.0.as_raw_fd(), UNLOCK) }, 0);
    }
    fn unchanged(&mut self) {
        assert_eq!(self.0.stream_position().unwrap(), 19);
    }
}

fn read_exact_deadline(reader: &mut ChildStdout, bytes: &mut [u8], context: &str) {
    let deadline = Instant::now() + DEADLINE;
    let mut completed = 0;
    while completed < bytes.len() {
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .unwrap_or_else(|| panic!("pipe deadline: {context}"));
        let mut descriptor = PollFd {
            fd: reader.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        let result = unsafe {
            poll(
                &mut descriptor,
                1,
                remaining.as_millis().clamp(1, 5000) as c_int,
            )
        };
        if result < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            panic!("poll {context}: {error}");
        }
        assert!(result > 0, "pipe deadline: {context}");
        let received = match reader.read(&mut bytes[completed..]) {
            Ok(received) => received,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => panic!("read {context}: {error}"),
        };
        assert!(received > 0, "unexpected pipe EOF: {context}");
        completed += received;
    }
}

fn expect_eof_deadline<R: Read + AsRawFd>(reader: &mut R, context: &str) {
    let deadline = Instant::now() + DEADLINE;
    loop {
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .unwrap_or_else(|| panic!("EOF deadline: {context}"));
        let mut descriptor = PollFd {
            fd: reader.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        let result = unsafe {
            poll(
                &mut descriptor,
                1,
                remaining.as_millis().clamp(1, 5000) as c_int,
            )
        };
        if result < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            panic!("poll EOF {context}: {error}");
        }
        assert!(result > 0, "EOF deadline: {context}");
        let mut byte = [0u8; 1];
        match reader.read(&mut byte) {
            Ok(0) => return,
            Ok(_) => panic!("unexpected trailing output {byte:?}: {context}"),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => panic!("read EOF {context}: {error}"),
        }
    }
}

struct Peer {
    child: Child,
    input: ChildStdin,
    output: ChildStdout,
    trace: common::TempArtifact,
    pid: i32,
    descriptor: i32,
    finished: bool,
}
impl Peer {
    fn new(directory: &Directory) -> Self {
        let trace = common::TempArtifact::new("laniusc_flock_process", "trace", None);
        let mut command = Command::new("strace");
        command
            .args(["--kill-on-exit", "-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=flock,close,lseek,fcntl,mmap,mremap,munmap,brk,fsync,fdatasync",
                "-e",
                "signal=none",
            ])
            .arg(executable().path())
            .current_dir(directory.path())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        let mut child = command.spawn().unwrap();
        let input = child.stdin.take().unwrap();
        let output = child.stdout.take().unwrap();
        // Install cleanup before the first readiness wait so failed admission
        // also kills and reaps the tracer and its target process group.
        let mut peer = Self {
            child,
            input,
            output,
            trace,
            pid: 0,
            descriptor: -1,
            finished: false,
        };
        let mut ready = [0u8; 8];
        read_exact_deadline(&mut peer.output, &mut ready, "peer identity");
        peer.pid = i32::from_le_bytes(ready[..4].try_into().unwrap());
        peer.descriptor = i32::from_le_bytes(ready[4..].try_into().unwrap());
        assert!(peer.pid > 0 && peer.descriptor >= 3);
        peer.expect(b'R');
        peer
    }
    fn send(&mut self, command: u8) {
        self.input.write_all(&[command]).unwrap();
    }
    fn expect(&mut self, expected: u8) {
        let mut byte = [0u8; 1];
        read_exact_deadline(&mut self.output, &mut byte, "peer acknowledgement");
        assert_eq!(
            byte[0], expected,
            "native peer pid={} expected={expected}",
            self.pid
        );
    }
    fn command(&mut self, command: u8, expected: u8) {
        self.send(command);
        self.expect(expected);
    }
    fn begin_blocking(&mut self) {
        self.command(b'X', b'A');
        let deadline = Instant::now() + DEADLINE;
        let path = format!("/proc/{}/syscall", self.pid);
        loop {
            let last = match fs::read_to_string(&path) {
                Ok(state) => {
                    let mut words = state.split_whitespace();
                    if words.next() == Some("73") {
                        let descriptor = words
                            .next()
                            .and_then(|word| word.strip_prefix("0x"))
                            .and_then(|word| i32::from_str_radix(word, 16).ok());
                        let operation = words
                            .next()
                            .and_then(|word| word.strip_prefix("0x"))
                            .and_then(|word| i32::from_str_radix(word, 16).ok());
                        if descriptor == Some(self.descriptor) && operation == Some(EXCLUSIVE) {
                            eprintln!(
                                "flock native_pid={} pending_syscall=73 operation=LOCK_EX observed_before_release",
                                self.pid
                            );
                            return;
                        }
                    }
                    state
                }
                Err(error) => format!("{path}: {error}"),
            };
            assert!(
                Instant::now() < deadline,
                "blocking call was not observed before release: {last}"
            );
            assert!(
                self.child.try_wait().unwrap().is_none(),
                "peer exited before entering pending flock: {last}"
            );
            thread::yield_now();
        }
    }
    fn finish(mut self, command: u8, locks: &[&str], closes: usize) {
        self.command(command, command);
        let deadline = Instant::now() + DEADLINE;
        let status = loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                break status;
            }
            assert!(
                Instant::now() < deadline,
                "native peer did not exit after command {command}"
            );
            thread::yield_now();
        };
        let events = fs::read_to_string(self.trace.path()).unwrap();
        assert_eq!(status.code(), Some(0), "{events}");
        expect_eof_deadline(
            &mut self.child.stderr.take().unwrap(),
            "peer stderr after tracer exit",
        );
        expect_eof_deadline(&mut self.output, "peer stdout after tracer exit");
        for forbidden in [
            "mmap(",
            "mremap(",
            "munmap(",
            "brk(",
            "fsync(",
            "fdatasync(",
        ] {
            assert!(!events.contains(forbidden), "{events}");
        }
        let actual: Vec<&str> = events
            .lines()
            .filter(|line| line.starts_with("flock("))
            .collect();
        assert_eq!(actual.len(), locks.len(), "{events}");
        for (line, operation) in actual.iter().zip(locks) {
            assert!(line.contains(&format!(", {operation})")), "{events}");
            let result = line.rsplit_once('=').unwrap().1.trim();
            assert!(result == "0" || result.starts_with("-1 EAGAIN"), "{events}");
        }
        let actual: Vec<&str> = events
            .lines()
            .filter(|line| line.starts_with("close("))
            .collect();
        assert_eq!(actual.len(), closes, "{events}");
        assert!(actual.iter().all(|line| line.ends_with(" = 0")), "{events}");
        self.finished = true;
    }
}
impl Drop for Peer {
    fn drop(&mut self) {
        if !self.finished {
            // The tracer owns a fresh group; retire both tracer and target on
            // any assertion/deadline failure, including while flock is blocked.
            unsafe {
                kill(-(self.child.id() as i32), 9);
            }
            let _ = self.child.wait();
        }
    }
}

#[test]
fn separate_process_shared_holders_and_exclusive_nonblocking_contention() {
    let directory = Directory::new();
    let mut host = Control::new(&directory);
    let mut contender = Control::new(&directory);
    assert!(host.try_lock(SHARED));
    let mut peer = Peer::new(&directory);
    peer.command(b'S', b'K');
    assert!(!contender.try_lock(EXCLUSIVE));
    peer.command(b'U', b'K');
    peer.command(b'E', b'B');
    host.unlock();
    peer.command(b'E', b'K');
    assert!(!contender.try_lock(SHARED));
    assert!(!contender.try_lock(EXCLUSIVE));
    peer.command(b'U', b'K');
    assert!(host.try_lock(SHARED));
    host.unlock();
    peer.finish(
        b'Q',
        &[
            "LOCK_SH|LOCK_NB",
            "LOCK_UN",
            "LOCK_EX|LOCK_NB",
            "LOCK_EX|LOCK_NB",
            "LOCK_UN",
        ],
        1,
    );
    host.unchanged();
    contender.unchanged();
    directory.unchanged();
}

#[test]
fn blocking_process_lock_is_pending_until_explicit_host_unlock() {
    let directory = Directory::new();
    let mut host = Control::new(&directory);
    assert!(host.try_lock(EXCLUSIVE));
    let mut peer = Peer::new(&directory);
    peer.command(b'E', b'B');
    peer.begin_blocking();
    host.unlock();
    peer.expect(b'K');
    assert!(!host.try_lock(SHARED));
    peer.command(b'U', b'K');
    assert!(host.try_lock(EXCLUSIVE));
    host.unlock();
    peer.finish(b'Q', &["LOCK_EX|LOCK_NB", "LOCK_EX", "LOCK_UN"], 1);
    host.unchanged();
    directory.unchanged();
}

#[test]
fn last_duplicate_close_releases_for_an_already_blocked_process() {
    let directory = Directory::new();
    let mut host = Control::new(&directory);
    let mut holder = Peer::new(&directory);
    let mut waiter = Peer::new(&directory);
    holder.command(b'E', b'K');
    holder.command(b'D', b'K');
    holder.command(b'O', b'K');
    assert!(!host.try_lock(EXCLUSIVE));
    waiter.command(b'E', b'B');
    waiter.begin_blocking();
    holder.command(b'C', b'K');
    waiter.expect(b'K');
    assert!(!host.try_lock(EXCLUSIVE));
    waiter.command(b'U', b'K');
    assert!(host.try_lock(EXCLUSIVE));
    host.unlock();
    holder.finish(b'Q', &["LOCK_EX|LOCK_NB"], 2);
    waiter.finish(b'Q', &["LOCK_EX|LOCK_NB", "LOCK_EX", "LOCK_UN"], 1);
    host.unchanged();
    directory.unchanged();
}

#[test]
fn actual_process_exit_releases_description_and_wakes_a_blocked_contender() {
    let directory = Directory::new();
    let mut host = Control::new(&directory);
    let mut holder = Peer::new(&directory);
    let mut waiter = Peer::new(&directory);
    holder.command(b'E', b'K');
    holder.command(b'D', b'K');
    waiter.command(b'E', b'B');
    waiter.begin_blocking();
    // Z deliberately omits explicit owner cleanup to exercise the kernel's
    // process-exit scope, rather than claiming an automatic Lanius destructor.
    holder.finish(b'Z', &["LOCK_EX|LOCK_NB"], 0);
    waiter.expect(b'K');
    assert!(!host.try_lock(EXCLUSIVE));
    waiter.command(b'U', b'K');
    assert!(host.try_lock(EXCLUSIVE));
    host.unlock();
    waiter.finish(b'Q', &["LOCK_EX|LOCK_NB", "LOCK_EX", "LOCK_UN"], 1);
    host.unchanged();
    directory.unchanged();
}
