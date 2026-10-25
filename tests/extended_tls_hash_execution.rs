//! TLS hash/suite foundations: full-byte independent oracles and bounded seams.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/tls_hash")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TLS hash/suite foundations", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("TLS hash/suite {name}: {e}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_tls_hash", name, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}

fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}

fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_tls_hash", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tls_hash", "memory", None);
    let output = common::process_output_with_timeout(
        "TLS hash/suite native without allocation",
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
        "TLS hash/suite allocated"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}

struct Case {
    wire: Vec<u8>,
    expected: Vec<u64>,
}

fn word(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap())
}

fn cases(group: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "CPU-only TLS hash/suite oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/tls_hash/model.py"))
            .arg(group),
        Duration::from_secs(15),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let bytes = output.stdout;
    let count = word(&bytes, 0);
    assert!((100..=2048).contains(&count));
    let mut at = 8;
    let mut result = Vec::new();
    for _ in 0..count {
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((80..=8272).contains(&n));
        let wire = bytes[at..at + n].to_vec();
        at += n;
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((1..=47).contains(&n));
        let expected = (0..n).map(|i| word(&bytes, at + 8 * i)).collect();
        at += 8 * n;
        result.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    result
}

fn check(group: &str) {
    let cases = cases(group);
    for (batch_index, batch) in cases.chunks(64).enumerate() {
        let mut input = (batch.len() as u64).to_le_bytes().to_vec();
        for case in batch {
            input.extend(&case.wire);
        }
        let actual = execute(protocol(), &input);
        let mut at = 0;
        for (index, case) in batch.iter().enumerate() {
            let n = case.expected.len();
            assert!(at + n <= actual.len(), "short native output");
            assert_eq!(
                &actual[at..at + n],
                &case.expected,
                "{group} batch {batch_index} case {index}, wire={:02x?}",
                case.wire
            );
            at += n;
        }
        assert_eq!(at, actual.len());
    }
    eprintln!(
        "TLS hash/suite {group}: {} commands / {} native batches",
        cases.len(),
        cases.len().div_ceil(64)
    );
}

#[test]
fn tls_hash_suite_ordinary_composition_consumer() {
    let file = compile("plain");
    assert!(execute(&file, &[]).is_empty());
}

#[test]
fn tls_hash_published_hashlib_streams_forks_and_owned_snapshots() {
    check("hashes");
}

#[test]
fn tls_hash_factory_metadata_atomicity_and_common_count_seams() {
    check("limits");
}

#[test]
fn tls_suite_mappings_all_ordered_policies_and_active_slot_contracts() {
    check("suites");
}
