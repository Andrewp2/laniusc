//! Named temporary ownership and checked descriptor-relative filesystem calls.
//! Native effects, entropy provenance and resource cleanup use an independent
//! host oracle. Production behavior is entirely in Lanius.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn compile(name: &'static str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let relative = format!("tests/fixtures/stdlib_execution/temp_file/{name}");
    let entry = root.join(&relative);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(&relative, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{relative}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_temp_file", name, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}

fn owner() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("probe.lani"))
}

fn primitives() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("primitives.lani"))
}

fn bounds() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("bounds.lani"))
}

fn gate(group: &str, file: &common::TempArtifact, second: Option<&common::TempArtifact>) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let script = root.join("tests/fixtures/stdlib_execution/temp_file/oracle.py");
    let mut command = Command::new("python3");
    command.arg(script).arg(group).arg(file.path());
    if let Some(other) = second {
        command.arg(other.path());
    }
    let output = common::process_output_with_timeout(
        "owned temporary-file native oracle",
        &mut command,
        Duration::from_secs(70),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII acceptance summary");
    let prefix = format!("temp-file group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap_or_else(|| panic!("missing finite native receipt: {summary:?}"))
        .parse()
        .unwrap_or_else(|error| panic!("invalid native case count {summary:?}: {error}"));
    assert!(count > 0, "no native cases executed");
    print!("{summary}");
}

#[test]
fn temp_file_owner_executes_binary_empty_keep_cleanup_and_anchoring() {
    gate("owner", owner(), None);
}

#[test]
fn temp_file_collisions_and_excluded_destinations_use_bounded_os_entropy() {
    gate("collisions", owner(), None);
}

#[test]
fn temp_file_validation_rejects_bad_names_limits_and_parent_descriptors() {
    gate("validation", owner(), None);
}

#[test]
fn temp_file_faults_retain_recovery_authority_and_retire_resources_once() {
    gate("faults", owner(), None);
}

#[test]
fn temp_file_primitives_execute_relative_paths_policies_and_checked_bounds() {
    gate("primitives", primitives(), Some(bounds()));
}
