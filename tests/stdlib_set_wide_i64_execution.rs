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

#[test]
fn owned_wide_i64_set_executes_on_x86() {
    let bytes = compile_fixture("set_wide_i64_complete");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("set_wide_i64", "set_wide_i64", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_i64_set_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/std/set_wide_i64.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/set_wide_i64_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("set function has a name");
        let call = format!("std::set_wide_i64::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 19);
}

#[test]
fn set_allocation_failures_preserve_owned_data() {
    for (name, syscall, when) in [
        ("set_wide_i64_alloc_failure", "mmap", 1),
        ("set_wide_i64_realloc_failure", "mremap", 1),
        ("set_wide_i64_shrink_failure", "mremap", 1),
        ("set_wide_i64_clone_failure", "mmap", 2),
        ("set_wide_i64_union_failure", "mmap", 3),
        ("set_wide_i64_intersection_failure", "mmap", 3),
        ("set_wide_i64_difference_failure", "mmap", 3),
        ("set_wide_i64_symmetric_difference_failure", "mmap", 3),
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::fs::PermissionsExt;

            let executable = common::TempArtifact::new("laniusc_set", name, None);
            executable.write_bytes(&bytes);
            let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
            permissions.set_mode(0o700);
            std::fs::set_permissions(executable.path(), permissions).unwrap();

            let normal = common::short_process_output_with_timeout(
                format!("{name} normal allocation"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(normal.status.code(), Some(4), "{name}: {normal:?}");

            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_ok()
            {
                let trace = common::TempArtifact::new("laniusc_set", "trace", None);
                let injected = common::short_process_output_with_timeout(
                    format!("{name} injected allocation failure"),
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
                let trace_text = std::fs::read_to_string(trace.path()).unwrap();
                assert!(trace_text.contains("INJECTED"), "{name}: {trace_text}");
                assert!(trace_text.contains("ENOMEM"), "{name}: {trace_text}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, when);
    }
}
#[test]
fn wide_signed_distinct_sum_program_uses_set_and_wrapping_arithmetic() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/wide_signed_distinct_sum.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide signed distinct sum", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide signed distinct sum program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable =
            common::TempArtifact::new("laniusc_stdlib", "wide_signed_distinct_sum", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"0\n".as_slice()),
            (b"-7\n5\n-7\n".as_slice(), 0, b"-2\n".as_slice()),
            (
                b"9223372036854775807\n1\n".as_slice(),
                0,
                b"-9223372036854775808\n".as_slice(),
            ),
            (
                b"-9223372036854775808\n-9223372036854775808\n1\n".as_slice(),
                0,
                b"-9223372036854775807\n".as_slice(),
            ),
            (b"-0\n0\n".as_slice(), 0, b"0\n".as_slice()),
            (
                b"4294967296\n4294967296".as_slice(),
                0,
                b"4294967296\n".as_slice(),
            ),
            (b"1\n\n".as_slice(), 2, b"".as_slice()),
            (b"1 2\n".as_slice(), 3, b"".as_slice()),
            (b"9223372036854775808\n".as_slice(), 3, b"".as_slice()),
            (b"-9223372036854775809\n".as_slice(), 3, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
        ] {
            let input =
                common::TempArtifact::new("laniusc_stdlib", "wide_distinct_sum_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "wide signed distinct sum",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(
                output.status.code(),
                Some(expected_code),
                "{input_bytes:?}: {output:?}"
            );
            assert_eq!(
                output.stdout, expected_stdout,
                "{input_bytes:?}: {output:?}"
            );
            assert!(output.stderr.is_empty(), "{input_bytes:?}: {output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
