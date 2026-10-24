//! Descriptor copy behavior against real Linux files and injected syscall faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    cell::Cell,
    ffi::{CString, c_char, c_int},
    fs::{self, File, OpenOptions},
    io::{Seek, SeekFrom},
    os::{
        fd::{AsFd, AsRawFd, FromRawFd},
        unix::{ffi::OsStrExt, fs::PermissionsExt},
    },
    path::{Path, PathBuf},
    process::Command,
};

unsafe extern "C" {
    fn open(path: *const c_char, flags: c_int, ...) -> c_int;
    fn fcntl(fd: c_int, command: c_int, ...) -> c_int;
}

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_file_copy", "directory", None);
        fs::create_dir(path.path()).unwrap();
        Self(path)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/file_copy/descriptor.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("regular-file copy", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("regular-file copy: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_file_copy", "executable", None);
    // Retain the shared strict ELF/native-transfer checker.
    output.write_bytes(bytes);
    fs::set_permissions(output.path(), fs::Permissions::from_mode(0o700)).unwrap();
    output
}

fn bytes(length: usize) -> Vec<u8> {
    (0..length).map(|index| (index * 37 + 128) as u8).collect()
}

fn raw_open(path: &Path, flags: i32) -> File {
    let name = CString::new(path.as_os_str().as_bytes()).unwrap();
    // Existing paths only: no mode argument or creation flags are needed.
    let descriptor = unsafe { open(name.as_ptr(), flags | 524288) };
    assert!(
        descriptor >= 0,
        "open {path:?}, flags {flags:#x}: {}",
        std::io::Error::last_os_error()
    );
    unsafe { File::from_raw_fd(descriptor) }
}

fn status_flags(file: &File) -> i32 {
    let flags = unsafe { fcntl(file.as_raw_fd(), 3) };
    assert!(flags >= 0, "F_GETFL: {}", std::io::Error::last_os_error());
    flags
}

fn position(file: &File) -> Option<u64> {
    file.try_clone().unwrap().stream_position().ok()
}

struct Pair {
    source: File,
    destination: File,
    source_path: PathBuf,
    destination_path: PathBuf,
    input: Vec<u8>,
    old_destination: Vec<u8>,
}
impl Pair {
    fn new(directory: &Directory, input: &[u8]) -> Self {
        let source_path = directory.path().join("input");
        let destination_path = directory.path().join("output");
        // Previous alias cases may have left a hard link or symlink here.
        let _ = fs::remove_file(&destination_path);
        fs::write(&source_path, input).unwrap();
        let old_destination = vec![167; input.len() + 37];
        fs::write(&destination_path, &old_destination).unwrap();
        let mut source = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&source_path)
            .unwrap();
        let mut destination = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&destination_path)
            .unwrap();
        source.seek(SeekFrom::Start(3)).unwrap();
        destination.seek(SeekFrom::Start(5)).unwrap();
        Self {
            source,
            destination,
            source_path,
            destination_path,
            input: input.to_vec(),
            old_destination,
        }
    }
    fn positions(&self) -> (Option<u64>, Option<u64>) {
        (position(&self.source), position(&self.destination))
    }
    fn unchanged(&self, positions: (Option<u64>, Option<u64>)) {
        assert_eq!(self.positions(), positions);
        assert_eq!(fs::read(&self.source_path).unwrap(), self.input);
        assert_eq!(
            fs::read(&self.destination_path).unwrap(),
            self.old_destination
        );
    }
    fn copied(&self, read: u64, written: usize) {
        assert_eq!(self.positions(), (Some(read), Some(written as u64)));
        assert_eq!(fs::read(&self.source_path).unwrap(), self.input);
        assert_eq!(
            fs::read(&self.destination_path).unwrap(),
            self.input[..written]
        );
    }
}

