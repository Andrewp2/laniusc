#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
fn compile(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
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
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_dns_client", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/dns_query.lani"))
}
fn oracle(mode: &str, exe: &std::path::Path) -> String {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let python = root.join("target/stdlib-work/dns-oracle-venv/bin/python");
    assert!(
        python.exists(),
        "test-only isolated dnspython==2.7.0 venv required; see docs/extended-dns-client.md"
    );
    let out = common::process_output_with_timeout(
        "DNS client loopback oracle",
        Command::new(python)
            .arg(root.join("tests/fixtures/extended/dns_client_oracle.py"))
            .arg(mode)
            .arg(exe),
        Duration::from_secs(75),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    let summary = String::from_utf8(out.stdout).unwrap();
    eprintln!("{summary}");
    summary
}
#[test]
fn dns_client_native_counted_strided_name_owned_response_and_borrowed_records_execute() {
    let exe = compile("tests/fixtures/extended/dns_client_contracts.lani");
    assert!(oracle("native", exe.path()).contains("native-contract cases=1"));
}
#[test]
fn dns_client_udp_tcp_fallback_binary_names_rcodes_edns_and_large_frames_match_independent_peer() {
    assert!(oracle("matrix", cli().path()).contains("transport-matrix cases=19"));
}
#[test]
fn dns_client_correlates_sources_ids_complete_questions_and_bounds_junk_retry_windows() {
    assert!(oracle("junk", cli().path()).contains("correlation-retries cases=13"));
}
#[test]
fn dns_client_rejects_malformed_frames_incomplete_replies_and_resource_limits_without_output() {
    assert!(oracle("failures", cli().path()).contains("transport-failures cases=42"));
}
#[test]
fn dns_client_all_reached_allocations_socket_io_entropy_clock_and_late_successes_cleanup() {
    assert!(oracle("faults", cli().path()).contains("transport-faults cases="));
}

#[test]
fn dns_client_cli_stages_output_and_cleans_up_real_broken_pipes_and_io_faults() {
    assert!(oracle("io", cli().path()).contains("cli-io-faults cases=9"));
}

#[test]
fn dns_client_preserves_truncation_before_close_failure_and_receive_stage_on_retry_exhaustion() {
    assert!(oracle("precedence", cli().path()).contains("error-precedence cases=5"));
}
