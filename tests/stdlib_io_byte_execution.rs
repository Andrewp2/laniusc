mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile scalar byte I/O fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_byte", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat scalar byte fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod scalar byte fixture");
    executable
}

#[test]
fn scalar_byte_io_executes_with_binary_input_and_output() {
    let bytes = compile_fixture("std_io_byte");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_byte");
        let input = common::TempArtifact::new("laniusc_std_io_byte", "input", None);
        input.write_bytes(&[65, 0, 255]);
        let output = common::short_process_output_with_timeout(
            "scalar byte I/O",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).expect("open scalar byte input"),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, [0, 255], "{output:?}");
        assert_eq!(output.stderr, b"A", "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn scalar_byte_io_reports_injected_host_errors() {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, syscall, injection) in [
            ("std_io_byte_error", "read", "read:error=EIO:when=1"),
            ("std_io_byte_error", "read", "read:retval=2:when=1"),
            ("std_io_byte_write_error", "write", "write:error=EIO:when=1"),
            ("std_io_byte_write_error", "write", "write:retval=0:when=1"),
        ] {
            let bytes = compile_fixture(name);
            let executable = write_executable(&bytes, name);
            let input = common::TempArtifact::new("laniusc_std_io_byte", "fault_input", None);
            input.write_bytes(b"Z");
            let trace = common::TempArtifact::new("laniusc_std_io_byte", "fault_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("scalar byte {syscall} failure"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg(format!("trace={syscall}"))
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(input.path()).expect("open fault input"),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(
                std::fs::read_to_string(trace.path())
                    .expect("read fault trace")
                    .contains("INJECTED"),
                "{name}: host fault was not injected"
            );
        }
    }
}

#[test]
fn hex_to_decimal_program_uses_scalar_byte_io_and_portable_helpers() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/hex_to_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("hex_to_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile hex-to-decimal sample");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "hex_to_decimal");
        let cases: &[(&[u8], i32, &[u8])] = &[
            (b" 0a2f\n", 0, b"2607\n"),
            (b"FFFFFFFF", 0, b"4294967295\n"),
            (b"G", 3, b""),
            (b"100000000", 3, b""),
            (b" \n", 4, b""),
        ];
        for &(input_bytes, expected_exit, expected_stdout) in cases {
            let input = common::TempArtifact::new("laniusc_std_io_byte", "sample_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "hex-to-decimal sample",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).expect("open sample input"),
                )),
            );
            assert_eq!(output.status.code(), Some(expected_exit), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn fnv1a_stdin_program_hashes_text_empty_and_binary_input() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/fnv1a_stdin.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("fnv1a_stdin", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile stdin fingerprint sample");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "fnv1a_stdin");
        for (label, data, expected) in [
            ("text", b"foobar".as_slice(), b"bf9cf968\n".as_slice()),
            ("empty", b"".as_slice(), b"811c9dc5\n".as_slice()),
            ("binary", &[0, 255, 128][..], b"728e7760\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_fnv1a", label, None);
            input.write_bytes(data);
            let output = common::short_process_output_with_timeout(
                format!("fnv1a stdin {label}"),
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).expect("open fingerprint input"),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
            assert_eq!(output.stdout, expected, "{label}: {output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn scalar_byte_io_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_byte.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_io_byte.lani");
    let mut count = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        assert!(
            fixture.contains(&format!("std::io_byte::{name}(")),
            "std::io_byte::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}