struct Outcome {
    report: (i32, u64, u64),
    events: String,
}
impl Outcome {
    fn check(&self, code: i32, read: u64, written: u64) {
        assert_eq!(self.report, (code, read, written), "{}", self.events);
    }
    fn count(&self, prefix: &str) -> usize {
        self.events
            .lines()
            .filter(|line| line.starts_with(prefix))
            .count()
    }
    fn no_mutation(&self) {
        for prefix in ["lseek(", "ftruncate(", "read(0,", "write(1,"] {
            assert_eq!(self.count(prefix), 0, "{}", self.events);
        }
    }
    fn prepared(&self) {
        let prefixes = [
            "fcntl(0,",
            "fcntl(1,",
            "statx(0,",
            "statx(1,",
            "lseek(0,",
            "lseek(1,",
            "ftruncate(1,",
        ];
        let calls: Vec<_> = self.events.lines().take(prefixes.len()).collect();
        assert_eq!(calls.len(), prefixes.len(), "{}", self.events);
        for (call, prefix) in calls.iter().zip(prefixes) {
            assert!(call.starts_with(prefix), "{}", self.events);
        }
    }
    fn probe(&self) {
        let last = self
            .events
            .lines()
            .filter(|line| line.starts_with("read(0,"))
            .last()
            .unwrap();
        assert!(last.contains(", 1)"), "{}", self.events);
    }
}

struct Harness {
    executable: common::TempArtifact,
    trace: common::TempArtifact,
    runs: Cell<usize>,
}
impl Harness {
    fn new() -> Self {
        Self {
            executable: executable(),
            trace: common::TempArtifact::new("laniusc_file_copy", "trace", None),
            runs: Cell::new(0),
        }
    }
    fn run(
        &self,
        pair: &Pair,
        mode: u64,
        limit: u64,
        capacity: u64,
        injection: Option<&str>,
    ) -> Outcome {
        self.runs.set(self.runs.get() + 1);
        let mut command = Command::new("timeout");
        command
            .args(["--kill-after=1s", "5s", "strace", "-qq", "-o"])
            .arg(self.trace.path())
            .args([
                "-e",
                "trace=fcntl,statx,lseek,ftruncate,read,write,mmap,mremap,munmap,brk,close",
                "-e",
                "signal=none",
            ]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        command
            .arg(self.executable.path())
            .args([mode.to_string(), limit.to_string(), capacity.to_string()])
            .stdin(pair.source.try_clone().unwrap())
            .stdout(pair.destination.try_clone().unwrap());
        // The common capturing helper replaces stdout. output() preserves the
        // descriptor redirection; GNU timeout supplies the explicit native bound.
        let output = command.output().expect("run bounded regular-file copy");
        let events = fs::read_to_string(self.trace.path()).unwrap();
        assert_eq!(
            output.status.code(),
            Some(0),
            "{injection:?}: {output:?}\n{events}"
        );
        assert!(output.stdout.is_empty(), "{output:?}");
        let report = parse_report(&output.stderr);
        for prefix in ["mmap(", "mremap(", "munmap(", "brk(", "close("] {
            assert!(
                !events.lines().any(|line| line.starts_with(prefix)),
                "unexpected {prefix}: {events}"
            );
        }
        assert!(
            events
                .lines()
                .filter(|line| line.starts_with("fcntl("))
                .all(|line| line.contains("F_GETFL")),
            "{events}"
        );
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with("write(2,"))
                .count(),
            1,
            "{events}"
        );
        assert_eq!(
            events.contains("INJECTED"),
            injection.is_some(),
            "{injection:?}: {events}"
        );
        Outcome { report, events }
    }
}

fn parse_report(bytes: &[u8]) -> (i32, u64, u64) {
    let text = std::str::from_utf8(bytes).unwrap();
    let fields: Vec<_> = text.split_whitespace().collect();
    assert_eq!(fields.len(), 3, "unexpected report: {text:?}");
    let values = (
        fields[0].parse().unwrap(),
        fields[1].parse().unwrap(),
        fields[2].parse().unwrap(),
    );
    assert_eq!(text, format!("{} {} {}\n", values.0, values.1, values.2));
    values
}

fn copies_and_quota(harness: &Harness, directory: &Directory) {
    let lengths = [0, 1, 7, 1024, 1025, 4097];
    let capacities = [1, 7, 7, 4096, 1, 4096];
    for mode in [0, 1] {
        for (length, capacity) in lengths.into_iter().zip(capacities) {
            let pair = Pair::new(directory, &bytes(length));
            let outcome = harness.run(&pair, mode, length as u64 + 9, capacity, None);
            outcome.check(0, length as u64, length as u64);
            outcome.prepared();
            pair.copied(length as u64, length);
        }
    }
    for (index, length) in lengths.into_iter().enumerate() {
        let pair = Pair::new(directory, &bytes(length));
        let outcome = harness.run(
            &pair,
            (index % 2) as u64,
            length as u64,
            capacities[index],
            None,
        );
        outcome.check(0, length as u64, length as u64);
        outcome.probe();
        pair.copied(length as u64, length);
    }
    for (length, quota, capacity) in [(1, 0, 1), (7, 6, 7), (1025, 1024, 4096), (4097, 4096, 7)] {
        let pair = Pair::new(directory, &bytes(length));
        let outcome = harness.run(&pair, 1, quota, capacity, None);
        outcome.check(2, quota + 1, quota);
        outcome.probe();
        pair.copied(quota + 1, quota as usize);
    }
}

