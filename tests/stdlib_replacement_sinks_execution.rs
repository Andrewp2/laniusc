//! Actual replacement delegates and helper: state models and payload ownership tags.
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
        .join("tests/fixtures/stdlib_foundation/replacement_sinks")
}

fn executable(name: &str) -> common::TempArtifact {
    let entry = directory().join(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("replacement sinks {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let program = common::TempArtifact::new("replacement_sinks_native", name, None);
    program.write_bytes(bytes);
    std::fs::set_permissions(program.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    program
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn replacement_sink_phases_identity_progress_retry_and_all_facades_match_model() {
    let program = executable("model.lani");
    let output = common::process_output_with_timeout(
        "replacement sink independent model",
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("model.py"))
            .arg(program.path()),
        Duration::from_secs(45),
    );
    successful(&output);
    assert_eq!(output.stdout, b"replacement-sinks model cases=53\n");
}

#[test]
fn replacement_sink_nested_optional_wide_zero_sized_and_duplicate_policies_execute() {
    let program = executable("shapes.lani");
    let output = common::process_output_with_timeout(
        "replacement sink generic payloads and existing duplicate policy",
        &mut Command::new(program.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}
