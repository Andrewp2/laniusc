#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn build(path: &'static str, stem: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_http2_server", stem, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn engine() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| build("tests/fixtures/extended/http2_server/engine_pipe.lani", "engine"))
}

fn service() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| build("tests/fixtures/extended/http2_server/h2c_service.lani", "service"))
}

// The client is libnghttp2's client session (through ctypes); hand-built
// frames cover the protocol violations nghttp2 will not produce.
fn oracle(mode: &str, exe: &common::TempArtifact, expected: &str) {
    let out = common::process_output_with_timeout(
        "HTTP/2 server oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/http2_server/oracle.py"))
            .arg(mode)
            .arg(exe.path()),
        Duration::from_secs(120),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(String::from_utf8(out.stdout).unwrap().trim(), expected);
}

#[test]
fn http2_server_engine_against_nghttp2_client_and_raw_frames() {
    oracle("pipe", engine(), "http2-server-engine nghttp2=6 raw=18");
}

#[test]
fn http_service_serves_prior_knowledge_h2c_and_http1_on_one_listener() {
    oracle("tcp", service(), "http2-server-h2c nghttp2=6 raw=18 http1=1");
}
