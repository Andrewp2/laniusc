#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn server() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let path = "sample_programs/library/http_static.lani";
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
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
        .unwrap_or_else(|e| panic!("{path}: {e}"));
        let exe = common::TempArtifact::new("laniusc_http_service", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

fn oracle(group: &str) -> String {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let out = common::process_output_with_timeout(
        "HTTP service loopback oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/http_service/oracle.py"))
            .arg(group)
            .arg(server().path()),
        Duration::from_secs(90),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    String::from_utf8(out.stdout).unwrap()
}

fn group(name: &str, expected: &str) {
    assert_eq!(oracle(name).trim(), format!("http-service-{name} {expected}"));
}

#[test]
fn http_service_event_server_static_files_listings_ranges_keepalive_and_chunked_echo() {
    group("functional", "cases=70 connections=9 requests=77 rejected=0 timeouts=0");
}

#[test]
fn http_service_event_server_rejects_malformed_framing_limits_and_versions() {
    group("malformed", "cases=45 connections=45 requests=2 rejected=41 timeouts=0");
}

#[test]
fn http_service_event_server_absolute_deadlines_bound_slowloris_without_queueing() {
    group("slowloris", "cases=12 connections=13 requests=7 rejected=5 timeouts=5");
}

#[test]
fn http_service_event_server_conditional_requests_and_validators() {
    group("conditional", "cases=23 connections=1 requests=23 rejected=0 timeouts=0");
}

#[test]
fn http_service_event_server_concurrent_clients_slowloris_slow_reader_and_idle_peers() {
    group("concurrent", "cases=39 connections=78 requests=254 rejected=8 timeouts=8");
}

#[test]
fn http_service_sequential_driver_matches_functional_malformed_slowloris_and_conditional() {
    group("functional-seq", "cases=70 connections=9 requests=77 rejected=0 timeouts=0");
    group("malformed-seq", "cases=45 connections=45 requests=2 rejected=41 timeouts=0");
    group("slowloris-seq", "cases=12 connections=13 requests=7 rejected=5 timeouts=5");
    group("conditional-seq", "cases=23 connections=1 requests=23 rejected=0 timeouts=0");
}
