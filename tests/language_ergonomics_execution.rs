//! Language tests that are not `.lani` program tests.
//!
//! The x86_64 tests of `tests/fixtures/language` are the `//@` directives in
//! each file there. `laniusc test tests/fixtures/language` runs them; one
//! test below runs that command. The other tests here need a wasm host or a
//! fixture of another directory.

use crate::common;

use std::{
    path::PathBuf,
    process::{Command, Stdio},
};

use laniusc_compiler::compiler::compile_entry_to_wasm_with_stdlib;

/// Every `.lani` file below `tests/fixtures/language` with a `//@` directive
/// compiles and runs as the directive says.
#[test]
fn every_language_program_test_passes() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let laniusc = option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("target/release/laniusc"));
    let mut command = Command::new(laniusc);
    command
        .arg("test")
        .arg("--stdlib-root")
        .arg(root.join("stdlib"))
        .arg(root.join("tests/fixtures/language"))
        .stdin(Stdio::null());
    let output = common::codegen_command_output_with_timeout("laniusc test", &mut command);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(stdout.contains("test result: ok."), "{stdout}");
}

const ELSE_IF: &str = "1\n2\n3\n4\n5\n4\n3\n0\n1432\n10\n11\n12\n";

const LENGTHS: &str = "15\n3\n6\n5\n0\n6\n3\n3\n3\n2\n3\n";

#[test]
fn slice_len_and_string_len_count_on_wasm() {
    common::require_node();
    let fixture = "length_builtins.lani";
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    let wasm = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_wasm_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let stdout = common::run_wasm_main_with_node("language ergonomics", "length_builtins", &wasm);
    assert_eq!(stdout, LENGTHS);
}

#[test]
fn else_if_chains_take_the_first_true_arm_on_wasm() {
    common::require_node();
    let fixture = "else_if.lani";
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    let wasm = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_wasm_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let stdout = common::run_wasm_main_with_node("language ergonomics", "else_if", &wasm);
    assert_eq!(stdout, ELSE_IF);
}

// The resident workspace is sized by the largest unit checked so far; this
// preserved program's imports are larger than it. Name lookup must use the
// scope tree's published layout, not one derived from this unit's tokens.
#[test]
fn name_lookup_uses_the_scope_tree_layout_of_a_larger_workspace() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("tests/fixtures/stdlib_compiler_state/cli_match_shadow");
    let entry = fixture.join("original.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixture.join("extended")],
    };
    common::run_gpu_codegen_with_timeout("cli_match_shadow", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("cli_match_shadow/original.lani: {error}"));
}
