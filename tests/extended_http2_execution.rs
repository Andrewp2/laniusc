#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn driver() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let path = "tests/fixtures/extended/http2/engine_driver.lani";
        let entry = root().join(path);
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(path, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("{path}: {e}"));
        let exe = common::TempArtifact::new("laniusc_http2_engine", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

// The servers are libnghttp2 server sessions (through ctypes) and hand-built
// frames for the protocol violations nghttp2 will not produce.
fn group(name: &str, expected: &str) {
    let out = common::process_output_with_timeout(
        "HTTP/2 engine loopback oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/http2/engine_oracle.py"))
            .arg(name)
            .arg(driver().path()),
        Duration::from_secs(90),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim(),
        format!("http2-engine-{name} {expected}")
    );
}

#[test]
fn http2_engine_against_nghttp2_server_streams_flow_control_and_control_frames() {
    group("nghttp2", "cases=17");
}

#[test]
fn http2_engine_detects_connection_and_stream_errors_from_raw_frames() {
    group("raw", "cases=46");
}
