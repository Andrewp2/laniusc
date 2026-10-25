//! Explicit-anchor ordered paths against independently signed host chains.
//! Multi-algorithm integration admission is pending; historical Ed25519 gates remain.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn output_summary(output: &std::process::Output) -> String {
    format!(
        "status={}, stdout_len={}, stdout_prefix={:02x?}, stderr_len={}, stderr_prefix={:?}",
        output.status,
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(32)],
        output.stderr.len(),
        String::from_utf8_lossy(&output.stderr[..output.stderr.len().min(512)])
    )
}

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
    assert!(output.status.success(), "{}", output_summary(&output));
    assert!(output.stderr.is_empty(), "{}", output_summary(&output));
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
    assert_eq!(output.status.code(), Some(0), "{}", output_summary(&output));
    assert!(output.stderr.is_empty(), "{}", output_summary(&output));
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
        assert_eq!(
            report[0],
            c.expected[0],
            "case{index}: layout={}, wire_len={}, expected_prefix={:?}",
            field(c, 0),
            c.wire.len(),
            &c.expected[..c.expected.len().min(8)]
        );
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

fn mixed_protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("mixed"))
}
fn mixed_corpus(mode: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "independent OpenSSL mixed-family path corpus",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/x509_path/mixed.py"))
            .arg(mode),
        Duration::from_secs(40),
    );
    assert!(output.status.success(), "{}", output_summary(&output));
    assert!(output.stderr.is_empty(), "{}", output_summary(&output));
    let bytes = output.stdout;
    let mut at = 0;
    let count = word(&bytes, &mut at);
    assert!(count > 0 && count <= 128);
    let mut cases = Vec::new();
    for _ in 0..count {
        let length = word(&bytes, &mut at) as usize;
        assert!((72..=32768).contains(&length) && at + length <= bytes.len());
        let wire = bytes[at..at + length].to_vec();
        at += length;
        let count = word(&bytes, &mut at) as usize;
        assert!(count == 4 || count == 8);
        let expected = (0..count).map(|_| word(&bytes, &mut at)).collect();
        cases.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    cases
}
fn mixed_check(cases: &[Case]) -> Vec<[u64; 8]> {
    let mut input = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        input.extend(&c.wire);
    }
    let actual = execute(mixed_protocol(), &input);
    let mut at = 0;
    let mut reports = Vec::new();
    for (index, c) in cases.iter().enumerate() {
        assert!(at + 8 <= actual.len(), "short mixed case{index}");
        let report: [u64; 8] = actual[at..at + 8].try_into().unwrap();
        at += 8;
        assert_eq!(
            report[0],
            c.expected[0],
            "mixed case{index}: layout={}, wire_len={}, expected_prefix={:?}",
            field(c, 0),
            c.wire.len(),
            &c.expected[..c.expected.len().min(8)]
        );
        for (actual, expected) in report[1..3].iter().zip(&c.expected[2..4]) {
            if *expected != u64::MAX {
                assert_eq!(actual, expected, "mixed indexed error case{index}");
            }
        }
        assert!(report[1] <= field(c, 5) && report[2] <= field(c, 6));
        assert!(report[3] <= c.wire.len() as u64);
        for (spent, limit) in [
            (report[4], field(c, 4)),
            (report[5], field(c, 3)),
            (report[6], 100_000),
            (report[7], 16_777_216),
        ] {
            assert!(spent <= limit, "mixed budget underflow case{index}");
        }
        if c.expected[1] != u64::MAX {
            assert_eq!(report[4], c.expected[1], "mixed attempts case{index}");
        }
        if field(c, 1) == 6 || field(c, 1) == 7 || field(c, 2) >= 6 {
            assert_eq!(&report[4..], &[0; 4], "mixed preflight case{index}");
        }
        if c.expected[0] == 0 {
            assert!(at + 3 <= actual.len());
            assert_eq!(
                &actual[at..at + 3],
                &c.expected[4..7],
                "mixed owned leaf kind/anchor/count case{index}"
            );
            at += 3;
            if c.expected[7] != u64::MAX {
                assert_eq!(
                    report[5], c.expected[7],
                    "independent path/storage/key work case{index}"
                );
            }
        }
        reports.push(report);
    }
    assert_eq!(at, actual.len());
    eprintln!("mixed X509 path commands: {}", cases.len());
    reports
}
#[test]
fn mixed_issuer_families_policies_cache_retirement_and_openssl_paths() {
    mixed_check(&mixed_corpus("models"));
}
#[test]
fn mixed_paths_share_exact_work_and_signature_admission_without_cache_reuse() {
    let baselines = mixed_corpus("seams");
    let reports = mixed_check(&baselines);
    let expected_spent: Vec<u64> = reports.iter().map(|report| report[5]).collect();
    let mut seams = Vec::new();
    for (c, report) in baselines.iter().zip(reports) {
        assert_eq!(report[0], 0);
        let spent = report[5];
        assert!(spent > 0);
        for (limit, status) in [(spent - 1, 11), (spent, 0), (spent + 1, 0)] {
            let mut wire = c.wire.clone();
            wire[24..32].copy_from_slice(&limit.to_le_bytes());
            let mut expected = c.expected.clone();
            expected[0] = status;
            if status != 0 {
                // A denied RSA operation can retain admitted setup charges;
                // the shared dispatch owns attempt reservation semantics.
                expected[1] = u64::MAX;
                expected.truncate(4);
            }
            seams.push(Case { wire, expected });
        }
    }
    let observed = mixed_check(&seams);
    for (index, group) in observed.chunks_exact(3).enumerate() {
        assert_eq!(group[1][5], expected_spent[index]);
        assert_eq!(group[1][4..], group[2][4..]);
    }
}
