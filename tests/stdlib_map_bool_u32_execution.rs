mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn finite_boolean_keyed_map_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/map_bool_u32_complete.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("finite boolean map", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile the complete Boolean-keyed map fixture");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("finite boolean map", "map_bool_u32", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_boolean_map_function_has_an_executable_case() {
    let source = include_str!("../stdlib/std/map_bool_u32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/map_bool_u32_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("map function has a name");
        let call = format!("std::map_bool_u32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks an executable case");
        covered += 1;
    }
    assert_eq!(covered, 10);
}

#[test]
fn digit_byte_counter_uses_boolean_map_with_real_input() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/count_digit_bytes.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("digit byte counter", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile digit byte counter");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_map_bool", "digit_counter", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        for (input_bytes, expected) in [
            (b"".as_slice(), b"0\n0\n".as_slice()),
            (b"123a\n".as_slice(), b"3\n2\n".as_slice()),
            (b"\xff0\0".as_slice(), b"1\n2\n".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_map_bool", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "digit byte counter",
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
