mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"))
}

#[test]
fn every_public_wide_vector_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/vec_wide_u64.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/vec_wide_u64.lani");
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 19);
    for name in names {
        assert!(
            fixture.contains(&format!("std::vec_wide_u64::{name}(")),
            "{name}"
        );
    }
}

#[test]
fn wide_unsigned_vector_operations_execute_on_x86() {
    let bytes = compile_fixture("vec_wide_u64");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("unsigned wide vector", "vec_wide_u64", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let exe = common::TempArtifact::new("laniusc_vec_wide_u64", name, None);
    exe.write_bytes(bytes);
    let mut permissions = std::fs::metadata(exe.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(exe.path(), permissions).unwrap();
    exe
}

#[test]
fn wide_unsigned_vector_overstated_word_view_traps_on_x86() {
    let bytes = compile_fixture("vec_wide_u64_extend_bounds");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "wide vector backing bounds",
            "vec_wide_u64_extend_bounds",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(101), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn wide_unsigned_vector_allocation_failures_preserve_ownership_on_x86() {
    for (name, syscall, when) in [
        ("vec_wide_u64_alloc_failure", "mmap", 1),
        ("vec_wide_u64_realloc_failure", "mremap", 1),
        ("vec_wide_u64_extend_realloc_failure", "mremap", 1),
        ("vec_wide_u64_insert_realloc_failure", "mremap", 1),
        ("vec_wide_u64_resize_realloc_failure", "mremap", 1),
        ("vec_wide_u64_clone_alloc_failure", "mmap", 2),
        ("vec_wide_u64_shrink_realloc_failure", "mremap", 1),
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let exe = executable(&bytes, name);
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal"),
                &mut std::process::Command::new(exe.path()),
            );
            assert_eq!(normal.status.code(), Some(1), "{name}: {normal:?}");
            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_err()
            {
                continue;
            }
            let trace = common::TempArtifact::new("laniusc_vec_wide_u64", "trace", None);
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
                    .arg(exe.path()),
            );
            assert_eq!(injected.status.code(), Some(0), "{name}: {injected:?}");
            let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
            assert!(
                trace_text.contains("INJECTED") && trace_text.contains("ENOMEM"),
                "{name}: {trace_text}"
            );
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, when);
    }
}
