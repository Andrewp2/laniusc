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
fn owned_i32_map_executes_on_x86() {
    let bytes = compile_fixture("map_i32_i32_complete");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("map_i32_i32", "map_i32_i32", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_i32_map_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/std/map_i32_i32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/map_i32_i32_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("map function has a name");
        let call = format!("std::map_i32_i32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 16);
}

#[test]
fn map_allocation_failures_preserve_owned_data() {
    for (name, syscall, when) in [
        ("map_i32_i32_alloc_failure", "mmap", 1),
        ("map_i32_i32_realloc_failure", "mremap", 1),
        ("map_i32_i32_shrink_failure", "mremap", 1),
        ("map_i32_i32_clone_failure", "mmap", 2),
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
fn byte_histogram_program_combines_map_numeric_and_io_helpers() {
    let bytes = compile_fixture("map_byte_histogram");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_map", "histogram", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        for (input_bytes, expected_stdout) in [
            (&b""[..], &b"0 0\n"[..]),
            (&b"abbccc"[..], &b"3 590\n"[..]),
            (&[0, 255, 255, 128][..], &b"3 638\n"[..]),
        ] {
            let input = common::TempArtifact::new("laniusc_map", "histogram_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "map byte histogram",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
