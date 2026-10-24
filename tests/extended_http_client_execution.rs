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
    let exe = common::TempArtifact::new("laniusc_http_client", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/http_fetch.lani"))
}
fn oracle(mode: &str, exe: &std::path::Path) -> String {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let out = common::process_output_with_timeout(
        "HTTP client loopback oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/http_client_oracle.py"))
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
fn http_client_native_owned_method_binary_body_interim_and_borrowed_response_contracts_execute() {
    let exe = compile("tests/fixtures/extended/http_client_contracts.lani");
    assert!(oracle("native", exe.path()).contains("http-client-native cases=1"));
}
#[test]
fn http_client_fixed_chunked_close_binary_headers_versions_and_fragmentation_match_independent_peers()
 {
    assert!(oracle("matrix", cli().path()).contains("http-client-matrix cases=47"));
}
#[test]
fn http_client_caps_exact_eof_probe_and_early_final_half_close_are_bounded() {
    assert!(oracle("limits", cli().path()).contains("http-client-limits-early-final cases=21"));
}
#[test]
fn http_client_rejects_truncation_smuggling_malformed_upgrades_and_request_injection() {
    assert!(oracle("failures", cli().path()).contains("http-client-failures cases=34"));
}
#[test]
fn http_client_each_reached_allocation_leaf_io_quota_late_results_and_cleanup_failures_execute() {
    assert!(oracle("faults", cli().path()).contains("http-client-faults cases="));
}
#[test]
fn http_client_cli_files_stream_faults_closed_pipes_and_output_cleanup_execute() {
    assert!(oracle("io", cli().path()).contains("http-client-io cases=12"));
}
