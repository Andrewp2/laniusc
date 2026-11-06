//! Independent byte-conservation and provider-event models for buffered streams.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

const SUMMARY: &str = "caller-buffered-model histories=48 routes=3 cases=144 actions=1455 provider_calls=753 errors=450 handoffs=150 restores=138 empty_restores=6 bad_restores=60 fault_restores=39 empty_range_restores=84 fault_observations=177 read_bytes=120 accepted_bytes=435 seed=0xb0ffe0261121\n";

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_caller_buffered/model")
        .join(name)
}

#[test]
fn buffered_oracle_accepts_positive_controls_and_rejects_small_corruptions() {
    let output = common::process_output_with_timeout(
        "buffered oracle host controls",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg("controls"),
        Duration::from_secs(15),
    );
    common::assert_command_success("buffered oracle controls", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        format!("{SUMMARY}cpu-controls=22 rejected=22 initial-patterns=2 bytes=2672696\n")
    );
    eprint!("{summary}");
}

#[test]
fn independent_buffered_model_matches_all_bytes_events_and_handoffs() {
    let entry = fixture("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib")),
        user_roots: vec![fixture("")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("caller-backed buffered model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("caller-backed buffered model: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_caller_buffered", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent buffered byte ledger",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("independent buffered model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary, SUMMARY);
    eprint!("{summary}");
}
