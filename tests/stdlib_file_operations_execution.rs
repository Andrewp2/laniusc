#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    io::{Read, Seek, SeekFrom},
    os::unix::fs::{PermissionsExt, symlink},
    process::{Command, Output},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let file = common::TempArtifact::new("laniusc_file_ops", "directory", None);
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
    common::process_output_with_timeout("file operations", command, Duration::from_secs(5))
}
fn checked(out: &Output, status: i32) {
    assert_eq!(out.status.code(), Some(status), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_file_ops", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn raw_openat_statx_binding_admission() {
    let exe = executable("file_ops_admission");
    let out = common::process_output_with_timeout(
        "file ops binding admission",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}

#[test]
fn file_operations_preserve_native_identity_flags_and_large_positions() {
    let exe = executable("file_ops_contracts");
    let directory = Directory::new();
    std::fs::write(directory.path().join("target"), b"unrelated").unwrap();
    symlink("data", directory.path().join("link")).unwrap();
    checked(
        &run(Command::new(exe.path()).current_dir(directory.path())),
        0,
    );
    let name = directory.path().join("data");
    let metadata = std::fs::metadata(&name).unwrap();
    assert_eq!(metadata.len(), 4_294_967_312);
    assert_eq!(metadata.permissions().mode() & 0o777, 0o600);
    let mut file = std::fs::File::open(name).unwrap();
    let mut prefix = [0; 6];
    file.read_exact(&mut prefix).unwrap();
    assert_eq!(prefix, [0, 128, 255, 97, 98, 99]);
    file.seek(SeekFrom::End(-2)).unwrap();
    let mut tail = [0; 2];
    file.read_exact(&mut tail).unwrap();
    assert_eq!(tail, [0, 99]);
    assert_eq!(
        std::fs::read(directory.path().join("target")).unwrap(),
        b"unrelated"
    );
}

#[test]
fn syscall_errors_remain_distinct_and_close_is_never_retried() {
    let exe = executable("file_ops_fault");
    let directory = Directory::new();
    std::fs::write(directory.path().join("input"), b"input").unwrap();
    let trace = common::TempArtifact::new("laniusc_file_ops", "trace", None);
    // strace close injection skips the syscall. These cases check logical
    // invalidation and one attempt, not real Linux release after a close error.
    for (operation, injection, expected, syscall, attempts) in [
        (0, "openat:error=EACCES:when=1", 113, "close(", 0),
        (0, "lseek:error=EINTR:when=1", 104, "lseek(", 1),
        (0, "lseek:error=ESPIPE:when=1", 129, "close(", 1),
        (1, "statx:error=EIO:when=1", 105, "close(", 1),
        (1, "statx:error=EAGAIN:when=1", 111, "statx(", 1),
        (2, "fsync:error=ENOSPC:when=1", 128, "fsync(", 1),
        (3, "fdatasync:error=EINTR:when=1", 104, "fdatasync(", 1),
        (4, "fcntl:error=EMFILE:when=1", 124, "close(", 1),
        (0, "close:error=EINTR:when=1", 104, "close(", 1),
        (4, "close:error=EIO:when=1", 105, "close(", 2),
    ] {
        let out = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=openat,close,lseek,fcntl,fsync,fdatasync,statx",
                "-e",
            ])
            .arg(format!("inject={injection}"))
            .arg(exe.path())
            .arg(operation.to_string())
            .current_dir(directory.path()));
        checked(&out, expected);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{injection}: {events}");
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with(syscall))
                .count(),
            attempts,
            "{injection}: {events}"
        );
    }
}

#[test]
fn metadata_decoder_and_invalid_paths_are_atomic_before_syscalls() {
    let exe = executable("file_ops_bounds");
    let trace = common::TempArtifact::new("laniusc_file_ops", "bounds", None);
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=openat,statx"])
        .arg(exe.path()));
    checked(&out, 0);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn statx_fields_match_an_independent_os_metadata_oracle() {
    let exe = executable("file_ops_metadata");
    let directory = Directory::new();
    let input = directory.path().join("input");
    std::fs::write(&input, [0, 128, 255, 42]).unwrap();
    let oracle = "import os,sys; p=sys.argv[1]; os.utime(p,ns=(-500000000,-123456789)); s=os.stat(p,follow_symlinks=False); a=divmod(s.st_atime_ns,10**9); m=divmod(s.st_mtime_ns,10**9); c=divmod(s.st_ctime_ns,10**9); print(','.join(map(str,[s.st_mode,s.st_uid,s.st_gid,s.st_nlink,s.st_ino,s.st_size,s.st_blocks,s.st_blksize,*a,*m,*c,os.major(s.st_dev),os.minor(s.st_dev),os.major(s.st_rdev),os.minor(s.st_rdev)])))";
    let expected = run(Command::new("python3").args(["-c", oracle]).arg(&input));
    assert_eq!(expected.status.code(), Some(0), "{expected:?}");
    let actual = run(Command::new(exe.path()).current_dir(directory.path()));
    assert_eq!(actual.status.code(), Some(0), "{actual:?}");
    assert_eq!(actual.stdout, expected.stdout);
    assert!(actual.stderr.is_empty());
}
