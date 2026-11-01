//! Ordered navigation: exact policy call sequences, interval edges, prefix families and bounds.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_ordered_navigation/direct").join(name)
}
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_ordered_navigation", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
// The fixture checks its own owner fields and release counts; no tracer runs.
fn execute(name: &str) {
    let executable = executable(name);
    let output = common::process_output_with_timeout(
        "ordered navigation contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success(name, &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn ordered_navigation_calls_edges_prefix_families_and_owner_release_execute() { execute("contracts.lani"); }
#[test]
fn ordered_navigation_requires_exact_comparator_and_same_key_order_when_empty() {
    for name in ["negative_tree_map_missing_comparator.lani", "negative_tree_set_reversed_comparator.lani",
        "negative_tree_map_range_bounds_without_ord.lani", "negative_tree_set_last_at_most_without_ord.lani"] {
        let error = compile(name).expect_err("empty ordered collections still require navigation capabilities");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(label.source_line.as_deref().unwrap_or("").contains("rejected_navigation_bound"), "{name}: {label:?}");
    }
}
