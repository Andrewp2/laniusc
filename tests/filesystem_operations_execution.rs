#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    ffi::{OsStr, OsString},
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
};

fn fixture(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = format!("tests/fixtures/stdlib_foundation/filesystem_operations_{name}.lani");
    let entry = root.join(&path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(&path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let artifact = common::TempArtifact::new("laniusc_filesystem_operations", name, None);
    artifact.write_bytes(&bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let artifact =
            common::TempArtifact::new("laniusc_filesystem_operations", "directory", None);
        std::fs::create_dir(artifact.path()).unwrap();
        Self(artifact)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.path());
    }
}

fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("checked filesystem mutations", command)
}
fn check(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
fn operation(exe: &Path, directory: &Path, args: &[&OsStr], status: i32) {
    check(
        &run(Command::new(exe).args(args).current_dir(directory)),
        status,
    );
}
fn normal(exe: &Path, directory: &Path, args: &[&str], status: i32) {
    let args: Vec<&OsStr> = args.iter().map(OsStr::new).collect();
    operation(exe, directory, &args, status);
}

#[test]
fn checked_mutations_execute_real_changes_and_preserve_linux_errors() {
    let exe = fixture("command");
    let directory = Directory::new();
    let path = directory.path();
    normal(exe.path(), path, &["m", "directory"], 0);
    assert!(path.join("directory").is_dir());
    normal(exe.path(), path, &["m", "directory"], 17);
    normal(exe.path(), path, &["m", "absent/child"], 2);
    let too_long_component = "a".repeat(256);
    normal(exe.path(), path, &["m", &too_long_component], 36);
    let absolute = path.join("absolute");
    operation(
        exe.path(),
        path,
        &[OsStr::new("m"), absolute.as_os_str()],
        0,
    );
    assert!(absolute.is_dir());
    operation(
        exe.path(),
        path,
        &[OsStr::new("d"), absolute.as_os_str()],
        0,
    );
    // Set only the child process's umask, using positional shell arguments so
    // the executable path is never interpolated into shell source.
    check(
        &run(Command::new("sh")
            .args(["-c", "umask 027; exec \"$1\" m permissions", "sh"])
            .arg(exe.path())
            .current_dir(path)),
        0,
    );
    assert_eq!(
        std::fs::metadata(path.join("permissions"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o750
    );
    std::fs::write(path.join("directory/child"), b"kept").unwrap();
    normal(exe.path(), path, &["d", "directory"], 39);
    normal(exe.path(), path, &["u", "directory"], 21);
    normal(exe.path(), path, &["d", "directory/child"], 20);
    normal(exe.path(), path, &["u", "directory/child"], 0);
    normal(exe.path(), path, &["d", "directory"], 0);
    assert!(!path.join("directory").exists());
    for op in ["m", "d", "u"] {
        normal(exe.path(), path, &[op, ""], 2);
    }
    normal(exe.path(), path, &["r", "", "other"], 2);
    normal(exe.path(), path, &["r", "missing", "other"], 2);
    std::fs::write(path.join("source"), b"source\0\xff").unwrap();
    std::fs::write(path.join("destination"), b"old").unwrap();
    normal(exe.path(), path, &["r", "source", "destination"], 0);
    assert!(!path.join("source").exists());
    assert_eq!(
        std::fs::read(path.join("destination")).unwrap(),
        b"source\0\xff"
    );
    normal(exe.path(), path, &["r", "destination", "destination"], 0);
    normal(exe.path(), path, &["m", "directory"], 0);
    normal(exe.path(), path, &["r", "destination", "directory"], 21);
    normal(exe.path(), path, &["r", "directory", "destination"], 20);
    assert_eq!(
        std::fs::read(path.join("destination")).unwrap(),
        b"source\0\xff"
    );
    normal(exe.path(), path, &["m", "other"], 0);
    std::fs::write(path.join("other/child"), b"keep").unwrap();
    normal(exe.path(), path, &["r", "directory", "other"], 39);
    assert!(path.join("directory").is_dir());
    normal(exe.path(), path, &["u", "other/child"], 0);
    normal(exe.path(), path, &["r", "directory", "other"], 0);
    assert!(!path.join("directory").exists() && path.join("other").is_dir());
    normal(exe.path(), path, &["d", "other"], 0);
    normal(exe.path(), path, &["m", "trailing/"], 0);
    normal(exe.path(), path, &["d", "trailing/"], 0);

    let raw = OsString::from_vec(vec![b'n', 255, b'\n', b'\\']);
    let moved = OsString::from_vec(vec![b'm', 128, b'\t']);
    operation(exe.path(), path, &[OsStr::new("m"), &raw], 0);
    assert!(path.join(&raw).is_dir());
    operation(exe.path(), path, &[OsStr::new("r"), &raw, &moved], 0);
    assert!(!path.join(&raw).exists() && path.join(&moved).is_dir());
    operation(exe.path(), path, &[OsStr::new("d"), &moved], 0);
    std::fs::write(path.join(&raw), b"raw file").unwrap();
    operation(exe.path(), path, &[OsStr::new("r"), &raw, &moved], 0);
    assert_eq!(std::fs::read(path.join(&moved)).unwrap(), b"raw file");
    operation(exe.path(), path, &[OsStr::new("u"), &moved], 0);

    std::os::unix::fs::symlink("destination", path.join("link")).unwrap();
    normal(exe.path(), path, &["d", "link"], 20);
    normal(exe.path(), path, &["r", "link", "moved_link"], 0);
    assert_eq!(
        std::fs::read_link(path.join("moved_link")).unwrap(),
        Path::new("destination")
    );
    normal(exe.path(), path, &["u", "moved_link"], 0);
    assert_eq!(
        std::fs::read(path.join("destination")).unwrap(),
        b"source\0\xff"
    );
    std::fs::create_dir(path.join("target")).unwrap();
    std::os::unix::fs::symlink("target", path.join("prefix_link")).unwrap();
    normal(exe.path(), path, &["m", "prefix_link/child"], 0);
    assert!(path.join("target/child").is_dir());
}

#[test]
fn mutations_accept_strided_subviews_and_reject_invalid_paths_before_syscalls() {
    let directory = Directory::new();
    let trace = common::TempArtifact::new("laniusc_filesystem_operations", "views_trace", None);
    let exe = fixture("views");
    check(
        &run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mkdir,rmdir,unlink,rename,mmap,munmap"])
            .arg(exe.path())
            .current_dir(directory.path())),
        0,
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "{events}"
    );
    assert_eq!(events.lines().count(), 5, "{events}");
    assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);

    let exe = fixture("invalid");
    check(
        &run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mkdir,rmdir,unlink,rename,mmap,munmap"])
            .arg(exe.path())
            .current_dir(directory.path())),
        0,
    );
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "invalid paths must not reach a host mutation"
    );
    assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
}

