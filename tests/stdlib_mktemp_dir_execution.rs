//! Real TempDir CLI effects and verified reached fault schedules.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/mktemp_dir.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("mktemp_dir application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("mktemp_dir: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_mktemp_dir", "application", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut command = Command::new("python3");
    command
        .arg(root.join("tests/fixtures/stdlib_execution/mktemp_dir/oracle.py"))
        .arg(group)
        .arg(executable().path());
    let output = common::process_output_with_timeout(
        "mktemp_dir native application oracle",
        &mut command,
        Duration::from_secs(70),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("mktemp-dir group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap_or_else(|| panic!("missing receipt: {summary:?}"))
        .parse()
        .unwrap();
    assert!(count > 0, "no native cases executed");
    print!("{summary}");
}

#[test]
fn mktemp_dir_creates_new_empty_private_directories_and_publishes_exact_names() {
    gate("normal");
}

#[test]
fn mktemp_dir_argument_and_path_admission_has_no_creation_effects() {
    gate("arguments");
}

#[test]
fn mktemp_dir_all_reached_source_ooms_release_owners_before_exit() {
    gate("allocations");
}

#[test]
fn mktemp_dir_reached_host_output_and_cleanup_failures_preserve_publication_truth() {
    gate("faults");
}
