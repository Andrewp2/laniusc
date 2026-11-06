#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn compile(path: &'static str, name: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    // wss:// goes through ext::tls_stream and the Accept digest through
    // ext::openssl_websocket, so the client links OpenSSL 3.
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_websocket_client", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn client() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/ws_cat.lani", "executable"))
}

fn crypto_interposer() -> &'static common::TempArtifact {
    static SHIM: OnceLock<common::TempArtifact> = OnceLock::new();
    SHIM.get_or_init(|| {
        let shim = common::TempArtifact::new("laniusc_websocket_client", "crypto.so", None);
        let out = common::process_output_with_timeout(
            "WebSocket client crypto fault interposer",
            Command::new("cc")
                .args([
                    "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-shared", "-fPIC",
                ])
                .arg(root().join("tests/fixtures/extended/websocket_upgrade/fault_interposer.c"))
                .arg("-o")
                .arg(shim.path())
                .args(["-ldl", "-lcrypto"]),
            Duration::from_secs(20),
        );
        common::assert_command_success("WebSocket client crypto fault interposer", &out);
        shim
    })
}

fn crypto_group(name: &str, executable: &common::TempArtifact, expected: &str) {
    let out = common::process_output_with_timeout(
        "WebSocket client crypto boundary",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root().join("tests/fixtures/extended/websocket_client/crypto_oracle.py"))
            .arg(name)
            .arg(executable.path())
            .arg(crypto_interposer().path()),
        Duration::from_secs(30),
    );
    common::assert_command_success("WebSocket client crypto boundary", &out);
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(String::from_utf8(out.stdout).unwrap().trim(), expected);
}

fn group(name: &str, expected: &str) {
    let out = common::process_output_with_timeout(
        "WebSocket client loopback oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/websocket_client/oracle.py"))
            .arg(name)
            .arg(client().path()),
        Duration::from_secs(90),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim(),
        format!("websocket-client-{name} {expected}")
    );
}

#[test]
fn ws_handshake_masking_lengths_fragments_control_frames_utf8_and_close() {
    group("ws", "cases=50 frames=65");
}

#[test]
fn wss_verifies_the_server_and_runs_the_same_cases_over_tls() {
    group("wss", "cases=52 frames=65");
}

#[test]
fn permessage_deflate_against_zlib_with_and_without_context_takeover() {
    group("deflate", "cases=24 frames=74");
}

#[test]
fn native_accept_failures_preserve_typed_cause_close_before_send_and_recover() {
    let executable = compile(
        "tests/fixtures/extended/websocket_client/crypto_probe.lani",
        "crypto-probe",
    );
    crypto_group(
        "typed",
        &executable,
        "websocket-client-crypto typed=3 zero-request=3 recovered=3 owners=balanced",
    );
}

#[test]
fn native_accept_failures_are_reported_as_crypto_by_ws_cat() {
    crypto_group(
        "sample",
        client(),
        "websocket-client-crypto sample=3 zero-request=3 diagnostic=crypto",
    );
}
