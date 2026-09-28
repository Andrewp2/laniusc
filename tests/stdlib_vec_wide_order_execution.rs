mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn owned_signed_wide_vector_sort_and_search_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/vec_wide_i64_order.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("vec_wide_i64_order", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("vec_wide_i64_order: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("vec_wide_i64_order", "vec_wide_i64_order", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn owned_unsigned_wide_vector_sort_and_search_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/vec_wide_u64_order.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("vec_wide_u64_order", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("vec_wide_u64_order: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("vec_wide_u64_order", "vec_wide_u64_order", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn paired_word_sort_and_bounds_match_exhaustive_small_sequences() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/wide_word_cells_exhaustive.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide_word_cells_exhaustive", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("wide_word_cells_exhaustive: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "wide_word_cells_exhaustive",
            "wide_word_cells_exhaustive",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_paired_cell_function_has_an_executable_case() {
    let source = include_str!("../stdlib/core/wide_word_cells.lani");
    let unsigned = include_str!("fixtures/stdlib_foundation/vec_wide_u64_order.lani");
    let signed = include_str!("fixtures/stdlib_foundation/vec_wide_i64_order.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("paired-cell function has a name");
        let call = format!("core::wide_word_cells::{name}(");
        assert!(
            unsigned.contains(&call) && signed.contains(&call),
            "{call} lacks both runtime orders"
        );
        covered += 1;
    }
    assert_eq!(covered, 4);
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_vec_wide", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn wide_owned_median_programs_handle_full_width_input_and_failures() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, cases) in [
        (
            "sorted_wide_unsigned_median",
            [
                (
                    b"18446744073709551615\n0\n4294967296\n4294967296\n9223372036854775808\n"
                        .as_slice(),
                    0,
                    b"4294967296 2\n".as_slice(),
                ),
                (
                    b"0\n18446744073709551615\n".as_slice(),
                    0,
                    b"18446744073709551615 1\n".as_slice(),
                ),
                (b"7\n".as_slice(), 0, b"7 1\n".as_slice()),
                (b"".as_slice(), 2, b"".as_slice()),
                (b"\n".as_slice(), 2, b"".as_slice()),
                (b"1x\n".as_slice(), 3, b"".as_slice()),
                (b"18446744073709551616\n".as_slice(), 3, b"".as_slice()),
            ],
        ),
        (
            "sorted_wide_signed_median",
            [
                (
                    b"-9223372036854775808\n0\n-1\n-1\n9223372036854775807\n".as_slice(),
                    0,
                    b"-1 2\n".as_slice(),
                ),
                (
                    b"-9223372036854775808\n9223372036854775807\n".as_slice(),
                    0,
                    b"9223372036854775807 1\n".as_slice(),
                ),
                (b"-7\n".as_slice(), 0, b"-7 1\n".as_slice()),
                (b"".as_slice(), 2, b"".as_slice()),
                (b"\n".as_slice(), 2, b"".as_slice()),
                (b"1x\n".as_slice(), 3, b"".as_slice()),
                (b"9223372036854775808\n".as_slice(), 3, b"".as_slice()),
            ],
        ),
    ] {
        let entry = root.join(format!("sample_programs/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            for (input_bytes, expected_code, expected_stdout) in cases {
                let input = common::TempArtifact::new("laniusc_vec_wide", "median_input", None);
                input.write_bytes(input_bytes);
                let output = common::short_process_output_with_timeout(
                    name,
                    std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                        std::fs::File::open(input.path()).unwrap(),
                    )),
                );
                assert_eq!(
                    output.status.code(),
                    Some(expected_code),
                    "{name} {input_bytes:?}: {output:?}"
                );
                assert_eq!(
                    output.stdout, expected_stdout,
                    "{name} {input_bytes:?}: {output:?}"
                );
                assert!(
                    output.stderr.is_empty(),
                    "{name} {input_bytes:?}: {output:?}"
                );
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, cases);
    }
}

#[test]
fn paired_word_sort_traps_on_overclaimed_physical_backing() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/wide_word_cells_overclaim.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide_word_cells_overclaim", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("wide_word_cells_overclaim: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "wide_word_cells_overclaim",
            "wide_word_cells_overclaim",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(101), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
