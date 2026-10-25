//! Portable TLS engines; independent peers validate the exact emitted records.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/tls_connection")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("portable TLS connection", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("TLS connection {name}: {e}"));
    let exe = common::TempArtifact::new("laniusc_tls_connection", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
fn checked(result: &std::process::Output) {
    assert_eq!(
        result.status.code(),
        Some(0),
        "stdout={:?}, stderr={:?}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
    assert!(
        result.stderr.is_empty(),
        "{:?}",
        String::from_utf8_lossy(&result.stderr)
    );
}
fn peer(mode: &str) {
    let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended/tls_connection/peer.py");
    let result = common::process_output_with_timeout(
        "independent TLS connection record/checkpoint oracle",
        Command::new("python3")
            .arg(script)
            .arg(mode)
            .arg(protocol().path()),
        Duration::from_secs(48),
    );
    checked(&result);
    assert_eq!(
        result.stdout,
        format!("tls connection {mode}: accepted\n").as_bytes()
    );
}

#[test]
fn ordinary_connection_storage_and_pending_wire_consumer_executes() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_tls_connection", "plain_memory", None);
    let result = common::process_output_with_timeout(
        "ordinary portable connection without allocation",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk", "-e", "signal=none"])
            .arg(exe.path()),
        Duration::from_secs(15),
    );
    checked(&result);
    assert!(result.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn paired_connections_match_independent_wire_epochs_and_authentication() {
    peer("pairs");
}

#[test]
fn fragmented_long_certificate_and_both_hello_retry_modes_execute() {
    peer("fragments");
}

#[test]
fn connection_error_atomicity_and_record_epoch_boundaries_execute() {
    let exe = compile("controls");
    let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended/tls_connection/controls_peer.py");
    let result = common::process_output_with_timeout(
        "independent TLS error, publication and record-limit controls",
        Command::new("python3").arg(script).arg(exe.path()),
        Duration::from_secs(40),
    );
    checked(&result);
    assert_eq!(result.stdout, b"tls connection controls: 44 accepted\n");
}
