//! Ordinary Flatten/FlatMap: shared independent state oracle and plain payloads.
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
        .join("tests/fixtures/stdlib_foundation/infallible_nested_iteration")
}

fn executable(name: &str) -> common::TempArtifact {
    let entry = directory().join(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("ordinary nested iteration {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("infallible_nested_native", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn plain_nested_actions_match_existing_independent_sequence_oracle() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "ordinary nested iteration sequence model",
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("model.py"))
            .arg(executable.path()),
        Duration::from_secs(45),
    );
    successful(&output);
    assert_eq!(output.stdout, b"infallible-nested model cases=24\n");
}

#[test]
fn plain_nested_optional_wide_strides_zero_sized_and_composition_execute() {
    let executable = executable("shapes.lani");
    let output = common::process_output_with_timeout(
        "ordinary nested iteration plain items and composition",
        &mut Command::new(executable.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}