fn argument_preflight(harness: &Harness, directory: &Directory) {
    for (mode, limit, code) in (2..=8)
        .map(|mode| (mode, 7, if mode == 6 || mode == 7 { 109 } else { 1 }))
        .chain([(0, 9_223_372_036_854_775_808, 1), (1, u64::MAX, 1)])
    {
        let pair = Pair::new(directory, &bytes(7));
        let positions = pair.positions();
        let outcome = harness.run(&pair, mode, limit, 7, None);
        outcome.check(code, 0, 0);
        outcome.no_mutation();
        assert_eq!(outcome.count("fcntl("), 0, "{}", outcome.events);
        assert_eq!(outcome.count("statx("), 0, "{}", outcome.events);
        pair.unchanged(positions);
    }
}

fn descriptor_policy(harness: &Harness, directory: &Directory) {
    // Linux flags are opened directly because Rust OpenOptions masks access
    // mode bits out of custom_flags. Verify the actual host flags before use.
    for (source, flags, mask) in [
        (true, 1, 3),
        (false, 0, 3),
        (true, 2097152, 2097152),
        (false, 2097152, 2097152),
        (true, 2 | 16384, 16384),
        (false, 2 | 16384, 16384),
        (true, 3, 3),
        (false, 3, 3),
        (false, 2 | 1024, 1024),
    ] {
        let mut pair = Pair::new(directory, &bytes(7));
        if source {
            pair.source = raw_open(&pair.source_path, flags);
        } else {
            pair.destination = raw_open(&pair.destination_path, flags);
        }
        let descriptor = if source {
            &pair.source
        } else {
            &pair.destination
        };
        let before_flags = status_flags(descriptor);
        assert_eq!(
            before_flags & mask,
            flags & mask,
            "host did not retain flags {flags:#x}"
        );
        let positions = pair.positions();
        let outcome = harness.run(&pair, 0, 7, 7, None);
        outcome.check(1, 0, 0);
        outcome.no_mutation();
        assert_eq!(outcome.count("statx("), 0, "{}", outcome.events);
        assert_eq!(status_flags(descriptor), before_flags);
        pair.unchanged(positions);
    }
    // Append is harmless on the read side and is not changed by copying.
    let mut pair = Pair::new(directory, &bytes(7));
    pair.source = raw_open(&pair.source_path, 2 | 1024);
    harness.run(&pair, 0, 7, 7, None).check(0, 7, 7);
    assert_ne!(status_flags(&pair.source) & 1024, 0);
    pair.copied(7, 7);

    for alias in 0..4 {
        let mut pair = Pair::new(directory, &bytes(7));
        match alias {
            0 => pair.destination = raw_open(&pair.source_path, 2),
            1 => pair.destination = pair.source.try_clone().unwrap(),
            2 | 3 => {
                fs::remove_file(&pair.destination_path).unwrap();
                if alias == 2 {
                    fs::hard_link(&pair.source_path, &pair.destination_path).unwrap();
                } else {
                    std::os::unix::fs::symlink(&pair.source_path, &pair.destination_path).unwrap();
                }
                pair.destination = raw_open(&pair.destination_path, 2);
                pair.old_destination = pair.input.clone();
            }
            _ => unreachable!(),
        }
        pair.source.seek(SeekFrom::Start(3)).unwrap();
        pair.destination.seek(SeekFrom::Start(5)).unwrap();
        let positions = pair.positions();
        let outcome = harness.run(&pair, 0, 7, 7, None);
        outcome.check(1, 0, 0);
        outcome.no_mutation();
        assert_eq!(outcome.count("statx("), 2, "{}", outcome.events);
        pair.unchanged(positions);
    }
    for kind in 0..4 {
        let mut pair = Pair::new(directory, &bytes(7));
        match kind {
            0 => pair.source = File::open("/dev/null").unwrap(),
            1 => pair.destination = OpenOptions::new().write(true).open("/dev/null").unwrap(),
            2 => {
                let (reader, _writer) = std::io::pipe().unwrap();
                pair.source = File::from(reader.as_fd().try_clone_to_owned().unwrap());
            }
            3 => {
                let (_reader, writer) = std::io::pipe().unwrap();
                pair.destination = File::from(writer.as_fd().try_clone_to_owned().unwrap());
            }
            _ => unreachable!(),
        }
        let positions = pair.positions();
        let outcome = harness.run(&pair, 0, 7, 7, None);
        outcome.check(1, 0, 0);
        outcome.no_mutation();
        assert_eq!(outcome.count("statx("), 2, "{}", outcome.events);
        pair.unchanged(positions);
    }
}

