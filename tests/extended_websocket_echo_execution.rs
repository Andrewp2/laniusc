#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

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

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/websocket_echo.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["ssl".into(), "crypto".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("WebSocket echo application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("WebSocket echo application: {error}"));
        let artifact = common::TempArtifact::new("websocket_echo_app", "native", None);
        std::fs::write(artifact.path(), bytes).unwrap();
        let linked = common::process_output_with_timeout(
            "WebSocket echo shared libraries",
            Command::new("readelf").arg("-d").arg(artifact.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("WebSocket echo shared libraries", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"));
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("WebSocket echo {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/websocket_echo/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("WebSocket echo {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("websocket-echo-{mode} cases={cases} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn websocket_echo_plain_binary_text_fragment_control_limits_origin_and_ipv6_execute() {
    oracle("plain", 11);
}

#[test]
fn websocket_echo_handshake_policy_and_syntax_rejections_execute() {
    oracle("handshake", 12);
}

#[test]
fn websocket_echo_protocol_utf8_limit_and_unclean_eof_failures_execute() {
    oracle("rejection", 10);
}

#[test]
fn websocket_echo_cli_errors_do_not_open_network_handles() {
    oracle("cli", 14);
}

#[test]
fn websocket_echo_verified_tls12_tls13_trust_and_shutdown_execute() {
    oracle("tls", 4);
}

#[test]
fn websocket_echo_bad_server_credentials_fail_before_listening() {
    oracle("credentials", 3);
}

#[test]
fn websocket_echo_absolute_deadline_bounds_waiting_for_a_client() {
    oracle("deadline", 1);
}

#[test]
fn websocket_echo_closed_readiness_stdout_reports_failure_after_listening() {
    oracle("io", 1);
}