#[test]
fn mutations_propagate_host_failures_without_retries_or_fallback_changes() {
    let exe = fixture("command");
    let directory = Directory::new();
    let trace = common::TempArtifact::new("laniusc_filesystem_operations", "failure_trace", None);
    std::fs::create_dir(directory.path().join("directory")).unwrap();
    std::fs::write(directory.path().join("file"), b"kept").unwrap();
    std::fs::write(directory.path().join("destination"), b"destination kept").unwrap();
    for (syscall, args) in [
        ("mkdir", vec!["m", "new"]),
        ("rmdir", vec!["d", "directory"]),
        ("unlink", vec!["u", "file"]),
        ("rename", vec!["r", "file", "destination"]),
    ] {
        for (error, code) in [
            ("EACCES", 13),
            ("EINTR", 4),
            ("EAGAIN", 11),
            ("EIO", 5),
            ("ENOSPC", 28),
            ("EXDEV", 18),
        ] {
            check(
                &run(Command::new("strace")
                    .args(["-qq", "-o"])
                    .arg(trace.path())
                    .args(["-e", "trace=mkdir,rmdir,unlink,rename,mmap,munmap", "-e"])
                    .arg(format!("inject={syscall}:error={error}:when=1"))
                    .arg(exe.path())
                    .args(&args)
                    .current_dir(directory.path())),
                code,
            );
            let events = std::fs::read_to_string(trace.path()).unwrap();
            assert!(events.contains("INJECTED"), "{events}");
            assert_eq!(
                events.lines().count(),
                1,
                "one host attempt, no allocations or fallback: {events}"
            );
            assert!(!directory.path().join("new").exists());
            assert!(directory.path().join("directory").is_dir());
            assert_eq!(
                std::fs::read(directory.path().join("file")).unwrap(),
                b"kept"
            );
            assert_eq!(
                std::fs::read(directory.path().join("destination")).unwrap(),
                b"destination kept"
            );
        }
    }
}

#[test]
fn mutations_execute_exact_path_limit_and_reject_larger_paths_without_syscalls() {
    use std::os::fd::AsRawFd;
    let exe = fixture("command");
    let directory = Directory::new();
    let component = "a".repeat(200);
    let mut current = std::fs::File::open(directory.path()).unwrap();
    let mut prefix = String::new();
    for _ in 0..20 {
        let child = format!("/proc/self/fd/{}/{}", current.as_raw_fd(), component);
        std::fs::create_dir(&child).unwrap();
        current = std::fs::File::open(child).unwrap();
        prefix.push_str(&component);
        prefix.push('/');
    }
    let leaf = "f".repeat(75);
    let other_leaf = "g".repeat(75);
    let source = format!("{prefix}{leaf}");
    let destination = format!("{prefix}{other_leaf}");
    assert_eq!(source.len(), 4095);
    normal(exe.path(), directory.path(), &["m", &source], 0);
    normal(
        exe.path(),
        directory.path(),
        &["r", &source, &destination],
        0,
    );
    normal(exe.path(), directory.path(), &["d", &destination], 0);
    let physical = format!("/proc/self/fd/{}/{}", current.as_raw_fd(), leaf);
    std::fs::write(&physical, b"boundary").unwrap();
    normal(exe.path(), directory.path(), &["u", &source], 0);
    assert!(!Path::new(&physical).exists());
    let trace = common::TempArtifact::new("laniusc_filesystem_operations", "limit_trace", None);
    let larger = format!("{source}x");
    for args in [
        vec!["m", &larger],
        vec!["d", &larger],
        vec!["u", &larger],
        vec!["r", &larger, &source],
        vec!["r", &source, &larger],
    ] {
        check(
            &run(Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mkdir,rmdir,unlink,rename,mmap,munmap"])
                .arg(exe.path())
                .args(&args)
                .current_dir(directory.path())),
            36,
        );
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    }
}
