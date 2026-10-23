#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let file = common::TempArtifact::new("laniusc_owned_file", "executable", None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let file = common::TempArtifact::new("laniusc_owned_file", "directory", None);
        std::fs::create_dir(file.path()).unwrap();
        Self(file)
    }
    fn path(&self) -> &std::path::Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.path());
    }
}

fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("owned file execution", command)
}

fn check(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn owned_files_execute_modes_transfer_reuse_and_byte_paths() {
    let exe = fixture("owned_file");
    let directory = Directory::new();
    let output = run(Command::new(exe.path())
        .current_dir(directory.path())
        .stdin(Stdio::null()));
    check(&output, 0);
    assert!(output.stdout.is_empty());
    assert_eq!(
        std::fs::read(directory.path().join("data.bin")).unwrap(),
        [0, 128, 255, 42, 1, 2]
    );
    assert_eq!(
        std::fs::read(
            directory
                .path()
                .join(std::ffi::OsString::from_vec(vec![b'n', 255]))
        )
        .unwrap(),
        b""
    );
    assert_eq!(
        std::fs::read_dir(directory.path()).unwrap().count(),
        2,
        "NUL mutation must not create a truncated name"
    );

    let exe = fixture("owned_file_path_limit");
    let trace = common::TempArtifact::new("laniusc_owned_file", "path_limit", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=open"])
        .arg(exe.path())
        .current_dir(directory.path()));
    check(&output, 0);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "oversized path must fail before open"
    );
    let exe = fixture("path_physical_bounds");
    let output = run(&mut Command::new(exe.path()));
    assert_eq!(output.status.code(), Some(101), "{output:?}");
}

#[test]
fn owned_file_copy_preserves_errno_and_closes_on_every_failure_path() {
    let exe = fixture("owned_file_copy");
    let directory = Directory::new();
    let data: Vec<u8> = (0..2501).map(|i| (i * 37 + 11) as u8).collect();
    std::fs::write(directory.path().join("input.bin"), &data).unwrap();
    let trace = common::TempArtifact::new("laniusc_owned_file", "fault_trace", None);
    // close injection skips the syscall; it checks error propagation and no
    // retries, not actual Linux descriptor release on a delayed close error.
    for (injection, status, length, expected_closes) in [
        (None, 0, Some(data.len()), 2),
        (Some("open:error=EACCES:when=1"), 53, None, 0),
        (Some("open:error=EINTR:when=1"), 44, None, 0),
        (Some("open:error=EMFILE:when=2"), 84, None, 1),
        (Some("open:error=EAGAIN:when=2"), 71, None, 1),
        (Some("read:error=EINTR:when=2"), 0, Some(data.len()), 2),
        (Some("write:error=EINTR:when=2"), 0, Some(data.len()), 2),
        (Some("read:error=EIO:when=2"), 85, Some(1024), 2),
        (Some("read:error=EAGAIN:when=1"), 91, Some(0), 2),
        (Some("write:error=ENOSPC:when=2"), 108, Some(1024), 2),
        (Some("write:error=EIO:when=1"), 85, Some(0), 2),
        (Some("write:retval=0:when=2"), 180, Some(1024), 2),
        (Some("close:error=EIO:when=1"), 105, Some(data.len()), 2),
        (Some("close:error=EINTR:when=1"), 104, Some(data.len()), 2),
        (Some("close:error=EIO:when=2"), 125, Some(data.len()), 2),
        (Some("close:error=EINTR:when=2"), 124, Some(data.len()), 2),
    ] {
        let output_path = directory.path().join("output.bin");
        if output_path.exists() {
            std::fs::remove_file(&output_path).unwrap();
        }
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=open,close,read,write,mmap,munmap"]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command.arg(exe.path()).current_dir(directory.path()));
        check(&output, status);
        assert!(output.stdout.is_empty());
        if let Some(length) = length {
            assert_eq!(
                std::fs::read(output_path).unwrap(),
                data[..length],
                "{injection:?}"
            );
        } else {
            assert!(!output_path.exists(), "{injection:?}");
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with("close("))
                .count(),
            expected_closes,
            "{injection:?}: {events}"
        );
        assert!(
            !events.contains("mmap(") && !events.contains("munmap("),
            "file/stream operations must not allocate: {events}"
        );
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let mut handles = std::collections::BTreeSet::new();
        for line in events.lines() {
            if line.starts_with("open(") {
                if let Ok(handle) = line.rsplit(" = ").next().unwrap().parse::<i32>() {
                    assert!(handles.insert(handle), "{events}");
                }
            } else if let Some(tail) = line.strip_prefix("close(") {
                let handle: i32 = tail.split(')').next().unwrap().parse().unwrap();
                assert!(
                    handles.remove(&handle),
                    "duplicate or unrelated close: {events}"
                );
            }
        }
        assert!(handles.is_empty(), "missing close attempts: {events}");
    }
}

