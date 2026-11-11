//! Resumable filesystem traversal, checked against an independent host model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn probe() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_directory_cursor/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![],
        };
        let bytes = common::run_gpu_codegen_with_timeout("directory cursor probe", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry,
                    &roots,
                    &laniusc_compiler::compiler::NativeLinkOptions::default(),
                ),
            )
        })
        .unwrap_or_else(|error| panic!("directory cursor probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("directory_cursor", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        format!("directory cursor {group}"),
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_directory_cursor/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("directory cursor {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let receipt = String::from_utf8(output.stdout).unwrap();
    let count: usize = receipt
        .trim()
        .strip_prefix(&format!("directory-cursor group={group} cases="))
        .unwrap_or_else(|| panic!("missing cursor receipt: {receipt}"))
        .parse()
        .unwrap_or_else(|error| panic!("bad cursor receipt: {receipt}: {error}"));
    match group {
        "model" => assert_eq!(count, 6),
        "mutations" => assert_eq!(count, 9),
        "limits" => assert_eq!(count, 20),
        "faults" => assert!(count > 10),
        _ => panic!("unknown cursor gate {group}"),
    }
    print!("{receipt}");
}

#[test]
fn directory_cursor_resumption_pruning_and_borrowed_descriptors_execute() {
    gate("model");
}
#[test]
fn directory_cursor_anchoring_replacements_and_symlink_policy_execute() {
    gate("mutations");
}
#[test]
fn directory_cursor_limits_cancellation_and_terminal_states_execute() {
    gate("limits");
}
#[test]
fn directory_cursor_reached_allocation_and_io_failures_release_owners() {
    gate("faults");
}

#[test]
fn directory_cursor_observer_rejects_bad_reports_and_resource_traces() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "directory cursor observer controls",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_directory_cursor/host_controls.py")),
        Duration::from_secs(10),
    );
    common::assert_command_success("directory cursor observer controls", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"directory-cursor observer controls=39\n");
}
