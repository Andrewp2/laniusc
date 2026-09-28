mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn strict_utf16_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, expected_exit) in [
        (
            "core_utf16_complete",
            "tests/fixtures/stdlib_foundation/core_utf16_complete.lani",
            0,
        ),
        (
            "core_utf16_matrix",
            "tests/fixtures/stdlib_foundation/core_utf16_matrix.lani",
            0,
        ),
        (
            "core_utf16_bounds",
            "tests/fixtures/stdlib_foundation/core_utf16_bounds.lani",
            101,
        ),
    ] {
        let entry = root.join(source);
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_exit);
    }
}

#[test]
fn every_utf16_function_and_status_has_an_executable_case() {
    let source = include_str!("../stdlib/core/utf16.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_utf16_complete.lani");
    let mut functions = 0;
    let mut constants = 0;
    for line in source.lines() {
        if let Some(tail) = line.strip_prefix("pub fn ") {
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .unwrap();
            assert!(
                fixture.contains(&format!("core::utf16::{name}(")),
                "{name} lacks a runtime call"
            );
            functions += 1;
        }
        if let Some(tail) = line.strip_prefix("pub const ") {
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .unwrap();
            assert!(
                fixture.contains(&format!("core::utf16::{name}")),
                "{name} lacks a runtime assertion"
            );
            constants += 1;
        }
    }
    assert_eq!(functions, 17);
    assert_eq!(constants, 5);
}

#[test]
fn utf16le_count_program_handles_real_input_and_errors() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/utf16le_scalar_count.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("UTF-16LE scalar count", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile UTF-16LE scalar count program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_utf16", "scalar_count", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let maximum = vec![b'A', 0].repeat(64);
        let oversized = vec![b'A', 0].repeat(65);
        for (input_bytes, expected_exit, expected_output) in [
            (b"".as_slice(), 0, b"0\n".as_slice()),
            (b"A\0=\xd8\0\xde".as_slice(), 0, b"2\n".as_slice()),
            (b"\xff\xdb\xff\xdf".as_slice(), 0, b"1\n".as_slice()),
            (maximum.as_slice(), 0, b"64\n".as_slice()),
            (oversized.as_slice(), 3, b"".as_slice()),
            (b"A".as_slice(), 3, b"".as_slice()),
            (b"=\xd8".as_slice(), 3, b"".as_slice()),
            (b"\0\xdc".as_slice(), 3, b"".as_slice()),
            (b"=\xd8A\0".as_slice(), 3, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_utf16", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "UTF-16LE scalar count",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{input_bytes:?}: {output:?}"
            );
            assert_eq!(
                output.stdout, expected_output,
                "{input_bytes:?}: {output:?}"
            );
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
