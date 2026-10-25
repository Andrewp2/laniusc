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
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
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
fn p256_and_dual_group_connections_match_independent_openssl_ecdh() {
    peer("groups");
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
    assert_eq!(result.stdout, b"tls connection controls: 50 accepted\n");
}

#[test]
fn group_entropy_scalar_encoding_and_work_admission_boundaries_execute() {
    let exe = compile("groups");
    let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended/tls_connection/groups_peer.py");
    let result = common::process_output_with_timeout(
        "TLS group constructor and selected-share admission",
        Command::new("python3").arg(script).arg(exe.path()),
        Duration::from_secs(45),
    );
    checked(&result);
    assert_eq!(
        result.stdout,
        b"tls connection group admissions: 90 accepted\n"
    );
}

#[test]
fn sha384_only_suite_both_groups_and_publication_execute() {
    peer("hashes");
}
#[test]
fn sha384_late_binding_cross_hash_retry_and_cookie_execute() {
    peer("hash-retries");
}

#[test]
fn mixed_certificate_issuers_keep_real_ed25519_signer_and_full_epochs() {
    peer("signatures");
}
#[test]
fn actual_signature_offers_fallback_rejections_and_owned_key_retirement_execute() {
    peer("signature-policies");
}

#[test]
fn local_signing_shares_verification_work_and_attempt_boundary_after_credentials() {
    peer("signing-limits");
}

#[test]
fn local_signing_preflights_all_presign_protocol_work_before_shared_reservation() {
    peer("signing-protocol-limits");
}
