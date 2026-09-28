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
fn character_conversion_and_every_vector_operation_execute() {
    for name in [
        "repro_i32_to_char",
        "repro_u32_to_char",
        "char_conversion_runtime",
        "vec_char",
        "vec_char_sort_search",
        "vec_char_lengths",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output("vec_char", name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let executable = common::TempArtifact::new("laniusc_vec_char", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn character_vector_allocation_failures_preserve_ownership() {
    for (name, syscall, when, normal_exit) in [
        ("vec_char_alloc_failure", "mmap", 1, 1),
        ("vec_char_realloc_failure", "mremap", 1, 4),
        ("vec_char_extend_realloc_failure", "mremap", 1, 4),
        ("vec_char_insert_realloc_failure", "mremap", 1, 4),
        ("vec_char_clone_alloc_failure", "mmap", 2, 4),
        ("vec_char_resize_realloc_failure", "mremap", 1, 4),
        ("vec_char_shrink_realloc_failure", "mremap", 1, 4),
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal"),
                &mut std::process::Command::new(executable.path()),
            );
            assert_eq!(
                normal.status.code(),
                Some(normal_exit),
                "{name}: {normal:?}"
            );
            if std::process::Command::new("strace")
                .arg("-V")
                .output()
                .is_err()
            {
                continue;
            }
            let trace = common::TempArtifact::new("laniusc_vec_char", "trace", None);
            let injected = common::short_process_output_with_timeout(
                format!("{name} injected {syscall} failure"),
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
            assert!(injected.stdout.is_empty() && injected.stderr.is_empty());
            let trace_text = std::fs::read_to_string(trace.path()).unwrap();
            assert!(trace_text.contains("INJECTED"), "{name}: {trace_text}");
            assert!(trace_text.contains("ENOMEM"), "{name}: {trace_text}");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, syscall, when, normal_exit);
    }
}

#[test]
fn unicode_sort_unique_program_handles_input_and_errors() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/unicode_sort_unique.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("unicode_sort_unique", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("unicode_sort_unique: compile: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "unicode_sort_unique");
        for (input_bytes, expected_code, expected_stdout) in [
            ("Ω😀éΩa".as_bytes(), 0, "aéΩ😀\n".as_bytes()),
            (b"", 0, b"\n"),
            (b"\xff", 2, b""),
            (b"\0a\0", 0, b"\0a\n"),
            (&[b'x'; 4097][..], 4, b""),
        ] {
            let input = common::TempArtifact::new("laniusc_vec_char", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "unicode_sort_unique input",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(expected_code), "{output:?}");
            assert_eq!(output.stdout, expected_stdout);
            assert!(output.stderr.is_empty());
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_character_vector_function_has_an_executed_call_site() {
    let source = include_str!("../stdlib/std/vec_char.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_foundation/vec_char.lani"),
        include_str!("fixtures/stdlib_foundation/vec_char_sort_search.lani"),
        include_str!("fixtures/stdlib_foundation/vec_char_lengths.lani"),
    ]
    .concat();
    let mut count = 0;
    for line in source.lines().filter(|line| line.starts_with("pub fn ")) {
        let name = line
            .trim_start_matches("pub fn ")
            .split('(')
            .next()
            .unwrap();
        assert!(
            fixtures.contains(&format!("std::vec_char::{name}(")),
            "public function {name} has no executed fixture call",
        );
        count += 1;
    }
    assert_eq!(count, 25);
    assert!(fixtures.contains("std::vec_char::MAX_CAPACITY"));
}
