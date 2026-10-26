//! Actual persistent Server active-owner cap and cancellation controls.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn active_owner_caps_and_cancellation_preserve_cleanup_and_first_failure() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = "tests/fixtures/extended/server_poll_limits/main.lani";
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("server_poll_limits", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "persistent Server active-owner cap/cancel controls",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/server_poll_limits/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(30),
    );
    common::assert_command_success(
        "persistent Server active-owner cap/cancel controls",
        &output,
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"server-poll-limits cases=7\n");
}

#[test]
fn reached_poll_interruptions_reprepare_and_fatal_poll_errors_retire_live_owners() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = "tests/fixtures/extended/server_poll_limits/poll_faults.lani";
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("server_poll_faults", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "persistent Server reached poll faults",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/server_poll_limits/poll_faults_oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(55),
    );
    common::assert_command_success("persistent Server reached poll faults", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"server-poll-faults cases=2 calibration=1\n");
}
