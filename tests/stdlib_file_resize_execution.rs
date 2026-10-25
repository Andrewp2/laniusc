//! Checked file length changes on the native x86_64 Linux profile.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_resize", "directory", None);
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

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/file_resize/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("file resizing {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_resize", name, None);
    // The shared writer applies the unchanged strict native transfer checker.
    output.write_bytes(bytes);
    fs::set_permissions(output.path(), fs::Permissions::from_mode(0o700)).unwrap();
    output
}

fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("file resize", command, Duration::from_secs(5))
}

fn checked(output: &Output, code: i32) {
    assert_eq!(output.status.code(), Some(code), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn length_changes_preserve_offsets_and_expose_zero_filled_extensions() {
    let executable = executable("contracts");
    let directory = Directory::new();
    fs::write(directory.path().join("input"), [0, 128, 255, 97, 98, 99]).unwrap();
    let trace = common::TempArtifact::new("laniusc_resize", "contracts-trace", None);
    checked(
        &run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=ftruncate,close,mmap,munmap"])
            .arg(executable.path())
            .current_dir(directory.path())),
        0,
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    let lengths: Vec<i64> = events
        .lines()
        .filter_map(|line| line.strip_prefix("ftruncate("))
        .map(|arguments| {
            arguments
                .split_once(',')
                .unwrap()
                .1
                .split_once(')')
                .unwrap()
                .0
                .trim()
                .parse()
                .unwrap()
        })
        .collect();
    // Seven valid changes and one real read-only failure. The two active
    // oversized requests and both closed-owner cases must not reach the host.
    assert_eq!(lengths.len(), 8, "{events}");
    assert_eq!(&lengths[..7], [3, 3, 8, 0, 4_294_967_313, 0, 3], "{events}");
    assert!(lengths.iter().all(|length| *length >= 0), "{events}");
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("close("))
            .count(),
        3,
        "{events}"
    );
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "{events}"
    );
    // The fixture checks sparse high offsets before returning to this small
    // final length. The OS oracle also observes the published bytes.
    assert_eq!(fs::read(directory.path().join("input")).unwrap(), [0, 0, 0]);
}

#[test]
fn resize_errors_are_not_retried_and_success_requires_a_zero_result() {
    let executable = executable("fault");
    let directory = Directory::new();
    let input = directory.path().join("input");
    let trace = common::TempArtifact::new("laniusc_resize", "trace", None);
    for (injection, expected) in [
        (None, 0),
        (Some("ftruncate:error=EINTR:when=1"), 104),
        (Some("ftruncate:error=EAGAIN:when=1"), 111),
        (Some("ftruncate:error=EIO:when=1"), 105),
        (Some("ftruncate:error=EFBIG:when=1"), 127),
        (Some("ftruncate:error=ENOSPC:when=1"), 128),
        (Some("ftruncate:retval=1:when=1"), 196),
    ] {
        fs::write(&input, [0, 128, 255, 97, 98, 99]).unwrap();
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=ftruncate,close"]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        checked(
            &run(command.arg(executable.path()).current_dir(directory.path())),
            expected,
        );
        let events = fs::read_to_string(trace.path()).unwrap();
        for syscall in ["ftruncate(", "close("] {
            assert_eq!(
                events
                    .lines()
                    .filter(|line| line.starts_with(syscall))
                    .count(),
                1,
                "{injection:?}: {events}"
            );
        }
        assert_eq!(events.contains("INJECTED"), injection.is_some(), "{events}");
        let expected_bytes: &[u8] = if injection.is_none() {
            &[0, 128]
        } else {
            &[0, 128, 255, 97, 98, 99]
        };
        assert_eq!(fs::read(&input).unwrap(), expected_bytes, "{events}");
    }
}
