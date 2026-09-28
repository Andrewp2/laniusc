mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_entry(name: &str, path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

fn compile_fixture(name: &str) -> Vec<u8> {
    compile_entry(
        name,
        &format!("tests/fixtures/stdlib_foundation/{name}.lani"),
    )
}

#[test]
fn byte_backed_utf8_operations_execute_on_x86() {
    for (name, path, exit_code, stdout) in [
        (
            "core_utf8_bytes",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_bytes_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_search",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_search.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_search_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_search_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_append",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_append.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_append_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_append_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "utf8_vec_bytes",
            "tests/fixtures/stdlib_foundation/utf8_vec_bytes.lani",
            0,
            b"".as_slice(),
        ),
        (
            "utf8_vec_splice_bytes",
            "tests/fixtures/stdlib_foundation/utf8_vec_splice_bytes.lani",
            0,
            b"".as_slice(),
        ),
        (
            "utf8_vec_splice_bytes_bounds",
            "tests/fixtures/stdlib_foundation/utf8_vec_splice_bytes_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "utf8_text_report",
            "sample_programs/utf8_text_report.lani",
            0,
            b"A\xc2\xa2A\xc2\xa2B5\n".as_slice(),
        ),
    ] {
        let bytes = compile_entry(name, path);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(exit_code), "{name}: {output:?}");
            assert_eq!(output.stdout, stdout, "{name}: stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, exit_code);
    }
}

#[test]
fn byte_edits_failed_growth_preserve_utf8_text() {
    for name in [
        "utf8_vec_bytes_realloc_failure",
        "utf8_vec_splice_bytes_realloc_failure",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::fs::PermissionsExt;

            let executable = common::TempArtifact::new("laniusc_utf8", name, None);
            executable.write_bytes(&bytes);
            let mut permissions = std::fs::metadata(executable.path())
                .expect("stat UTF-8 byte fixture")
                .permissions();
            permissions.set_mode(0o700);
            std::fs::set_permissions(executable.path(), permissions).expect("chmod UTF-8 fixture");
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal allocation"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(normal.status.code(), Some(4), "{normal:?}");
            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_ok()
            {
                let trace = common::TempArtifact::new("laniusc_utf8", "trace", None);
                let injected = common::short_process_output_with_timeout(
                    format!("{name} injected realloc failure"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-o")
                        .arg(trace.path())
                        .arg("-e")
                        .arg("trace=mremap")
                        .arg("-e")
                        .arg("inject=mremap:error=ENOMEM:when=1")
                        .arg(executable.path()),
                );
                assert_eq!(injected.status.code(), Some(0), "{injected:?}");
                assert!(injected.stdout.is_empty() && injected.stderr.is_empty());
                let trace_text = std::fs::read_to_string(trace.path()).expect("read syscall trace");
                assert!(trace_text.contains("INJECTED"), "{trace_text}");
                assert!(trace_text.contains("ENOMEM"), "{trace_text}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}