fn faults(harness: &Harness, directory: &Directory) {
    // prefix=None retains the old destination. Positive injected counts skip
    // the syscall; only oversized counts are used, solely as invalid-count tests.
    for (injection, code, read, written, source_position, destination_position, prefix, attempts) in [
        ("fcntl:error=EINTR:when=1", 3, 0, 0, 3, 5, None, 1),
        ("fcntl:error=EAGAIN:when=2", 4, 0, 0, 3, 5, None, 2),
        ("fcntl:retval=2147483648:when=1", 5, 0, 0, 3, 5, None, 1),
        ("statx:error=EIO:when=1", 105, 0, 0, 3, 5, None, 1),
        ("statx:error=EINTR:when=2", 3, 0, 0, 3, 5, None, 2),
        ("statx:retval=0:when=1", 1, 0, 0, 3, 5, None, 2),
        ("statx:retval=0:when=2", 1, 0, 0, 3, 5, None, 2),
        ("lseek:error=EINTR:when=1", 3, 0, 0, 3, 5, None, 1),
        ("lseek:error=EIO:when=2", 105, 0, 0, 0, 5, None, 2),
        ("lseek:retval=1:when=1", 5, 0, 0, 3, 5, None, 1),
        ("lseek:retval=1:when=2", 5, 0, 0, 0, 5, None, 2),
        ("ftruncate:error=EIO:when=1", 105, 0, 0, 0, 0, None, 1),
        ("ftruncate:error=EINTR:when=1", 3, 0, 0, 0, 0, None, 1),
        ("ftruncate:error=EAGAIN:when=1", 4, 0, 0, 0, 0, None, 1),
        ("ftruncate:retval=1:when=1", 5, 0, 0, 0, 0, None, 1),
        ("read:error=EIO:when=1", 105, 0, 0, 0, 0, Some(0), 1),
        ("read:error=EINTR:when=1", 3, 0, 0, 0, 0, Some(0), 1),
        ("read:error=EAGAIN:when=1", 4, 0, 0, 0, 0, Some(0), 1),
        (
            "read:error=EIO:when=2",
            105,
            1024,
            1024,
            1024,
            1024,
            Some(1024),
            2,
        ),
        (
            "read:error=EINTR:when=2",
            3,
            1024,
            1024,
            1024,
            1024,
            Some(1024),
            2,
        ),
        ("write:error=EIO:when=1", 105, 1024, 0, 1024, 0, Some(0), 1),
        ("write:error=EINTR:when=1", 3, 1024, 0, 1024, 0, Some(0), 1),
        ("write:error=EAGAIN:when=1", 4, 1024, 0, 1024, 0, Some(0), 1),
        ("write:retval=0:when=1", 6, 1024, 0, 1024, 0, Some(0), 1),
        (
            "write:error=EIO:when=2",
            105,
            2048,
            1024,
            2048,
            1024,
            Some(1024),
            2,
        ),
        (
            "write:error=EINTR:when=2",
            3,
            2048,
            1024,
            2048,
            1024,
            Some(1024),
            2,
        ),
        (
            "write:retval=0:when=2",
            6,
            2048,
            1024,
            2048,
            1024,
            Some(1024),
            2,
        ),
        ("read:retval=1025:when=1", 5, 0, 0, 0, 0, Some(0), 1),
        ("write:retval=1025:when=1", 5, 1024, 0, 1024, 0, Some(0), 1),
    ] {
        let pair = Pair::new(directory, &bytes(2500));
        let outcome = harness.run(&pair, 0, 10000, 4096, Some(injection));
        outcome.check(code, read, written);
        assert_eq!(
            pair.positions(),
            (Some(source_position), Some(destination_position)),
            "{injection}: {}",
            outcome.events
        );
        let expected = prefix.map_or(pair.old_destination.as_slice(), |length| {
            &pair.input[..length]
        });
        assert_eq!(
            fs::read(&pair.destination_path).unwrap(),
            expected,
            "{injection}: {}",
            outcome.events
        );
        assert_eq!(fs::read(&pair.source_path).unwrap(), pair.input);
        let syscall = injection.split(':').next().unwrap();
        let call_prefix = if syscall == "write" {
            "write(1,".to_owned()
        } else {
            format!("{syscall}(")
        };
        assert_eq!(
            outcome.count(&call_prefix),
            attempts,
            "{injection}: {}",
            outcome.events
        );
        if prefix.is_none() {
            assert_eq!(outcome.count("read(0,"), 0, "{}", outcome.events);
        }
        if ["fcntl", "statx", "lseek"].contains(&syscall) {
            assert_eq!(outcome.count("ftruncate("), 0, "{}", outcome.events);
        }
    }
    for (injection, code) in [
        ("read:error=EIO:when=2", 105),
        ("read:error=EINTR:when=2", 3),
        ("read:error=EAGAIN:when=2", 4),
        ("read:retval=2:when=2", 5),
    ] {
        let pair = Pair::new(directory, &bytes(1024));
        let outcome = harness.run(&pair, 1, 1024, 4096, Some(injection));
        outcome.check(code, 1024, 1024);
        outcome.probe();
        assert_eq!(outcome.count("read(0,"), 2, "{}", outcome.events);
        assert_eq!(outcome.count("write(1,"), 1, "{}", outcome.events);
        pair.copied(1024, 1024);
    }
}

