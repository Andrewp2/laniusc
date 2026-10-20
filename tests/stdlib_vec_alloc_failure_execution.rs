mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

// Each row is a fixture, the allocator syscall to fail, strace's `when`
// (which calls fail: `2` is only the second, `2+` the second and every later
// one), and the exit code of an uninjected run. With the injection every
// fixture must exit 0: the failed operation left its vector unchanged.
const CASES: &[(&str, &str, &str, i32)] = &[
    ("std_vec_alloc_failure", "mmap", "1+", 1),
    ("std_vec_growth_failure", "mmap", "2+", 1),
    ("vec_u8_alloc_failure", "mmap", "1", 1),
    ("vec_u8_realloc_failure", "mremap", "1", 4),
    ("vec_u8_insert_realloc_failure", "mremap", "1", 4),
    ("vec_u8_extend_realloc_failure", "mremap", "1", 4),
    ("vec_u8_clone_alloc_failure", "mmap", "2", 4),
    ("utf8_vec_alloc_failure", "mmap", "1", 1),
    ("utf8_vec_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_bulk_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_insert_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_replace_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_codes_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_insert_codes_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_splice_codes_realloc_failure", "mremap", "1", 4),
    ("utf8_vec_clone_alloc_failure", "mmap", "2", 4),
];

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

    let executable = common::TempArtifact::new("laniusc_vec", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat vector fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod vector fixture");
    executable
}

#[test]
fn vector_allocation_failures_leave_vectors_unchanged_on_x86() {
    for &(name, syscall, when, normal_exit) in CASES {
        let bytes = compile_fixture(name);

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(normal.status.code(), Some(normal_exit), "{name}: {normal:?}");
            if std::process::Command::new("strace").arg("-V").output().is_err() {
                continue;
            }
            let trace = common::TempArtifact::new("laniusc_vec", "trace", None);
            let injected = common::short_process_output_with_timeout(
                format!("{name} injected {syscall} failure"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg(format!("trace={syscall}"))
                    .arg("-e")
                    .arg(format!("inject={syscall}:error=ENOMEM:when={when}"))
                    .arg(executable.path()),
            );
            assert_eq!(injected.status.code(), Some(0), "{name}: {injected:?}");
            assert!(injected.stdout.is_empty() && injected.stderr.is_empty());
            let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
            assert!(trace_text.contains("INJECTED"), "{name}: {trace_text}");
            assert!(trace_text.contains("ENOMEM"), "{name}: {trace_text}");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, when, normal_exit);
    }
}
