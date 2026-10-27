//! Real nested iterator owners, pre-exit cleanup and reached source faults.
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
        let entry = root.join("tests/fixtures/stdlib_execution/nested_iteration_owners/probe.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("nested iterator owners", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("nested iterator owner probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_nested_iteration_owners", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "nested iterator ownership oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("nested iterator ownership oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("PASS nested-owners group={group} cases=");
    let receipts: Vec<(usize, usize)> = summary
        .lines()
        .filter_map(|line| line.strip_prefix(&prefix))
        .map(|receipt| {
            let (cases, denials) = receipt
                .split_once(" reached-oom=")
                .expect("finite cases and reached OOM count");
            (cases.parse().unwrap(), denials.parse().unwrap())
        })
        .collect();
    assert_eq!(receipts.len(), 1, "{summary}");
    let (cases, denials) = receipts[0];
    if group == "lifecycle" {
        assert_eq!((cases, denials), (14, 0), "{summary}");
    } else {
        assert!(denials > 0 && cases > denials, "{summary}");
    }
    print!("{summary}");
}

#[test]
fn nested_owners_recover_actual_partial_state_before_explicit_release() {
    gate("lifecycle");
}

#[test]
fn flatten_every_reached_owner_allocation_failure_releases_before_exit() {
    gate("flatten-oom");
}

#[test]
fn flat_map_vec_every_reached_allocation_including_resume_is_recoverable() {
    gate("flatmap-oom-vec");
}

#[test]
fn flat_map_wrapped_deque_every_reached_allocation_including_resume_is_recoverable() {
    gate("flatmap-oom-deque");
}
