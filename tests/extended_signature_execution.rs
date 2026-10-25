//! Owned signature dispatch against independent OpenSSL and published vectors.
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
    let entry = root.join(format!("tests/fixtures/extended/signature/{stem}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("owned public signature dispatch", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("signature fixture {stem}: {e}"));
    let artifact = common::TempArtifact::new("laniusc_signature", stem, None);
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
        "independent signature OpenSSL peer",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/signature/model.py"))
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
    let input = common::TempArtifact::new("laniusc_signature", "input", None);
    input.write_bytes(&peer.stdout[24..24 + size]);
    let trace = common::TempArtifact::new("laniusc_signature", "memory", None);
    let actual = common::process_output_with_timeout(
        "native owned signature verification",
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
        "signature dispatch must allocate no backing"
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
        panic!("signature {group}, differing byte {at}, actual words {:?}, expected words {:?}, lengths {} vs {}",actual.stdout.get(start..end),expected.get(start..end),actual.stdout.len(),expected.len());
    }
    eprintln!("signature {group}: blocks={blocks}, commands={commands}");
}
#[test]
fn all_key_scheme_and_use_combinations_match_independent_openssl() {
    compare("matrix");
}
#[test]
fn malformed_and_inconsistent_signatures_match_independent_openssl() {
    compare("mutations");
}
#[test]
fn strict_spki_algorithm_identifiers_and_tls_ids_are_classified() {
    compare("encodings");
}
#[test]
fn metadata_and_shared_allowance_bridges_preserve_inputs_and_attempts() {
    compare("budgets");
}
#[test]
fn ordinary_consumer_imports_owns_classifies_and_verifies_all_families() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_signature", "plain_memory", None);
    let out = common::process_output_with_timeout(
        "ordinary owned signature consumer",
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
