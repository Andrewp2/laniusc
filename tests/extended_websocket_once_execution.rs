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
        let entry = root().join("sample_programs/library/websocket_once.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["ssl".into(), "crypto".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("WebSocket one-message application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("WebSocket one-message application: {error}"));
        let artifact = common::TempArtifact::new("websocket_once_app", "native", None);
        std::fs::write(artifact.path(), bytes).unwrap();
        let linked = common::process_output_with_timeout(
            "WebSocket one-message shared libraries",
            Command::new("readelf").arg("-d").arg(artifact.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("WebSocket one-message shared libraries", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"));
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("WebSocket one-message {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/websocket_once/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("WebSocket one-message {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("websocket-once-{mode} cases={cases} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn websocket_once_plain_coalesced_fragmented_binary_ping_and_clean_close_execute() {
    oracle("plain", 9);
}

#[test]
fn websocket_once_invalid_handshake_frame_utf8_and_unclean_close_publish_nothing() {
    oracle("rejection", 12);
}

#[test]
fn websocket_once_cli_input_limits_and_preflight_rejections_execute() {
    oracle("cli", 17);
}

#[test]
fn websocket_once_closed_output_input_failure_and_absolute_deadline_execute() {
    oracle("io", 3);
}

#[test]
fn websocket_once_verified_tls_versions_default_trust_and_identity_failures_execute() {
    oracle("tls", 5);
}
