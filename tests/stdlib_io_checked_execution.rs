mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked stream fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_checked", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat stream fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod stream fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_with_input(executable: &common::TempArtifact, input: &[u8]) -> std::process::Output {
    let source = common::TempArtifact::new("laniusc_std_io_checked", "copy_input", None);
    source.write_bytes(input);
    common::short_process_output_with_timeout(
        "checked stream copy",
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).expect("open copy input"),
        )),
    )
}

#[test]
fn checked_streams_read_and_write_exact_bytes_on_x86() {
    let bytes = compile_fixture("std_io_checked");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_checked");
        let input = common::TempArtifact::new("laniusc_std_io_checked", "input", None);
        input.write_bytes(b"ABCDEFGHI");
        let output = common::short_process_output_with_timeout(
            "checked stdin/stdout/stderr",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).expect("open input fixture"),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"ABCDEFGHI");
        assert_eq!(output.stderr, b"E");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_stdin_reports_eof_after_a_read_prefix_on_x86() {
    let bytes = compile_fixture("std_io_checked_short_read");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_checked_short_read");
        let input = common::TempArtifact::new("laniusc_std_io_checked", "short_input", None);
        input.write_bytes(b"AB");
        let output = common::short_process_output_with_timeout(
            "checked short stdin",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).expect("open short input fixture"),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"AB");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_stdin_retries_short_host_reads_on_x86() {
    let bytes = compile_fixture("std_io_checked");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "std_io_checked_short_host_read");
        let input = common::TempArtifact::new("laniusc_std_io_checked", "retry_input", None);
        input.write_bytes(b"ABCDEFGHI");
        let trace = common::TempArtifact::new("laniusc_std_io_checked", "read_trace", None);
        let output = common::short_process_output_with_timeout(
            "checked short host read",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-o")
                .arg(trace.path())
                .arg("-e")
                .arg("trace=read")
                .arg("-e")
                .arg("inject=read:retval=2:when=1")
                .arg(executable.path())
                .stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).expect("open retry input"),
                )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        // strace reports two bytes read without copying them, then the helper
        // reads the remaining bytes from the input file into the later slots.
        assert_eq!(output.stdout, b"\0\0ABCDEFG");
        assert_eq!(output.stderr, b"E");
        let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
        assert!(trace_text.contains("INJECTED"), "{trace_text}");
        assert!(trace_text.matches("read(").count() >= 3, "{trace_text}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_streams_report_host_errors_and_zero_progress_on_x86() {
    let read_bytes = compile_fixture("std_io_checked_read_failure");
    let stdout_bytes = compile_fixture("std_io_checked_stdout_failure");
    let stderr_bytes = compile_fixture("std_io_checked_stderr_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let input = common::TempArtifact::new("laniusc_std_io_checked", "fault_input", None);
        input.write_bytes(b"ABCD");
        for (name, bytes, syscall) in [
            ("read", read_bytes.as_slice(), "read"),
            ("stdout", stdout_bytes.as_slice(), "write"),
            ("stderr", stderr_bytes.as_slice(), "write"),
        ] {
            let executable = write_executable(bytes, name);
            for fault in ["error=EIO", "retval=0"] {
                let trace = common::TempArtifact::new("laniusc_std_io_checked", "trace", None);
                let output = common::short_process_output_with_timeout(
                    format!("checked {name} {fault}"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-o")
                        .arg(trace.path())
                        .arg("-e")
                        .arg(format!("trace={syscall}"))
                        .arg("-e")
                        .arg(format!("inject={syscall}:{fault}:when=1"))
                        .arg(executable.path())
                        .stdin(std::process::Stdio::from(
                            std::fs::File::open(input.path()).expect("open fault input"),
                        )),
                );
                assert_eq!(output.status.code(), Some(0), "{output:?}");
                assert!(output.stdout.is_empty(), "{output:?}");
                assert!(output.stderr.is_empty(), "{output:?}");
                let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
                assert!(
                    trace_text.contains("INJECTED"),
                    "fault was not injected: {trace_text}"
                );
            }
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (read_bytes, stdout_bytes, stderr_bytes);
}

#[test]
fn checked_streams_retry_short_writes_on_x86() {
    let stdout_bytes = compile_fixture("std_io_checked_stdout_retry");
    let stderr_bytes = compile_fixture("std_io_checked_stderr_retry");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, bytes) in [
            ("stdout", stdout_bytes.as_slice()),
            ("stderr", stderr_bytes.as_slice()),
        ] {
            let executable = write_executable(bytes, name);
            let trace = common::TempArtifact::new("laniusc_std_io_checked", "short_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("checked short {name} write"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg("inject=write:retval=2:when=1")
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            let trace_text = std::fs::read_to_string(trace.path()).expect("read short trace");
            assert!(trace_text.contains("INJECTED"), "{trace_text}");
            assert!(trace_text.matches("write(").count() >= 2, "{trace_text}");
            if name == "stdout" {
                assert_eq!(output.stdout, b"CD");
                assert!(output.stderr.is_empty(), "{output:?}");
            } else {
                assert_eq!(output.stderr, b"CD");
                assert!(output.stdout.is_empty(), "{output:?}");
            }
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (stdout_bytes, stderr_bytes);
}

#[test]
fn checked_stdin_to_stdout_copy_executes_on_x86() {
    let copy_bytes = compile_fixture("std_io_checked_copy");
    let invalid_bytes = compile_fixture("std_io_checked_copy_invalid");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&copy_bytes, "copy");
        for input in [b"".as_slice(), b"ABC".as_slice()] {
            let output = run_with_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, input);
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        let input: Vec<u8> = (0..517).map(|index| ((index * 37) % 256) as u8).collect();
        let output = run_with_input(&executable, &input);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, input);
        assert!(output.stderr.is_empty(), "{output:?}");

        let invalid = write_executable(&invalid_bytes, "copy_invalid");
        let output = run_with_input(&invalid, b"ABCDEFGH");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"ABCDEFGH");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (copy_bytes, invalid_bytes);
}

#[test]
fn checked_stdin_to_stdout_copy_reports_failures_on_x86() {
    let bytes = compile_fixture("std_io_checked_copy_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "copy_failure");
        for (injection, expected) in [
            ("read:error=EIO:when=1", b"".as_slice()),
            ("read:error=EIO:when=2", b"ABCD".as_slice()),
            ("read:retval=5:when=1", b"".as_slice()),
            ("write:error=EIO:when=1", b"".as_slice()),
            ("write:error=EIO:when=2", b"ABCD".as_slice()),
            ("write:retval=0:when=1", b"".as_slice()),
        ] {
            let source = common::TempArtifact::new("laniusc_std_io_checked", "fault_input", None);
            source.write_bytes(b"ABCDEFGH");
            let trace = common::TempArtifact::new("laniusc_std_io_checked", "copy_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("checked copy {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg("trace=read,write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(source.path()).expect("open copy fault input"),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
            let trace_text = std::fs::read_to_string(trace.path()).expect("read copy trace");
            assert!(trace_text.contains("INJECTED"), "{trace_text}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_stdin_to_stdout_copy_handles_short_transfers_on_x86() {
    let bytes = compile_fixture("std_io_checked_copy");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "copy_short");
        for (injection, expected, syscall) in [
            ("read:retval=2:when=1", b"\0\0ABCDEFGH".as_slice(), "read"),
            ("write:retval=2:when=1", b"CDEFGH".as_slice(), "write"),
        ] {
            let source = common::TempArtifact::new("laniusc_std_io_checked", "short_input", None);
            source.write_bytes(b"ABCDEFGH");
            let trace = common::TempArtifact::new("laniusc_std_io_checked", "short_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("checked copy {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg("trace=read,write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(source.path()).expect("open short copy input"),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
            let trace_text = std::fs::read_to_string(trace.path()).expect("read short copy trace");
            assert!(trace_text.contains("INJECTED"), "{trace_text}");
            assert!(
                trace_text.matches(&format!("{syscall}(")).count() >= 2,
                "{trace_text}"
            );
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_stream_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_checked.lani");
    let fixture = format!(
        "{}{}",
        include_str!("fixtures/stdlib_host/std_io_checked.lani"),
        include_str!("fixtures/stdlib_host/std_io_checked_copy.lani")
    );
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
            fixture.contains(&format!("std::io_checked::{name}(")),
            "std::io_checked::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 4);
}
