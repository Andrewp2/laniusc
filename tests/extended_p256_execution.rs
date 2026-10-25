//! Portable P-256 native contracts against independent affine/OpenSSL/NIST data.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/p256")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("P-256", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("P-256 {name}: {e}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_p256", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_p256", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_p256", "trace", None);
    let output = common::process_output_with_timeout(
        "P-256 native without allocations",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(25),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "P-256 allocated"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}
#[derive(Debug)]
struct Case {
    wire: Vec<u8>,
    expected: Vec<u64>,
}
fn word(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn cases(group: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "CPU-only independent P-256 oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/p256/model.py"))
            .arg(group),
        Duration::from_secs(35),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let bytes = output.stdout;
    let count = word(&bytes, 0);
    assert!((200..=2048).contains(&count));
    let mut at = 8;
    let mut result = Vec::new();
    for _ in 0..count {
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((48..=3120).contains(&n));
        let wire = bytes[at..at + n].to_vec();
        at += n;
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((2..=67).contains(&n));
        let expected = (0..n).map(|i| word(&bytes, at + 8 * i)).collect();
        at += 8 * n;
        result.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    result
}
fn check(group: &str) {
    let cases = cases(group);
    for (batch_index, batch) in cases.chunks(16).enumerate() {
        let mut input = (batch.len() as u64).to_le_bytes().to_vec();
        for c in batch {
            input.extend(&c.wire);
        }
        let got = execute(protocol(), &input);
        let mut at = 0;
        for (index, c) in batch.iter().enumerate() {
            let n = c.expected.len();
            assert!(at + n <= got.len(), "short output");
            assert_eq!(
                &got[at..at + n],
                &c.expected,
                "{group} batch{batch_index} case{index}: {:02x?}",
                c.wire
            );
            at += n;
        }
        assert_eq!(at, got.len());
    }
    eprintln!(
        "P-256 {group}: {} commands, {} native batches",
        cases.len(),
        cases.len().div_ceil(16)
    );
}
#[test]
fn p256_ordinary_published_ecdh_ecdsa_and_return_copies() {
    let file = compile("plain");
    assert!(execute(&file, &[]).is_empty());
}
#[test]
fn p256_published_nist_ecdh_ecdsa_and_rfc_vectors() {
    check("published");
}
#[test]
fn p256_independent_affine_openssl_and_exceptional_group_cases() {
    check("model");
}
#[test]
fn p256_signature_public_digest_and_message_mutations() {
    check("mutations");
}
#[test]
fn p256_rejects_noncanonical_scalars_points_der_and_metadata() {
    check("invalid");
}
