//! Checked links/readlink/permission effects with independent native oracles.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn probe() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_execution/filesystem_links/probe.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("filesystem link primitives", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("filesystem link probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_filesystem_links", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "filesystem links native oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_execution/filesystem_links/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("filesystem links native oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("PASS filesystem-links group={group} cases=");
    let counts: Vec<usize> = summary
        .lines()
        .filter_map(|line| line.strip_prefix(&prefix))
        .map(|count| count.parse().expect("finite native case count"))
        .collect();
    assert_eq!(counts.len(), 1, "{summary}");
    assert!(counts[0] > 0, "{summary}");
    print!("{summary}");
}

#[test]
fn hard_links_and_symlinks_preserve_inode_policy_and_never_replace() {
    gate("links");
}

#[test]
fn readlink_reports_exact_completeness_with_strided_alias_outputs() {
    gate("readlink");
}

#[test]
fn descriptor_and_path_permissions_preserve_open_file_state() {
    gate("permissions");
}

#[test]
fn link_and_permission_preflights_preserve_destinations_without_syscalls() {
    gate("bounds");
}

#[test]
fn reached_link_and_permission_faults_are_one_attempt_and_atomic() {
    gate("faults");
}
