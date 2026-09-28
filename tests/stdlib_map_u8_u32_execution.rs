mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn dense_byte_map_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, expected_exit) in [
        (
            "map_u8_u32",
            "tests/fixtures/stdlib_foundation/map_u8_u32_complete.lani",
            0,
        ),
        (
            "map_u8_u32_short",
            "tests/fixtures/stdlib_foundation/map_u8_u32_short_backing.lani",
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
fn every_byte_map_function_has_an_executable_case() {
    let source = include_str!("../stdlib/std/map_u8_u32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/map_u8_u32_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("map function has a name");
        let call = format!("std::map_u8_u32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks an executable case");
        covered += 1;
    }
    assert_eq!(covered, 12);
}

#[test]
fn byte_frequency_program_uses_map_with_real_input() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/byte_frequency_report.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("byte frequency report", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile byte frequency report");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_map_u8_u32", "frequency", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        let every_byte = (0..=255).map(|value| value as u8).collect::<Vec<_>>();
        for (input_bytes, expected) in [
            (b"".as_slice(), b"-1\n0\n".as_slice()),
            (b"banana".as_slice(), b"97\n3\n".as_slice()),
            (b"\xff\xff\0\0".as_slice(), b"0\n2\n".as_slice()),
            (b"1010".as_slice(), b"48\n2\n".as_slice()),
            (every_byte.as_slice(), b"0\n1\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_map_u8_u32", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "byte frequency report",
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
