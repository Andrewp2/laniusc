//! Minimal empty-enum layout reductions and diagnostic inhabited controls.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};

fn execute(name: &str) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_compiler_state/empty_enum_clone");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let exe = common::TempArtifact::new("empty_enum_layout", name, None);
    exe.write_bytes(bytes); // Retain the unchanged strict native checker.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{name}: {output:?}"
    );
}

#[test]
fn plain_result_return_with_empty_enum() {
    execute("plain_empty.lani");
}
#[test]
fn plain_result_return_with_inhabited_control() {
    execute("plain_inhabited.lani");
}
#[test]
fn direct_scalar_clone_with_empty_enum() {
    execute("direct_empty.lani");
}
#[test]
fn direct_scalar_clone_with_inhabited_control() {
    execute("direct_inhabited.lani");
}
#[test]
fn imported_generic_clone_with_empty_enum() {
    execute("imported_empty.lani");
}
#[test]
fn imported_generic_clone_with_inhabited_control() {
    execute("imported_inhabited.lani");
}
