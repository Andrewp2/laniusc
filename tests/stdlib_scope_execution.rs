//! std::scope: scoped stacks (docs/memory-scoped-stacks-design.md, phase S0).

mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

// The fixture returns 0, or the number of the first check that failed.
#[test]
fn stacks_grow_both_ends_in_place_and_release_to_marks() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_scope/semantics.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("stdlib_scope", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("std::scope semantics: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("stdlib scope", "semantics", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
