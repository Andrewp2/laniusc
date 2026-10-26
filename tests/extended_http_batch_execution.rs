//! Public concurrent HTTP batch behavior through real independently parsed peers.
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
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let path = "tests/fixtures/extended/http_batch/protocol.lani";
        let entry = root.join(path);
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(path, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("{path}: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        // This syscall-only ELF has no dynamic C runtime. Keep the existing
        // strict generated-function jump validation enabled.
        let file = common::TempArtifact::new("laniusc_http_batch", "protocol", None);
        file.write_bytes(bytes);
        std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}

fn oracle(mode: &str) -> String {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        &format!("HTTP batch {mode} oracle"),
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/http_batch/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(90),
    );
    assert_eq!(output.status.code(), Some(0), "{mode}: {output:?}");
    assert!(output.stderr.is_empty(), "{mode}: {output:?}");
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(
        text.contains(&format!("http-batch-{mode} cases=")),
        "{text}"
    );
    eprintln!("{text}");
    text
}

#[test]
fn batch_preflights_every_request_before_network_and_owns_taken_response_backing() {
    assert!(oracle("contracts").contains("cases=16"));
}

#[test]
fn batch_causal_waves_prove_overlap_cap_fair_refill_and_input_order() {
    assert!(oracle("overlap").contains("cases=5"));
}

#[test]
fn batch_independent_http_readers_cover_binary_framing_layouts_and_mixed_failures() {
    assert!(oracle("matrix").contains("cases=10"));
}

#[test]
fn batch_shared_deadline_budgets_and_retained_caps_cancel_without_losing_prior_results() {
    assert!(oracle("limits").contains("cases=18"));
}

#[test]
fn batch_leaf_poll_clock_and_repeated_interrupt_faults_close_all_owners_before_exit() {
    oracle("faults");
}

#[test]
fn every_reached_batch_allocation_failure_releases_active_pending_and_result_owners() {
    assert!(oracle("allocations").contains("allocation-positions="));
}

#[test]
fn consecutive_queued_begin_failures_refill_past_a_held_sibling_without_starvation() {
    assert!(oracle("refill-failures").contains("cases=1"));
}
