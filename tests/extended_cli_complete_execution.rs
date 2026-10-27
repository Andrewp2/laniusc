//! Portable completion contexts and candidates through actual public modules.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn directory() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/extended/cli_complete")
}

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = directory().join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("portable completion {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("cli_complete_native", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn completion_context_candidate_atomicity_strides_and_forks_execute() {
    let executable = executable("contracts.lani");
    let output = common::process_output_with_timeout(
        "portable completion contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}

#[test]
fn completion_contexts_and_candidates_match_finite_transition_catalog_model() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "portable completion finite model",
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("model.py"))
            .arg(executable.path()),
        Duration::from_secs(25),
    );
    successful(&output);
    assert_eq!(output.stdout, b"cli-complete model cases=67\n");
}