fn real_short_write_and_proc(harness: &Harness, directory: &Directory) {
    let pair = Pair::new(directory, &bytes(7));
    // This limit causes a real three-byte kernel write followed by EFBIG.
    // Python only sets OS policy and execs the already compiled fixture.
    // Its startup is deliberately outside the no-allocation syscall trace.
    let setup = "import os,resource,signal,sys; resource.setrlimit(resource.RLIMIT_FSIZE,(3,3)); signal.signal(signal.SIGXFSZ,signal.SIG_IGN); os.execv(sys.argv[1],sys.argv[1:])";
    let output = Command::new("timeout")
        .args(["--kill-after=1s", "5s", "python3", "-c", setup])
        .arg(harness.executable.path())
        .args(["0", "7", "7"])
        .stdin(pair.source.try_clone().unwrap())
        .stdout(pair.destination.try_clone().unwrap())
        .output()
        .expect("real short regular-file write");
    harness.runs.set(harness.runs.get() + 1);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert_eq!(parse_report(&output.stderr), (127, 7, 3));
    pair.copied(7, 3);

    let oracle = fs::read("/proc/version").unwrap();
    assert!(!oracle.is_empty());
    let mut pair = Pair::new(directory, &oracle);
    pair.source = File::open("/proc/version").unwrap();
    assert!(pair.source.metadata().unwrap().is_file());
    assert_eq!(pair.source.metadata().unwrap().len(), 0);
    let outcome = harness.run(&pair, 1, 65536, 7, None);
    outcome.check(0, oracle.len() as u64, oracle.len() as u64);
    assert_eq!(fs::read(&pair.destination_path).unwrap(), oracle);
    assert_eq!(position(&pair.source), Some(oracle.len() as u64));
    assert_eq!(position(&pair.destination), Some(oracle.len() as u64));
}

#[test]
fn regular_file_copy_preserves_bounds_identity_and_acknowledged_progress() {
    let harness = Harness::new();
    let directory = Directory::new();
    copies_and_quota(&harness, &directory);
    argument_preflight(&harness, &directory);
    descriptor_policy(&harness, &directory);
    faults(&harness, &directory);
    real_short_write_and_proc(&harness, &directory);
    // One fixture compilation, reused across every native execution.
    assert_eq!(harness.runs.get(), 84);
}
