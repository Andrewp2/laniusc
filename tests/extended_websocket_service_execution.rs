//! Public Hub ownership under native accept failures and the existing service oracle.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

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

fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/websocket_service")
        .join(name)
}

fn compile(path: &str, name: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["crypto".into()],
        ..Default::default()
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("WebSocket service native crypto", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("WebSocket service {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_websocket_service", name, None);
    std::fs::write(executable.path(), bytes).unwrap();
    let linked = common::process_output_with_timeout(
        "WebSocket service shared libraries",
        Command::new("readelf").arg("-d").arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("WebSocket service shared libraries", &linked);
    let dependencies = String::from_utf8(linked.stdout).unwrap();
    assert!(dependencies.contains("libcrypto.so.3"), "{dependencies}");
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn sample() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/ws_echo_server.lani", "echo"))
}

fn interposer() -> &'static common::TempArtifact {
    static SHIM: OnceLock<common::TempArtifact> = OnceLock::new();
    SHIM.get_or_init(|| {
        let shim = common::TempArtifact::new("laniusc_websocket_service", "so", None);
        let output = common::process_output_with_timeout(
            "WebSocket service OpenSSL fault interposer",
            Command::new("cc")
                .args([
                    "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-shared", "-fPIC",
                ])
                .arg(root().join("tests/fixtures/extended/websocket_upgrade/fault_interposer.c"))
                .arg("-o")
                .arg(shim.path())
                .args(["-ldl", "-lcrypto"]),
            Duration::from_secs(15),
        );
        common::assert_command_success("WebSocket service OpenSSL fault interposer", &output);
        shim
    })
}

fn checked_oracle(command: &mut Command, seconds: u64, expected: &str) {
    let output = common::process_output_with_timeout(
        "WebSocket service oracle",
        command,
        Duration::from_secs(seconds),
    );
    common::assert_command_success("WebSocket service oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim(), expected);
    eprint!("{summary}");
}

#[test]
fn websocket_service_existing_echo_oracle_uses_native_crypto() {
    checked_oracle(
        Command::new("python3")
            .arg("-B")
            .arg(fixture("echo_oracle.py"))
            .arg(sample().path()),
        70,
        "ws-service cases=89",
    );
}

#[test]
fn websocket_service_native_accept_errors_preserve_cause_http_ownership_and_capacity() {
    let probe = compile(
        "tests/fixtures/extended/websocket_service/crypto_probe.lani",
        "crypto_probe",
    );
    checked_oracle(
        Command::new("python3")
            .arg("-B")
            .arg(fixture("crypto_oracle.py"))
            .arg("hub")
            .arg(probe.path())
            .arg(interposer().path()),
        30,
        "ws-service-crypto-hub cases=4 failures=6 exact-causes=yes http-owned=yes recovered=yes",
    );
}

#[test]
fn websocket_service_sample_native_accept_failure_returns_500_and_keeps_http_usable() {
    checked_oracle(
        Command::new("python3")
            .arg("-B")
            .arg(fixture("crypto_oracle.py"))
            .arg("sample")
            .arg(sample().path())
            .arg(interposer().path()),
        30,
        "ws-service-crypto-sample cases=3 failures=6 status=500 http-reused=yes",
    );
}
