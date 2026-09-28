mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn local_trait_methods_and_imported_scalar_wrappers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source) in [
        (
            "trait_local_scalar",
            "tests/fixtures/stdlib_foundation/trait_local_scalar.lani",
        ),
        (
            "trait_local_nominal",
            "tests/fixtures/stdlib_foundation/trait_local_nominal.lani",
        ),
        (
            "trait_local_value",
            "tests/fixtures/stdlib_foundation/trait_local_value.lani",
        ),
        (
            "core_cmp_free",
            "tests/fixtures/stdlib_foundation/core_cmp_free.lani",
        ),
        (
            "core_hash",
            "tests/fixtures/stdlib_foundation/core_hash.lani",
        ),
    ] {
        let entry = root.join(source);
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn every_public_cmp_free_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/cmp.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_cmp_free.lani");
    let mut count = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("comparison function has a name");
        let call = format!("core::cmp::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        count += 1;
    }
    assert_eq!(count, 6);
}
