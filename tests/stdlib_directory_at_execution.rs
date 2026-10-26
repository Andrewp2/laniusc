//! Checked descriptor-relative directory creation/removal and resource effects.
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
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let relative = "tests/fixtures/stdlib_execution/directory_at/probe.lani";
        let entry = root.join(relative);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(relative, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("{relative}: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_directory_at", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "directory-at native oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/stdlib_execution/directory_at/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("directory-at native oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII directory-at summary");
    let prefix = format!("directory-at group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap_or_else(|| panic!("missing native receipt: {summary:?}"))
        .parse()
        .unwrap_or_else(|error| panic!("invalid native count {summary:?}: {error}"));
    assert!(count > 0);
    print!("{summary}");
}

#[test]
fn directory_at_namespace_and_anchor_semantics_execute() {
    gate("namespace");
}

#[test]
fn directory_at_preflight_mode_and_path_bounds_execute() {
    gate("bounds");
}

#[test]
fn directory_at_native_failures_are_exact_and_one_attempt() {
    gate("faults");
}
