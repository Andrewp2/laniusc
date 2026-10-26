#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("tests/fixtures/extended/http_exchange/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("HTTP Exchange fixture", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("{error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("http_exchange", "native", None);
        file.write_bytes(bytes);
        std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
fn group(name: &str) {
    let mut command = Command::new("python3");
    command
        .arg(root().join("tests/fixtures/extended/http_exchange/oracle.py"))
        .arg(executable().path())
        .arg(name);
    let output = common::process_output_with_timeout(
        "HTTP Exchange oracle",
        &mut command,
        Duration::from_secs(90),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    eprintln!("{summary}");
    assert!(
        summary.contains("owners and step boundaries checked"),
        "{summary}"
    );
}
#[test]
fn staged_request_lifetimes_pending_readiness_and_one_leaf_steps_execute() {
    group("steps");
}
#[test]
fn fragmented_information_chunk_fixed_and_close_prefixes_match_independent_oracles() {
    group("framing");
}
#[test]
fn early_final_head_stops_future_upload_and_half_closes_before_response_body() {
    group("early");
}
#[test]
fn prepared_abort_completion_and_sticky_failure_transfer_cleanup_once() {
    group("lifecycle");
}
#[test]
fn resumed_deadline_budget_leaf_faults_and_reached_allocations_preserve_progress_and_cleanup() {
    group("faults");
}
