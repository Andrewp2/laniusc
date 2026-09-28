mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn pointer_option_and_result_public_functions_execute() {
    let fixture = include_str!("fixtures/stdlib_foundation/option_result_ptr_complete.lani");
    for (module, source, expected) in [
        (
            "option_ptr",
            include_str!("../stdlib/core/option_ptr.lani"),
            12,
        ),
        (
            "result_ptr",
            include_str!("../stdlib/core/result_ptr.lani"),
            10,
        ),
    ] {
        let mut covered = 0;
        for line in source.lines() {
            let Some(tail) = line.strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            let call = format!("core::{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
            covered += 1;
        }
        assert_eq!(covered, expected, "{module}");
    }

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/option_result_ptr_complete.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("pointer_option_result", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile pointer Option/Result fixture");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("pointer_option_result", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn first_byte_result_program_uses_pointer_option_result_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/first_byte_result.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("first byte result", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile first byte result program");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_ptr_result", "program", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected) in [
            (b"".as_slice(), b"-1\n".as_slice()),
            (b"\x00".as_slice(), b"0\n".as_slice()),
            (b"A".as_slice(), b"65\n".as_slice()),
            (b"\xff\x01".as_slice(), b"255\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_ptr_result", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "first byte result",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{input_bytes:?}: {output:?}");
            assert_eq!(output.stdout, expected, "{input_bytes:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{input_bytes:?}: {output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
