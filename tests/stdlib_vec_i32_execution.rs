mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_vec_i32", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat vector fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod vector fixture");
    executable
}

#[test]
fn vector_growth_failures_leave_storage_unchanged_on_x86() {
    for (name, syscall, normal_exit) in [
        ("vec_i32_alloc_failure", "mmap", 1),
        ("vec_i32_realloc_failure", "mremap", 4),
    ] {
        let bytes = compile_fixture(name);

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(normal.status.code(), Some(normal_exit), "{name}: {normal:?}");
            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_err()
            {
                continue;
            }
            let trace = common::TempArtifact::new("laniusc_vec_i32", "trace", None);
            let injected = common::short_process_output_with_timeout(
                format!("{name} injected {syscall} failure"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg(format!("trace={syscall}"))
                    .arg("-e")
                    .arg(format!("inject={syscall}:error=ENOMEM:when=1"))
                    .arg(executable.path()),
            );
            assert_eq!(injected.status.code(), Some(0), "{name}: {injected:?}");
            assert!(injected.stdout.is_empty() && injected.stderr.is_empty());
            let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
            assert!(trace_text.contains("INJECTED"), "{name}: {trace_text}");
            assert!(trace_text.contains("ENOMEM"), "{name}: {trace_text}");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, normal_exit);
    }
}
