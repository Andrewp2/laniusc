mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn owned_i32_vector_sort_and_search_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/vec_i32_sort_search.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("vec_i32_sort_search", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("vec_i32_sort_search: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("vec_i32_sort_search", "vec_i32_sort_search", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8]) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_vec", "sorted_i32_median", None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn sorted_median_program_uses_vector_sort_bounds_and_decimal_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/sorted_i32_median.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("sorted_i32_median", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile sorted median program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes);
        for (input_bytes, expected_code, expected_stdout) in [
            (b"4\n3\n3\n-5\n3\n".as_slice(), 0, b"3 3\n".as_slice()),
            (
                b"-2147483648\n2147483647\n".as_slice(),
                0,
                b"2147483647 1\n".as_slice(),
            ),
            (b"7\n".as_slice(), 0, b"7 1\n".as_slice()),
            (b"".as_slice(), 2, b"".as_slice()),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"1x\n".as_slice(), 3, b"".as_slice()),
            (b"2147483648\n".as_slice(), 3, b"".as_slice()),
            (b"-2147483649\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_vec", "median_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "sorted i32 median",
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
