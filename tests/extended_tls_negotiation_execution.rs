//! Focused native negotiation semantics; Python is an independent wire oracle.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
const ANY: u64 = u64::MAX;
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/tls_negotiation")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TLS negotiation", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("TLS negotiation {name}: {e}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_tls_negotiation", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_tls_negotiation", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tls_negotiation", "trace", None);
    let output = common::process_output_with_timeout(
        "TLS negotiation native without allocation",
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
        "negotiation allocated"
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
fn word(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap())
}
fn set_word(bytes: &mut [u8], at: usize, n: u64) {
    bytes[at..at + 8].copy_from_slice(&n.to_le_bytes());
}
fn cases(group: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "CPU-only TLS negotiation oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/tls_negotiation/model.py"))
            .arg(group),
        Duration::from_secs(20),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let bytes = output.stdout;
    let count = word(&bytes, 0);
    assert!((200..=2048).contains(&count));
    let mut at = 8;
    let mut cases = Vec::new();
    for _ in 0..count {
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((160..=32928).contains(&n));
        let wire = bytes[at..at + n].to_vec();
        at += n;
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!(n == 28 || n == 156);
        let expected = (0..n).map(|i| word(&bytes, at + 8 * i)).collect();
        at += 8 * n;
        cases.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    cases
}
fn check(cases: &[Case]) -> Vec<Vec<u64>> {
    let mut results = Vec::new();
    for batch in cases.chunks(64) {
        let mut input = (batch.len() as u64).to_le_bytes().to_vec();
        for case in batch {
            input.extend(&case.wire);
        }
        let actual = execute(protocol(), &input);
        let mut at = 0;
        for (index, case) in batch.iter().enumerate() {
            let n = case.expected.len();
            assert!(at + n <= actual.len(), "short native output");
            let got = &actual[at..at + n];
            for (field, (&got, &want)) in got.iter().zip(&case.expected).enumerate() {
                if want != ANY {
                    assert_eq!(
                        got, want,
                        "case {index} field {field}, wire={:02x?}",
                        case.wire
                    );
                }
            }
            assert!(
                got[10] <= word(&case.wire, 56),
                "shared allowance increased"
            );
            results.push(got.to_vec());
            at += n;
        }
        assert_eq!(at, actual.len());
    }
    results
}
fn limits_from_observed_cost(cases: &[Case], outputs: &[Vec<u64>]) -> usize {
    let mut probes = Vec::new();
    for (case, out) in cases
        .iter()
        .zip(outputs)
        .filter(|(case, out)| out[0] == 0 && word(&case.wire, 16) == 0)
        .take(12)
    {
        let mut exact = case.clone();
        let used = word(&case.wire, 56) - out[10];
        assert!(used > 0);
        set_word(&mut exact.wire, 56, used);
        probes.push(exact.clone());
        set_word(&mut exact.wire, 56, used - 1);
        exact.expected.fill(0);
        exact.expected[0] = 3;
        exact.expected[10] = ANY;
        // Failed writers leave their entire backing unchanged.
        if word(&exact.wire, 0) == 6 {
            exact.expected[28..].fill(0xa5a5_a5a5_a5a5_a5a5);
        }
        probes.push(exact);
    }
    check(&probes);
    probes.len()
}
#[test]
fn tls_negotiation_ordinary_two_suites_and_retry_consumer() {
    let file = compile("plain");
    assert!(execute(&file, &[]).is_empty());
}
#[test]
fn tls_negotiation_client_offer_wire_model_and_limits() {
    let cases = cases("offers");
    let outputs = check(&cases);
    let limits = limits_from_observed_cost(&cases, &outputs);
    eprintln!(
        "negotiation offers: {} model commands, {limits} exact/one-less budget probes",
        cases.len()
    );
}
#[test]
fn tls_negotiation_server_retry_second_hello_and_encrypted_extensions() {
    let cases = cases("server");
    let outputs = check(&cases);
    let limits = limits_from_observed_cost(&cases, &outputs);
    eprintln!(
        "negotiation server/HRR/EE: {} model commands, {limits} exact/one-less budget probes",
        cases.len()
    );
}
#[test]
fn tls_negotiation_atomic_extension_writers_and_guards() {
    let cases = cases("writers");
    let outputs = check(&cases);
    let limits = limits_from_observed_cost(&cases, &outputs);
    eprintln!(
        "negotiation writers: {} model commands, {limits} exact/one-less budget probes",
        cases.len()
    );
}
