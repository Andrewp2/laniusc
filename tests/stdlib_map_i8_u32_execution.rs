mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn signed_byte_map_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, expected_exit) in [
        ("map_i8_u32_complete", 0),
        ("map_i8_u32_short_backing", 101),
        ("map_i8_u32_short_values", 101),
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_exit);
    }
}

#[test]
fn every_signed_byte_map_function_has_an_executable_case() {
    let source = include_str!("../stdlib/std/map_i8_u32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/map_i8_u32_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("map function has a name");
        let call = format!("std::map_i8_u32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks an executable case");
        covered += 1;
    }
    assert_eq!(covered, 12);
}
