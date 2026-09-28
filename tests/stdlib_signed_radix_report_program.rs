mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn signed_radix_report_combines_portable_parse_and_host_writers() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/signed_radix_report.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("signed radix report", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed radix report");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_stdlib", "signed_radix_report", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let min_input = format!("-0B1{}\n", "0".repeat(63));
        let max_input = format!("{}\n", "1".repeat(63));
        let min_output = format!(
            "-1{} -8000000000000000 -9223372036854775808\n",
            "0".repeat(63)
        );
        let max_output = format!("{} 7fffffffffffffff 9223372036854775807\n", "1".repeat(63));
        let too_long = format!("{}\n", "1".repeat(86));
        for (input_bytes, expected_code, expected_stdout) in [
            (b"0\n".as_slice(), 0, b"0 0 0\n".as_slice()),
            (b"-0b1101\n".as_slice(), 0, b"-1101 -d -13\n".as_slice()),
            (b"+0B101101\n".as_slice(), 0, b"101101 2d 45\n".as_slice()),
            (min_input.as_bytes(), 0, min_output.as_bytes()),
            (max_input.as_bytes(), 0, max_output.as_bytes()),
            (b"0b12\n".as_slice(), 3, b"".as_slice()),
            (b"1 0\n".as_slice(), 3, b"".as_slice()),
            (too_long.as_bytes(), 2, b"".as_slice()),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_stdlib", "radix_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "signed radix report",
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
