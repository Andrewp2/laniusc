//! Public scan/nested adapters: executable smoke, state models and payload shapes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn directory() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/nested_iteration")
}

fn executable(name: &str) -> common::TempArtifact {
    let entry = directory().join(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("public nested iteration {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let result = common::TempArtifact::new("nested_iteration_native", name, None);
    result.write_bytes(bytes);
    std::fs::set_permissions(result.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    result
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn smoke(name: &str) {
    let program = executable(name);
    let output = common::process_output_with_timeout(
        name,
        &mut Command::new(program.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}

fn model(group: &str, name: &str, cases: usize) {
    let program = executable(name);
    let output = common::process_output_with_timeout(
        group,
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("model.py"))
            .arg(group)
            .arg(program.path()),
        Duration::from_secs(45),
    );
    successful(&output);
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("nested-iteration group={group} cases={cases}\n")
    );
}

#[test]
fn public_scan_callbacks_state_none_error_and_fusion_execute() {
    smoke("scan_smoke.lani");
}

#[test]
fn public_nested_callbacks_retirement_recovery_and_resumption_execute() {
    smoke("nested_smoke.lani");
}

#[test]
fn public_nested_actions_match_independent_shared_sequence_models() {
    model("nested", "nested_model.lani", 360);
}

#[test]
fn public_scan_actions_match_independent_shared_sequence_models() {
    model("scan", "scan_model.lani", 672);
}

#[test]
fn public_nested_generic_payloads_strided_views_and_zero_sized_items_execute() {
    smoke("shapes.lani");
}
