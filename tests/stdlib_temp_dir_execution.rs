//! Actual named temporary-directory owners with independent native observations.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn owner() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_execution/temp_dir/probe.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("TempDir owner", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("TempDir owner: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("laniusc_temp_dir", "owner", None);
        file.write_bytes(bytes);
        std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "TempDir native oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_execution/temp_dir/oracle.py"))
            .arg(group)
            .arg(owner().path()),
        Duration::from_secs(90),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("temp-dir group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap()
        .parse()
        .unwrap();
    assert!(count > 0);
    print!("{summary}");
}

#[test]
fn temp_dir_owns_real_children_and_retains_anchored_nonempty_recovery() {
    gate("owner");
}

#[test]
fn temp_dir_validates_preflight_and_bounds_real_entropy_and_collisions() {
    gate("admission_entropy");
}

#[test]
fn temp_dir_creation_faults_retain_every_confirmed_namespace_owner() {
    gate("creation_faults");
}

#[test]
fn temp_dir_cleanup_preserves_first_error_and_exact_retained_resources() {
    gate("cleanup_faults");
}
