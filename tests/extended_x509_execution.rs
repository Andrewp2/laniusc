//! Borrowed X.509 schema parsing; host corpora never supply production behavior.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/x509")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("X509", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("X509 {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_x509", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_x509", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_x509", "trace", None);
    let output = common::process_output_with_timeout(
        "X509 native execution without allocation",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "X509 allocates nothing"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}
#[derive(Clone, Debug)]
struct Case {
    wire: Vec<u8>,
    expected: Vec<u64>,
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let result = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    result
}
fn prepare(mode: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "independent X509 schema/certificate corpus",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/x509/model.py"))
            .arg(mode),
        Duration::from_secs(40),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let (mut at, mut cases) = (0, Vec::new());
    let count = word(&output.stdout, &mut at);
    assert!(count <= 4096);
    for _ in 0..count {
        let length = word(&output.stdout, &mut at) as usize;
        assert!(length >= 48 && length <= 16432);
        let wire = output.stdout[at..at + length].to_vec();
        at += length;
        let length = word(&output.stdout, &mut at) as usize;
        let expected = (0..length).map(|_| word(&output.stdout, &mut at)).collect();
        cases.push(Case { wire, expected });
    }
    assert_eq!(at, output.stdout.len());
    cases
}
fn real_cases() -> &'static Vec<Case> {
    static CASES: OnceLock<Vec<Case>> = OnceLock::new();
    CASES.get_or_init(|| prepare("openssl"))
}
fn check(cases: &[Case]) {
    let mut input = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        input.extend(&c.wire);
    }
    let actual = execute(protocol(), &input);
    let mut at = 0;
    for (index, c) in cases.iter().enumerate() {
        if (c.expected[0] as i64) < 0 {
            let wanted = c.expected[0].wrapping_neg();
            assert!(at + 2 <= actual.len(), "short error output case{index}");
            assert_eq!(
                actual[at], wanted,
                "X509 rejection case{index}, wire={:02x?}",
                c.wire
            );
            let length = u64::from_le_bytes(c.wire[40..48].try_into().unwrap());
            assert!(actual[at + 1] <= length, "offset outside root case{index}");
            if wanted <= 2 {
                assert_eq!(actual[at + 1], 0, "preflight offset case{index}");
            }
            if c.expected.len() == 2 {
                assert_eq!(
                    actual[at + 1],
                    c.expected[1],
                    "nested root offset case{index}"
                );
            }
            at += 2;
        } else {
            let end = at + c.expected.len();
            assert!(end <= actual.len(), "short success output case{index}");
            assert_eq!(
                &actual[at..end],
                c.expected,
                "X509 borrowed schema case{index}, wire={:02x?}",
                c.wire
            );
            at = end;
        }
    }
    assert_eq!(at, actual.len());
    eprintln!("X509 independent commands: {}", cases.len());
}
#[test]
fn ordinary_x509_consumer_does_not_project_errors() {
    let bytes = &real_cases()[0].wire[48..];
    let mut input = (bytes.len() as u64).to_le_bytes().to_vec();
    input.extend(bytes);
    assert!(execute(&compile("plain"), &input).is_empty());
}
#[test]
fn x509_independent_schema_and_budget_models() {
    let cases = prepare("models");
    assert!(cases.len() > 500);
    check(&cases);
}
#[test]
fn x509_real_openssl_algorithms_match_borrowed_models() {
    assert_eq!(real_cases().len(), 6);
    check(real_cases());
}
