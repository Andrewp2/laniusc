mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn checked_time_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/time_checked.lani");
    let cases = include_str!("fixtures/stdlib_host/std_time_checked.lani");
    let mut count = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        assert!(
            cases.contains(&format!("std::time_checked::{name}(")),
            "std::time_checked::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}

#[test]
fn every_public_time_metadata_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/std/time.lani");
    let cases = include_str!("fixtures/stdlib_host/std_time_metadata.lani");
    let mut count = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public time metadata function has a name");
        assert!(
            cases.contains(&format!("std::time::{name}(")),
            "std::time::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 53);
}

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked time fixture")
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_time", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat time fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod time fixture");
    executable
}

#[test]
fn std_time_checked_executes_on_x86() {
    let bytes = compile_fixture("std_time_checked");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_time_checked");
        let started = std::time::Instant::now();
        let output = common::short_process_output_with_timeout(
            "std_time_checked",
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            started.elapsed() >= std::time::Duration::from_millis(40),
            "50 ms sleep completed too quickly"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_time_metadata_executes_on_x86() {
    let bytes = compile_fixture("std_time_metadata");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_time_metadata", "std_time_metadata", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout");
        assert!(output.stderr.is_empty(), "unexpected stderr");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_time_checked_reports_host_failures_on_x86() {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, trace, injection, expected_exit) in [
            (
                "std_time_checked_failure",
                "clock_gettime",
                "clock_gettime:error=EIO:when=1",
                0,
            ),
            (
                "std_time_checked",
                "clock_gettime",
                "clock_gettime:error=EIO:when=2",
                10,
            ),
            (
                "std_time_sleep_failure",
                "nanosleep",
                "nanosleep:error=EINTR:when=1",
                0,
            ),
        ] {
            let bytes = compile_fixture(name);
            let executable = write_executable(&bytes, name);
            let output = common::short_process_output_with_timeout(
                format!("checked time {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg(format!("trace={trace}"))
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(expected_exit), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
    }
}
