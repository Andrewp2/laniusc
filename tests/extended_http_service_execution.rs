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

#[test]
fn http_service_static_files_listings_ranges_keepalive_pipelining_and_chunked_echo() {
    assert_eq!(
        oracle("functional").trim(),
        "http-service-functional cases=69 connections=9 requests=76 rejected=0 timeouts=0"
    );
}

#[test]
fn http_service_rejects_malformed_framing_and_limits_with_typed_statuses() {
    assert_eq!(
        oracle("malformed").trim(),
        "http-service-malformed cases=42 connections=42 requests=2 rejected=38 timeouts=0"
    );
}

#[test]
fn http_service_absolute_head_body_and_idle_deadlines_bound_slowloris_clients() {
    assert_eq!(
        oracle("slowloris").trim(),
        "http-service-slowloris cases=12 connections=13 requests=7 rejected=5 timeouts=5"
    );
}
