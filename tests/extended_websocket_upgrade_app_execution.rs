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
        let entry = root().join("sample_programs/library/websocket_upgrade.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["crypto".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("WebSocket upgrade application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("WebSocket upgrade application: {error}"));
        let artifact = common::TempArtifact::new("websocket_upgrade_app", "native", None);
        std::fs::write(artifact.path(), bytes).unwrap();
        let linked = common::process_output_with_timeout(
            "WebSocket upgrade shared libraries",
            Command::new("readelf").arg("-d").arg(artifact.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("WebSocket upgrade shared libraries", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(dependencies.contains("libcrypto.so.3"), "{dependencies}");
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("WebSocket upgrade {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/websocket_upgrade_app/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(50),
    );
    common::assert_command_success(format!("WebSocket upgrade {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("websocket-upgrade-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn websocket_upgrade_rfc_fresh_keys_exact_protocols_and_boundaries_execute() {
    oracle("functional", 22);
}

#[test]
fn websocket_upgrade_malformed_incomplete_trailing_and_over_limit_requests_emit_nothing() {
    oracle("rejection", 30);
}

#[test]
fn websocket_upgrade_cli_help_and_argument_errors_execute() {
    oracle("cli", 15);
}

#[test]
fn websocket_upgrade_closed_readers_and_input_failure_preserve_status() {
    oracle("io", 4);
}
