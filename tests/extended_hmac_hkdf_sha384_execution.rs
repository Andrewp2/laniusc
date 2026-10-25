//! HMAC/HKDF-SHA384: full-byte oracles, lifecycle, boundaries and private seams.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/hmac_hkdf_sha384")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("HMAC/HKDF-SHA384", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("HMAC/HKDF-SHA384 {name}: {e}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_hmac_hkdf384", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_hmac_hkdf384", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_hmac_hkdf384", "trace", None);
    let output = common::process_output_with_timeout(
        "HMAC/HKDF-SHA384 native without allocations",
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
        "HMAC/HKDF allocated"
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
fn word(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn cases(group: &str) -> Vec<Case> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "CPU-only SHA384 HMAC/HKDF oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/hmac_hkdf_sha384/model.py"))
            .arg(group),
        Duration::from_secs(30),
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
        assert!((64..=3136).contains(&n));
        let wire = bytes[at..at + n].to_vec();
        at += n;
        let n = word(&bytes, at) as usize;
        at += 8;
        assert!((2..=1534).contains(&n));
        let expected = (0..n).map(|i| word(&bytes, at + 8 * i)).collect();
        at += 8 * n;
        result.push(Case { wire, expected });
    }
    assert_eq!(at, bytes.len());
    result
}
fn check(group: &str) {
    let cases = cases(group);
    for (batch_index, batch) in cases.chunks(32).enumerate() {
        let mut input = (batch.len() as u64).to_le_bytes().to_vec();
        for c in batch {
            input.extend(&c.wire);
        }
        let actual = execute(protocol(), &input);
        let mut at = 0;
        for (index, c) in batch.iter().enumerate() {
            let n = c.expected.len();
            assert!(at + n <= actual.len(), "short native output");
            assert_eq!(
                &actual[at..at + n],
                &c.expected,
                "{group} batch{batch_index} case{index}, wire={:02x?}",
                c.wire
            );
            at += n;
        }
        assert_eq!(at, actual.len());
    }
    eprintln!(
        "HMAC/HKDF-SHA384 {group}: {} commands / {} native batches",
        cases.len(),
        cases.len().div_ceil(32)
    );
}
#[test]
fn hmac_hkdf_sha384_ordinary_no_error_projection_consumer() {
    let file = compile("plain");
    assert!(execute(&file, &[]).is_empty());
}
#[test]
fn hmac_sha384_rfc4231_blocks_streams_resets_and_owned_copies() {
    check("hmac");
}
#[test]
fn hkdf_sha384_independent_openssl_full_counter255_and_guards() {
    check("hkdf");
}
#[test]
fn hmac_hkdf_sha384_atomic_errors_and_private_counter_seams() {
    check("limits");
}
