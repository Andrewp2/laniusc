#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let executable = common::TempArtifact::new("laniusc_deque", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn recent_boolean_count_program_uses_deque_byte_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_bool_count.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent boolean count", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent boolean count");
    {
        let executable = write_executable(&bytes, "recent_bool_count");
        for (input_bytes, expected_stdout, expected_code) in [
            (b"".as_slice(), b"0\n".as_slice(), 0),
            (b"1".as_slice(), b"1\n".as_slice(), 0),
            (b"10110".as_slice(), b"3\n".as_slice(), 0),
            (b"0000011111".as_slice(), b"5\n".as_slice(), 0),
            (b"1 0\n1\t1 0".as_slice(), b"3\n".as_slice(), 0),
            (b"10x1".as_slice(), b"".as_slice(), 3),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "bool_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent boolean count",
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
}

#[test]
fn recent_unicode_program_uses_deque_and_utf8_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_unicode_scalars.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent unicode scalars", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent unicode scalars");
    {
        let executable = write_executable(&bytes, "recent_unicode_scalars");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            ("Ω".as_bytes(), 0, "Ω\n".as_bytes()),
            ("Ω😀é中".as_bytes(), 0, "😀é中\n".as_bytes()),
            (b"\0A\0B".as_slice(), 0, b"A\0B\n".as_slice()),
            (b"\xff".as_slice(), 2, b"".as_slice()),
            (b"\xf0\x9f".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque_char", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent unicode scalars",
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
            assert!(output.stderr.is_empty());
        }
        let full = std::fs::OpenOptions::new()
            .write(true)
            .open("/dev/full")
            .expect("open /dev/full");
        let status = std::process::Command::new("timeout")
            .arg("5s")
            .arg(executable.path())
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::from(full))
            .status()
            .expect("run with /dev/full stdout");
        assert_eq!(status.code(), Some(4), "{status:?}");
    }
}

#[test]
fn recent_signed_byte_lines_program_checks_bounds_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_i8_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent i8 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent i8 lines");
    {
        let executable = write_executable(&bytes, "recent_i8_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"-1\n".as_slice(), 0, b"-1\n".as_slice()),
            (b"1\n-2\n3\n4\n".as_slice(), 0, b"-2 3 4\n".as_slice()),
            (
                b"0\n-128\n127\n-0".as_slice(),
                0,
                b"-128 127 0\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"128\n".as_slice(), 3, b"".as_slice()),
            (b"-129\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent i8 lines",
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
}

#[test]
fn recent_signed_halfword_lines_program_checks_bounds_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_i16_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent i16 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent i16 lines");
    {
        let executable = write_executable(&bytes, "recent_i16_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"-1\n".as_slice(), 0, b"-1\n".as_slice()),
            (b"1\n-2\n3\n4\n".as_slice(), 0, b"-2 3 4\n".as_slice()),
            (
                b"0\n-32768\n32767\n-0".as_slice(),
                0,
                b"-32768 32767 0\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"32768\n".as_slice(), 3, b"".as_slice()),
            (b"-32769\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent i16 lines",
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
}

#[test]
fn recent_lines_program_uses_deque_decimal_and_io_helpers_i32() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_i32_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent i32 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent i32 lines");
    {
        let executable = write_executable(&bytes, "recent_i32_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"7\n".as_slice(), 0, b"7\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 0, b"2 3 4\n".as_slice()),
            (
                b"0\n-2147483648\n2147483647\n-0".as_slice(),
                0,
                b"-2147483648 2147483647 0\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"2147483648\n".as_slice(), 3, b"".as_slice()),
            (b"-2147483649\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent i32 lines",
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
}

#[test]
fn recent_byte_checksum_program_uses_deque_byte_option_and_io() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_byte_checksum.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent byte checksum", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent byte checksum");
    {
        let executable = write_executable(&bytes, "recent_byte_checksum");
        for (input_bytes, expected_stdout) in [
            (b"".as_slice(), b"0\n".as_slice()),
            (b"\x01".as_slice(), b"1\n".as_slice()),
            (b"\x01\x02\x03\x04".as_slice(), b"9\n".as_slice()),
            (b"\xff\x01\x02\x03".as_slice(), b"6\n".as_slice()),
            (b"\xff\xff\xff".as_slice(), b"253\n".as_slice()),
            (b"\x00\xff\x00".as_slice(), b"255\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "byte_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent byte checksum",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{input_bytes:?}: {output:?}");
            assert_eq!(
                output.stdout, expected_stdout,
                "{input_bytes:?}: {output:?}"
            );
            assert!(output.stderr.is_empty(), "{input_bytes:?}: {output:?}");
        }
    }
}

#[test]
fn recent_lines_program_uses_deque_decimal_and_io_helpers_u16() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_u16_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent u16 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent u16 lines");
    {
        let executable = write_executable(&bytes, "recent_u16_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"7\n".as_slice(), 0, b"7\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 0, b"2 3 4\n".as_slice()),
            (
                b"0\n32768\n65535\n0".as_slice(),
                0,
                b"32768 65535 0\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"65536\n".as_slice(), 3, b"".as_slice()),
            (b"-1\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent u16 lines",
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
}

#[test]
fn recent_lines_program_uses_deque_decimal_and_io_helpers_u32() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_u32_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent u32 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent u32 lines");
    {
        let executable = write_executable(&bytes, "recent_u32_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"7\n".as_slice(), 0, b"7\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 0, b"2 3 4\n".as_slice()),
            (
                b"0\n2147483648\n4294967295\n0".as_slice(),
                0,
                b"2147483648 4294967295 0\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"4294967296\n".as_slice(), 3, b"".as_slice()),
            (b"-1\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent u32 lines",
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
}

#[test]
fn recent_lines_program_uses_deque_decimal_and_io_helpers_wide_i64() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_wide_i64_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent wide i64 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent wide i64 lines");
    {
        let executable = write_executable(&bytes, "recent_wide_i64_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"7\n".as_slice(), 0, b"7\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 0, b"2 3 4\n".as_slice()),
            (
                b"0\n-1\n-9223372036854775808\n9223372036854775807".as_slice(),
                0,
                b"-1 -9223372036854775808 9223372036854775807\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"9223372036854775808\n".as_slice(), 3, b"".as_slice()),
            (b"-9223372036854775809\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent wide i64 lines",
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
}

#[test]
fn recent_lines_program_uses_deque_decimal_and_io_helpers_wide_u64() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/recent_wide_u64_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("recent wide u64 lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile recent wide u64 lines");
    {
        let executable = write_executable(&bytes, "recent_wide_u64_lines");
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"\n".as_slice()),
            (b"7\n".as_slice(), 0, b"7\n".as_slice()),
            (b"1\n2\n3\n4\n".as_slice(), 0, b"2 3 4\n".as_slice()),
            (
                b"0\n4294967296\n9223372036854775808\n18446744073709551615".as_slice(),
                0,
                b"4294967296 9223372036854775808 18446744073709551615\n".as_slice(),
            ),
            (b"\n".as_slice(), 2, b"".as_slice()),
            (b"123456789012345678901\n".as_slice(), 2, b"".as_slice()),
            (b"1 x\n".as_slice(), 3, b"".as_slice()),
            (b"18446744073709551616\n".as_slice(), 3, b"".as_slice()),
            (b"-1\n".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_deque", "recent_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "recent wide u64 lines",
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
}
