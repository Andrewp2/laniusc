mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[test]
fn owned_character_key_map_executes_on_x86() {
    for name in ["map_char_u32_complete", "map_char_u32_unicode"] {
        let bytes = compile_fixture(name);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output("map_char_u32", "map_char_u32", &bytes);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(output.stdout.is_empty(), "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn every_public_character_key_map_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/std/map_char_u32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/map_char_u32_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("map function has a name");
        let call = format!("std::map_char_u32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 16);
    assert!(fixture.contains("std::map_char_u32::MAX_ENTRIES"));
}

#[test]
fn map_allocation_failures_preserve_owned_data() {
    for (name, syscall, when) in [
        ("map_char_u32_alloc_failure", "mmap", 1),
        ("map_char_u32_realloc_failure", "mremap", 1),
        ("map_char_u32_shrink_failure", "mremap", 1),
        ("map_char_u32_clone_failure", "mmap", 2),
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::fs::PermissionsExt;

            let executable = common::TempArtifact::new("laniusc_map", name, None);
            executable.write_bytes(&bytes);
            let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
            permissions.set_mode(0o700);
            std::fs::set_permissions(executable.path(), permissions).unwrap();

            let normal = common::short_process_output_with_timeout(
                format!("{name} normal allocation"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(normal.status.code(), Some(4), "{name}: {normal:?}");

            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_ok()
            {
                let trace = common::TempArtifact::new("laniusc_map", "trace", None);
                let injected = common::short_process_output_with_timeout(
                    format!("{name} injected allocation failure"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-o")
                        .arg(trace.path())
                        .arg("-e")
                        .arg(format!("trace={syscall}"))
                        .arg("-e")
                        .arg(format!("inject={syscall}:error=ENOMEM:when={when}"))
                        .arg(executable.path()),
                );
                assert_eq!(injected.status.code(), Some(0), "{name}: {injected:?}");
                let trace_text = std::fs::read_to_string(trace.path()).unwrap();
                assert!(trace_text.contains("INJECTED"), "{name}: {trace_text}");
                assert!(trace_text.contains("ENOMEM"), "{name}: {trace_text}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, when);
    }
}

#[test]
fn unicode_frequency_report_handles_input_and_failures() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/unicode_frequency_report.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("unicode frequency report", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unicode frequency report");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = common::TempArtifact::new("laniusc_map", "unicode_frequency", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected_code, expected_stdout) in [
            (b"".as_slice(), 0, b"".as_slice()),
            ("Ω😀Ωa".as_bytes(), 0, "Ω:2\n😀:1\na:1\n".as_bytes()),
            (b"\0a\0".as_slice(), 0, b"\0:2\na:1\n".as_slice()),
            (b"\xff".as_slice(), 2, b"".as_slice()),
            (b"\xf0\x9f".as_slice(), 2, b"".as_slice()),
        ] {
            let input = common::TempArtifact::new("laniusc_map", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "unicode frequency report",
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
            .unwrap();
        let input = common::TempArtifact::new("laniusc_map", "input_full", None);
        input.write_bytes("Ω".as_bytes());
        let status = std::process::Command::new("timeout")
            .arg("5s")
            .arg(executable.path())
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            ))
            .stdout(std::process::Stdio::from(full))
            .status()
            .expect("run with /dev/full stdout");
        assert_eq!(status.code(), Some(5), "{status:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
