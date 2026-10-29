//! Resumable raw and framed decompression with caller-owned workspace.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn execute(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/inflate_stream")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_inflate_stream", name, None);
    executable.write_bytes(bytes); // Applies shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_inflate_stream", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "pure resumable decoder contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{events}"
    );
    let mut launches = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") && line.ends_with("= 0") {
            launches += 1;
        } else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
        } else {
            panic!("caller-workspace decoding must have no intervening host effects: {events}");
        }
    }
    assert_eq!(launches, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
}
#[test]
fn resumable_inflate_stored_chunks_execute_exact_native_admission() {
    execute("admission.lani");
}
#[test]
fn resumable_inflate_fields_matches_errors_and_recycled_strided_buffers_execute() {
    execute("contracts.lani");
}
#[test]
fn resumable_inflate_metadata_reset_and_terminal_progress_preserve_caller_storage() {
    execute("preflight.lani");
}
#[test]
fn resumable_container_framing_checksums_members_limits_and_exact_progress_execute() {
    execute("framing.lani");
}
