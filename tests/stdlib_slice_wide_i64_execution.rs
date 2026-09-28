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
fn all_wide_signed_slice_operations_execute_on_x86() {
    let bytes = compile_fixture("core_slice_wide_i64_complete");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("slice_wide_i64", "slice_wide_i64", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn each_public_wide_slice_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/slice_wide_i64.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_slice_wide_i64_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else { continue; };
        let name = tail.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next().expect("slice function name");
        let call = format!("core::slice_wide_i64::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 36);
}

#[test]
fn physical_backing_overclaims_exit_101() {
    for name in [
        "core_slice_wide_i64_bounds",
        "core_slice_wide_i64_first_bounds",
        "core_slice_wide_i64_capacity_bounds",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(101), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn wide_signed_median_program_uses_slice_parsing_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/wide_signed_median_five.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide signed median", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide signed median program");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_stdlib", "wide_signed_median", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected_code, expected_stdout) in [
            (
                b"-7\n9223372036854775807\n4294967296\n-9223372036854775808\n2\n".as_slice(),
                0,
                b"2\n".as_slice(),
            ),
            (
                b"9223372036854775807\n-1\n0\n-9223372036854775808\n-1\n".as_slice(),
                0,
                b"-1\n".as_slice(),
            ),
            (
                b"-9223372036854775808\n-9223372036854775808\n-9223372036854775808\n-9223372036854775808\n-9223372036854775808".as_slice(),
                0,
                b"-9223372036854775808\n".as_slice(),
            ),
            (b"-0\n0\n0\n0\n0\n".as_slice(), 0, b"0\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 2, b"".as_slice()),
            (b"1\n2\n3\n4\n5\n6\n".as_slice(), 2, b"".as_slice()),
            (b"1\n2\n3\n4\nno\n".as_slice(), 3, b"".as_slice()),
            (b"1\n2\n3\n4\n9223372036854775808\n".as_slice(), 3, b"".as_slice()),
            (b"1\n2\n3\n4\n-9223372036854775809\n".as_slice(), 3, b"".as_slice()),
            (b"1\n2\n3\n4\n123456789012345678901\n".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_stdlib", "wide_median_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "wide signed median",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(expected_code), "{input_bytes:?}: {output:?}");
            assert_eq!(output.stdout, expected_stdout, "{input_bytes:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{input_bytes:?}: {output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
