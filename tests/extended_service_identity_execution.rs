//! DNS/IP identity matching: independent CPU policy model and real OpenSSL SANs.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
const ANY: u64 = u64::MAX;
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/service_identity")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("service identity", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("service identity {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_service_identity", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_service_identity", "input", None);
    source.write_bytes(input);
    let log = common::TempArtifact::new("laniusc_service_identity", "trace", None);
    let output = common::process_output_with_timeout(
        "service identity native without allocations",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(log.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(log.path()).unwrap().is_empty(),
        "identity allocates nothing"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|v| u64::from_le_bytes(v.try_into().unwrap()))
        .collect()
}
#[derive(Clone, Debug)]
struct Case {
    wire: Vec<u8>,
    expected: Vec<u64>,
    late_offset: u64,
}
fn word(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap())
}
fn set_word(bytes: &mut [u8], at: usize, value: u64) {
    bytes[at..at + 8].copy_from_slice(&value.to_le_bytes());
}
fn prepare(mode: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "CPU-only service identity oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/service_identity/model.py"))
            .arg(mode),
        Duration::from_secs(40),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let bytes = output.stdout;
    let count = word(&bytes, 0);
    assert!(count <= 4096);
    let mut at = 8;
    let mut result = Vec::new();
    for _ in 0..count {
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((88..=9304).contains(&n));
        let wire = bytes[at..at + n].to_vec();
        at += n;
        let n = word(&bytes, at) as usize;
        at += 8;
        let expected = (0..n).map(|i| word(&bytes, at + 8 * i)).collect();
        at += 8 * n;
        let late_offset = word(&bytes, at);
        at += 8;
        result.push(Case {
            wire,
            expected,
            late_offset,
        });
    }
    assert_eq!(at, bytes.len());
    result
}
fn real() -> &'static Vec<Case> {
    static CASES: OnceLock<Vec<Case>> = OnceLock::new();
    CASES.get_or_init(|| prepare("openssl"))
}
fn check(cases: &[Case]) -> Vec<Vec<u64>> {
    let mut results = Vec::new();
    for batch in cases.chunks(128) {
        let mut input = (batch.len() as u64).to_le_bytes().to_vec();
        for case in batch {
            input.extend(&case.wire);
        }
        let actual = execute(protocol(), &input);
        let mut at = 0;
        for (index, case) in batch.iter().enumerate() {
            let n = case.expected.len();
            assert!(at + n <= actual.len(), "short output case{index}");
            let actual = &actual[at..at + n];
            for (i, (&got, &want)) in actual.iter().zip(&case.expected).enumerate() {
                if want != ANY {
                    assert_eq!(got, want, "case{index} field{i}, wire={:02x?}", case.wire);
                }
            }
            let op = word(&case.wire, 0);
            if op == 5 || op == 9 {
                let mut items = word(&case.wire, 40);
                let mut work = word(&case.wire, 48);
                let size = word(&case.wire, 72);
                for header in actual.chunks_exact(5) {
                    assert!(header[1] <= size, "offset outside certificate");
                    assert!(
                        header[3] <= items && header[4] <= work,
                        "shared allowance increased"
                    );
                    items = header[3];
                    work = header[4];
                }
            }
            results.push(actual.to_vec());
            at += n;
        }
        assert_eq!(at, actual.len());
    }
    results
}
#[test]
fn service_identity_dns_ip_models_and_value_copies() {
    let cases = prepare("raw");
    assert!(cases.len() > 1000);
    check(&cases);
    eprintln!("identity raw commands: {}", cases.len());
}
#[test]
fn service_identity_certificate_san_family_policy_and_shared_budgets() {
    let cases = prepare("certificates");
    check(&cases);
    let baselines = prepare("budgets");
    assert_eq!(baselines.len(), 2);
    for baseline in baselines {
        let result = check(std::slice::from_ref(&baseline)).pop().unwrap();
        assert_eq!(&result[..3], &[0, 0, 1]);
        let max_items = word(&baseline.wire, 40);
        let max_work = word(&baseline.wire, 48);
        let items_used = max_items - result[3];
        let work_used = max_work - result[4];
        assert!(items_used > 0 && work_used > 17);
        // Derive the parser's actual framing cost rather than freezing it. The last
        // DNS comparison is charged last: one unit short must fail at its content,
        // even though the earlier SAN already matched the reference.
        let mut exact = baseline.clone();
        set_word(&mut exact.wire, 48, work_used);
        exact.expected = vec![0, 0, 1, ANY, 0];
        check(&[exact]);
        let mut short = baseline.clone();
        set_word(&mut short.wire, 48, work_used - 1);
        short.expected = vec![104, baseline.late_offset, 0, ANY, ANY];
        check(&[short]);
        let mut shared = baseline.clone();
        set_word(&mut shared.wire, 48, 2 * work_used - 1);
        set_word(&mut shared.wire, 80, 2);
        shared.expected = vec![
            0,
            0,
            1,
            ANY,
            work_used - 1,
            104,
            baseline.late_offset,
            0,
            ANY,
            ANY,
        ];
        check(&[shared]);
        let mut item_short = baseline.clone();
        set_word(&mut item_short.wire, 40, items_used - 1);
        item_short.expected = vec![103, ANY, 0, ANY, ANY];
        check(&[item_short]);
    }
    eprintln!(
        "identity certificate commands: {} plus bounded continuation controls",
        cases.len()
    );
}
#[test]
fn service_identity_real_openssl_dns_and_ip_certificates() {
    assert_eq!(real().len(), 42);
    check(real());
}
#[test]
fn ordinary_service_identity_consumer_without_error_projection() {
    let case = &real()[0];
    let r = word(&case.wire, 56) as usize;
    let p = word(&case.wire, 64) as usize;
    let cert = &case.wire[88 + r + p..];
    let mut input = (cert.len() as u64).to_le_bytes().to_vec();
    input.extend(cert);
    assert!(execute(&compile("plain"), &input).is_empty());
}
