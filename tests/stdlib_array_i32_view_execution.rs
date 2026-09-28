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
fn borrowed_array_access_executes_across_fixed_lengths() {
    let bytes = compile_fixture("core_array_i32_view_complete");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("array_i32 view", "array_i32_view", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn each_public_array_function_has_an_executable_case() {
    let source = include_str!("../stdlib/core/array_i32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_array_i32_view_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else { continue; };
        let name = tail.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next().expect("array function name");
        let call = format!("core::array_i32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 2);
}

#[test]
fn physical_bounds_violations_trap() {
    for name in [
        "core_array_i32_view_bounds",
        "core_array_i32_view_negative",
        "core_array_i32_view_empty",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(101), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}
