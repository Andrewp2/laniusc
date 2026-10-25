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
    let exe = common::TempArtifact::new("laniusc_http_server", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn http_server_owned_connection_accept_cleanup_native_admission() {
    let exe = compile("tests/fixtures/extended/http_server_admission.lani");
    let trace = common::TempArtifact::new("laniusc_http_server", "trace", None);
    let out = common::short_process_output_with_timeout(
        "HTTPserveradmission",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=socket,accept4,close,mmap,munmap"])
            .arg(exe.path()),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "{events}"
    );
    assert_eq!(
        events.lines().filter(|l| l.starts_with("close(")).count(),
        3,
        "{events}"
    );
}

fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/http_serve.lani"))
}
fn oracle(mode: &str, exe: &std::path::Path) -> String {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let out = common::process_output_with_timeout(
        "HTTP server loopback oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/http_server_oracle.py"))
            .arg(mode)
            .arg(exe),
        Duration::from_secs(45),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    let summary = String::from_utf8(out.stdout).unwrap();
    eprintln!("{summary}");
    summary
}
#[test]
fn http_server_retained_views_checked_date_preflight_and_exact_staged_send_retry_execute() {
    let exe = compile("tests/fixtures/extended/http_server_contracts.lani");
    assert!(oracle("native", exe.path()).contains("http-server-native cases=3"));
}
#[test]
fn http_server_ipv4_ipv6_binary_chunked_fragmented_expect_and_one_final_match_independent_clients()
{
    assert!(oracle("matrix", cli().path()).contains("http-server-matrix cases=30"));
}
#[test]
fn http_server_rejects_malformed_framing_under_caps_and_echoes_one_mebibyte() {
    assert!(oracle("limits", cli().path()).contains("http-server-limits-scale cases=16"));
}
#[test]
fn http_server_exact_drain_probe_late_success_progress_expect_preflight_and_cli_bounds_execute() {
    assert!(oracle("boundaries", cli().path()).contains("http-server-boundaries cases=25"));
}
#[test]
fn http_server_every_reached_allocation_leaf_io_retry_quota_close_and_real_stdio_faults_cleanup() {
    assert!(oracle("faults", cli().path()).contains("http-server-faults cases=35"));
}
