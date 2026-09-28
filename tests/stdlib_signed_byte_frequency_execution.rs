mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn signed_byte_frequency_program_handles_input_and_output_failures() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/signed_byte_frequency_report.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("signed byte frequency", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed byte frequency report");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_signed_byte", "frequency", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let every_byte = (0..=255).map(|value| value as u8).collect::<Vec<_>>();
        for (input_bytes, expected) in [
            (b"".as_slice(), b"-129\n0\n0\n".as_slice()),
            (b"banana".as_slice(), b"97\n3\n3\n".as_slice()),
            (b"\xff\xff\0\0".as_slice(), b"-1\n2\n2\n".as_slice()),
            (b"\x80\x80\x7f".as_slice(), b"-128\n2\n2\n".as_slice()),
            (every_byte.as_slice(), b"-128\n1\n256\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_signed_byte", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "signed byte frequency",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{input_bytes:?}: {output:?}");
            assert_eq!(output.stdout, expected, "{input_bytes:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }

        let full = std::fs::OpenOptions::new()
            .write(true)
            .open("/dev/full")
            .unwrap();
        let status = std::process::Command::new("timeout")
            .arg("5s")
            .arg(executable.path())
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::from(full))
            .status()
            .expect("run with /dev/full stdout");
        assert_eq!(status.code(), Some(4), "{status:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
