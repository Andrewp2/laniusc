//! Actual Lanius atomic publication; independent host namespace/resource oracle.
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
    let relative = format!("tests/fixtures/stdlib_execution/atomic_file/{name}");
    let entry = root.join(&relative);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(&relative, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{relative}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_atomic_file", name, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}

fn probe() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("probe.lani"))
}

fn gate(group: &str, executable: &common::TempArtifact) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "owned atomic-file native oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/stdlib_execution/atomic_file/oracle.py"))
            .arg(group)
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("owned atomic-file native oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII acceptance summary");
    let prefix = format!("atomic-file group={group} cases=");
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
fn atomic_file_publishes_binary_empty_large_and_anchored_destinations() {
    gate("owner", probe());
}

#[test]
fn atomic_file_publication_orders_syncs_caches_commit_and_retries_directory_sync() {
    gate("publication", probe());
}

#[test]
fn atomic_file_faults_preserve_visibility_prefix_recovery_and_cleanup() {
    gate("faults", probe());
}

#[test]
fn atomic_file_validates_views_limits_and_bounded_write_attempts() {
    gate("bounds", probe());
}
