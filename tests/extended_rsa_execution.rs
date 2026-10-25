//! Bounded RSA public verification against NIST anchors, OpenSSL EVP and Python pow.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn compile(stem: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended/rsa/{stem}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("bounded public RSA", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("RSA fixture {stem}: {e}"));
    let artifact = common::TempArtifact::new("laniusc_rsa", stem, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
fn checked(out: &std::process::Output) {
    assert_eq!(
        out.status.code(),
        Some(0),
        "stdout={} bytes, stderr={:?}",
        out.stdout.len(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.stderr.is_empty(), "{out:?}");
}
fn word(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap())
}
fn compare(group: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let peer = common::process_output_with_timeout(
        "independent RSA OpenSSL/pow peer",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/rsa/model.py"))
            .arg(group),
        Duration::from_secs(45),
    );
    checked(&peer);
    assert!(peer.stdout.len() >= 24);
    let size = word(&peer.stdout, 0) as usize;
    let commands = word(&peer.stdout, 8);
    let blocks = word(&peer.stdout, 16);
    assert!(size <= peer.stdout.len() - 24);
    let expected = &peer.stdout[24 + size..];
    assert!(!expected.is_empty());
    let input = common::TempArtifact::new("laniusc_rsa", "input", None);
    input.write_bytes(&peer.stdout[24..24 + size]);
    let trace = common::TempArtifact::new("laniusc_rsa", "memory", None);
    let actual = common::process_output_with_timeout(
        "native bounded RSA verification",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        Duration::from_secs(45),
    );
    checked(&actual);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "RSA must allocate no backing"
    );
    if actual.stdout != expected {
        let at = actual
            .stdout
            .iter()
            .zip(expected)
            .position(|(a, b)| a != b)
            .unwrap_or(actual.stdout.len().min(expected.len()));
        let start = (at / 8) * 8;
        let end = (start + 32).min(actual.stdout.len()).min(expected.len());
        panic!("RSA {group}, differing byte {at}, actual words {:?}, expected words {:?}, lengths {} vs {}",actual.stdout.get(start..end),expected.get(start..end),actual.stdout.len(),expected.len());
    }
    eprintln!("RSA {group}: blocks={blocks}, commands={commands}");
}
#[test]
fn published_sha256_vectors_and_bounded_key_profiles_match_openssl() {
    compare("published");
}
#[test]
fn inconsistent_representatives_and_both_emsa_formats_reject() {
    compare("rejected");
}
#[test]
fn canonical_rsae_key_and_signature_identifiers_are_checked() {
    compare("encodings");
}
#[test]
fn work_reservations_and_metadata_priority_preserve_inputs() {
    compare("budgets");
}
#[test]
fn ordinary_consumer_owns_public_key_and_verifies_messages_and_digests() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_rsa", "plain_memory", None);
    let out = common::process_output_with_timeout(
        "ordinary public RSA consumer",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&out);
    assert!(out.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
