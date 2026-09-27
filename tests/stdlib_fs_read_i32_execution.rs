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

    let executable = common::TempArtifact::new("laniusc_read_i32", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat integer reader")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod integer reader");
    executable
}

#[test]
fn raw_signed_integer_reader_rejects_overflow_and_preserves_line_boundaries_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in ["std_fs_read_i32_boundaries", "repro_fs_read_i32_overflow"] {
        let bytes = compile_fixture(name);

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let output = common::short_process_output_with_timeout(
                format!("{name} native execution"),
                std::process::Command::new(executable.path()).current_dir(&root),
            );
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn raw_signed_integer_reader_returns_fallback_on_host_read_error_on_x86() {
    let bytes = compile_fixture("std_fs_read_i32_host_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let executable = write_executable(&bytes, "std_fs_read_i32_host_failure");
        let trace = common::TempArtifact::new("laniusc_read_i32", "read_trace", None);
        let output = common::short_process_output_with_timeout(
            "raw read_i32 injected host error",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-o")
                .arg(trace.path())
                .arg("-e")
                .arg("trace=read")
                .arg("-e")
                .arg("inject=read:error=EIO:when=1")
                .arg(executable.path())
                .current_dir(&root),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
        assert!(trace_text.contains("INJECTED"), "{trace_text}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
