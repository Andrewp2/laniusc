mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile(source: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(source);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(source, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{source}: compile: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let executable = common::TempArtifact::new("laniusc_narrow", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn all_32_bit_to_narrow_conversions_execute_on_x86() {
    let bytes = compile("tests/fixtures/stdlib_foundation/core_narrow.lani");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("core_narrow", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

// Canonical conversion policy is verified by executing core_narrow; the
// removed per-function name audit described the deleted helper namespace.

#[test]
fn narrow_byte_report_uses_real_decimal_input() {
    let bytes = compile("sample_programs/narrow_byte_report.lani");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "byte_report");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"300\n".as_slice(), 0, b"44\n255\n61\n".as_slice()),
            (b"-1\n".as_slice(), 0, b"255\n0\n16\n".as_slice()),
            (b"127\n".as_slice(), 0, b"127\n127\n254\n".as_slice()),
            (b"0\n".as_slice(), 0, b"0\n0\n0\n".as_slice()),
            (b"256\n".as_slice(), 0, b"0\n255\n17\n".as_slice()),
            (b"bad\n".as_slice(), 2, b"".as_slice()),
            (b"123456789\n".as_slice(), 0, b"21\n255\n38\n".as_slice()),
            (b"-2147483648\n".as_slice(), 0, b"0\n0\n17\n".as_slice()),
            (b"2147483647\n".as_slice(), 0, b"255\n255\n16\n".as_slice()),
            (b" \t+42\r\n".as_slice(), 0, b"42\n42\n84\n".as_slice()),
            (b"1 2\n".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_narrow", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "narrow byte report",
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