#[test]
fn file_concat_executes_binary_large_and_non_utf8_files_and_cleans_up() {
    let exe = executable("sample_programs/file_concat.lani");
    let directory = Directory::new();
    let first: Vec<u8> = (0..131_113).map(|i| (i * 13 + 7) as u8).collect();
    let second: Vec<u8> = (0..2051).map(|i| (i * 37 + 11) as u8).collect();
    let unusual = std::ffi::OsString::from_vec(vec![b'f', 255, b'\n', b'\\']);
    std::fs::write(directory.path().join("first"), &first).unwrap();
    std::fs::write(directory.path().join("empty"), []).unwrap();
    std::fs::write(directory.path().join(&unusual), &second).unwrap();
    let output = run(Command::new(exe.path())
        .args([
            std::ffi::OsStr::new("first"),
            std::ffi::OsStr::new("empty"),
            &unusual,
        ])
        .current_dir(directory.path()));
    check(&output, 0);
    let mut expected = first.clone();
    expected.extend_from_slice(&second);
    assert_eq!(output.stdout, expected);
    check(&run(&mut Command::new(exe.path())), 2);
    for (args, prefix) in [
        (vec!["missing"], vec![]),
        (vec!["first", "missing"], first.clone()),
        (vec![""], vec![]),
        (vec!["."], vec![]),
    ] {
        let output = run(Command::new(exe.path())
            .args(args)
            .current_dir(directory.path()));
        check(&output, 3);
        assert_eq!(output.stdout, prefix);
    }
    // Reach the binding's exact 4095-byte relative path bound with components
    // shorter than NAME_MAX. Build one component at a time to avoid an absolute
    // setup path exceeding the OS bound.
    let component = "a".repeat(200);
    let mut current = std::fs::File::open(directory.path()).unwrap();
    // Create each component through its parent descriptor so setup pathnames
    // stay bounded even when the temporary directory prefix is long.
    use std::os::fd::AsRawFd;
    let mut relative = String::new();
    for _ in 0..20 {
        let child = std::path::PathBuf::from(format!(
            "/proc/self/fd/{}/{}",
            current.as_raw_fd(),
            component
        ));
        std::fs::create_dir(&child).unwrap();
        current = std::fs::File::open(child).unwrap();
        relative.push_str(&component);
        relative.push('/');
    }
    let leaf = "b".repeat(4095 - relative.len());
    std::fs::write(
        format!("/proc/self/fd/{}/{}", current.as_raw_fd(), leaf),
        b"long path",
    )
    .unwrap();
    relative.push_str(&leaf);
    let output = run(Command::new(exe.path())
        .arg(&relative)
        .current_dir(directory.path()));
    check(&output, 0);
    assert_eq!(output.stdout, b"long path");
    let output = run(Command::new(exe.path())
        .arg(format!("{relative}x"))
        .current_dir(directory.path()));
    check(&output, 2);
    assert!(output.stdout.is_empty());

    let trace = common::TempArtifact::new("laniusc_owned_file", "concat_trace", None);
    for (injection, prefix) in [
        ("read:error=EIO:when=2", 1024),
        ("write:error=EIO:when=2", 1024),
        ("close:error=EIO:when=1", first.len()),
    ] {
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=open,close,read,write", "-e"])
            .arg(format!("inject={injection}"))
            .arg(exe.path())
            .args(["first", "empty"])
            .current_dir(directory.path()));
        check(&output, 3);
        assert_eq!(output.stdout, first[..prefix]);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{events}");
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with("open("))
                .count(),
            1,
            "must stop after failure: {events}"
        );
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with("close("))
                .count(),
            1,
            "must close on failure: {events}"
        );
    }
}
