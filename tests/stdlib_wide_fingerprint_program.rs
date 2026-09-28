mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn wide_fingerprint_program_handles_input_and_failure_cases() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/wide_fingerprint.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide fingerprint", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide fingerprint program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_stdlib", "wide_fingerprint", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        for (input_bytes, expected_code, expected_stdout) in [
            (&b"0\n"[..], 0, &b"-1 2615243109\n"[..]),
            (&b"4294967296\n"[..], 0, &b"-1 1270166100\n"[..]),
            (&b"9223372036854775808\n"[..], 0, &b"0 467811045\n"[..]),
            (&b"18446744073709551615\n"[..], 0, &b"1 1823345245\n"[..]),
            (&b"12x\n"[..], 3, &b""[..]),
            (&b"18446744073709551616\n"[..], 3, &b""[..]),
            (&b""[..], 2, &b""[..]),
        ] {
            let input = common::TempArtifact::new("laniusc_stdlib", "wide_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "wide fingerprint",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(expected_code), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
