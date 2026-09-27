mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_write_i32", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat integer writer")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod integer writer");
    executable
}

#[test]
fn raw_signed_integer_writer_formats_signed_boundaries_on_x86() {
    let bytes = compile_fixture("std_io_write_i32_boundaries");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "signed_boundaries");
        let output = common::short_process_output_with_timeout(
            "raw write_i32 signed boundaries",
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"0-42-21474836482147483647");
        assert!(output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn raw_signed_integer_writer_retries_short_writes_on_x86() {
    let bytes = compile_fixture("repro_io_write_i32_short");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "short_write");
        let normal = common::short_process_output_with_timeout(
            "raw write_i32 normal",
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(normal.status.code(), Some(0), "{normal:?}");
        assert_eq!(normal.stdout, b"42");

        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let trace = common::TempArtifact::new("laniusc_write_i32", "short_trace", None);
        let injected = common::short_process_output_with_timeout(
            "raw write_i32 short host write",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-o")
                .arg(trace.path())
                .arg("-e")
                .arg("trace=write")
                .arg("-e")
                .arg("inject=write:retval=1:when=1")
                .arg(executable.path()),
        );
        assert_eq!(injected.status.code(), Some(0), "{injected:?}");
        // strace reports one byte written without copying it; the second
        // syscall writes the remaining byte from the formatted buffer.
        assert_eq!(injected.stdout, b"2");
        let trace_text = std::fs::read_to_string(trace.path()).expect("read write trace");
        assert!(trace_text.contains("INJECTED"), "{trace_text}");
        assert_eq!(trace_text.matches("write(").count(), 2, "{trace_text}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn raw_signed_integer_writer_reports_no_progress_and_host_errors_on_x86() {
    let bytes = compile_fixture("std_io_write_i32_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "write_failure");
        for fault in ["retval=0", "error=EIO"] {
            let trace = common::TempArtifact::new("laniusc_write_i32", "failure_trace", None);
            let injected = common::short_process_output_with_timeout(
                format!("raw write_i32 {fault}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg(format!("inject=write:{fault}:when=1"))
                    .arg(executable.path()),
            );
            assert_eq!(injected.status.code(), Some(0), "{fault}: {injected:?}");
            assert!(injected.stdout.is_empty() && injected.stderr.is_empty());
            let trace_text = std::fs::read_to_string(trace.path()).expect("read write trace");
            assert!(trace_text.contains("INJECTED"), "{fault}: {trace_text}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
