//! Explicit-anchor Ed25519 path policy against independently signed host chains.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/x509_path")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("X509 path", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("X509 path {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_x509_path", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn prepare(mode: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "independent libsodium/OpenSSL signed path corpus",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/x509_path/model.py"))
            .arg(mode),
        Duration::from_secs(30),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_x509_path", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_x509_path", "memory", None);
    let output = common::process_output_with_timeout(
        "allocation-free native certificate path gate",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(40),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "path validation must not allocate"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect()
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    assert!(*at + 8 <= bytes.len(), "short corpus at{at}");
    let value = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    value
}
#[derive(Debug)]
struct Case {
    wire: Vec<u8>,
    expected: Vec<u64>,
}
fn corpus(mode: &str) -> Vec<Case> {
    let bytes = prepare(mode);
    let mut at = 0;
    let count = word(&bytes, &mut at);
    assert!(count > 0 && count <= 512);
    let mut cases = Vec::new();
    for _ in 0..count {
        let length = word(&bytes, &mut at) as usize;
        assert!(length >= 112 && length <= 32768 && at + length <= bytes.len());
        let wire = bytes[at..at + length].to_vec();
        at += length;
        let count = word(&bytes, &mut at) as usize;
        assert!(count == 4 || count == 38);
        let expected = (0..count).map(|_| word(&bytes, &mut at)).collect();
        cases.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    cases
}
fn field(c: &Case, index: usize) -> u64 {
    u64::from_le_bytes(c.wire[index * 8..index * 8 + 8].try_into().unwrap())
}
fn check(cases: &[Case]) {
    let mut input = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        input.extend(&c.wire);
    }
    let actual = execute(protocol(), &input);
    let mut at = 0;
    for (index, c) in cases.iter().enumerate() {
        assert!(at + 8 <= actual.len(), "short case{index}");
        let report = &actual[at..at + 8];
        assert_eq!(report[0], c.expected[0], "case{index}: {c:?}");
        if c.expected[2] != u64::MAX {
            assert_eq!(
                report[1], c.expected[2],
                "exact certificate index case{index}"
            );
        }
        if c.expected[3] != u64::MAX {
            assert_eq!(report[2], c.expected[3], "exact anchor index case{index}");
        }
        assert!(
            report[1] <= field(c, 12) && report[2] <= field(c, 13),
            "error indices case{index}"
        );
        assert!(report[3] <= c.wire.len() as u64, "error offset case{index}");
        for (spent, limit) in [
            (report[4], field(c, 5)),
            (report[5], field(c, 6)),
            (report[6], field(c, 7)),
            (report[7], field(c, 8)),
        ] {
            assert!(spent <= limit, "budget underflow case{index}");
        }
        if c.expected[1] != u64::MAX {
            assert_eq!(report[4], c.expected[1], "signature attempts case{index}");
        }
        if (1..=8).contains(&c.expected[0]) {
            assert_eq!(
                &report[4..],
                &[0; 4],
                "argument preflight effects case{index}"
            );
        }
        at += 8;
        if c.expected[0] == 0 {
            assert!(at + 34 <= actual.len(), "short success case{index}");
            assert_eq!(
                &actual[at..at + 34],
                &c.expected[4..],
                "validated key/anchor/chain case{index}"
            );
            at += 34;
        }
    }
    assert_eq!(at, actual.len());
    eprintln!("X509 path independent commands: {}", cases.len());
}

#[test]
fn ordinary_path_consumer_returns_only_the_validated_leaf_key() {
    assert!(execute(&compile("plain"), &prepare("plain")).is_empty());
}
#[test]
fn ordered_signed_paths_match_independent_policy_and_shared_budget_cases() {
    check(&corpus("models"));
}
#[test]
fn supported_ed25519_paths_agree_with_openssl_verify() {
    check(&corpus("openssl"));
}
