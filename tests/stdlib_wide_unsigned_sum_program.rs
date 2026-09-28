mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn wide_unsigned_sum_program_uses_owned_vector_and_wrapping_arithmetic() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/wide_unsigned_sum.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide unsigned sum", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide unsigned sum program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_stdlib", "wide_unsigned_sum", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"0\n".as_slice()),
            (
                b"18446744073709551615\n1\n".as_slice(),
                0,
                b"0\n".as_slice(),
            ),
            (
                b"9223372036854775808\n9223372036854775808\n".as_slice(),
                0,
                b"0\n".as_slice(),
            ),
            (b"1\n2\n3\n4\n5\n".as_slice(), 0, b"15\n".as_slice()),
            (b"4294967296".as_slice(), 0, b"4294967296\n".as_slice()),
            (b"1\n\n".as_slice(), 2, b"".as_slice()),
            (b"1 2\n".as_slice(), 3, b"".as_slice()),
            (b"18446744073709551616\n".as_slice(), 3, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_stdlib", "wide_sum_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "wide unsigned sum",
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
