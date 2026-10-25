//! Real certificate-path + CV + Finished bridge; no transport/connection claim.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/tls_authentication")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("portable TLS server authentication", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("TLS authentication {name}: {error}"));
    let file = common::TempArtifact::new("laniusc_tls_authentication", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdoutlen={}, prefix={:?}, stderr={:?}",
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(32)],
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "{:?}",
        String::from_utf8_lossy(&output.stderr)
    );
}
fn peer(mode: &str) -> Vec<u8> { peer_file("peer.py",mode) }
fn peer_file(name: &str, mode: &str) -> Vec<u8> {
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended/tls_authentication").join(name);
    let output = common::process_output_with_timeout(
        "independent OpenSSL/libsodium TLS authentication peer",
        Command::new("python3").arg(path).arg(mode),
        Duration::from_secs(40),
    );
    checked(&output);
    output.stdout
}
fn execute(exe: &common::TempArtifact, input: &[u8]) -> Vec<u8> {
    let source = common::TempArtifact::new("laniusc_tls_authentication", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tls_authentication", "memory", None);
    let output = common::process_output_with_timeout(
        "native portable TLS authentication without allocation",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk", "-e", "signal=none"])
            .arg(exe.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(30),
    );
    checked(&output);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "portable bridge and fixtures allocate nothing"
    );
    output.stdout
}
struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, at: 0 }
    }
    fn bytes(&mut self, n: usize) -> &'a [u8] {
        assert!(
            n <= self.bytes.len() - self.at,
            "truncated response at {}",
            self.at
        );
        let value = &self.bytes[self.at..self.at + n];
        self.at += n;
        value
    }
    fn word(&mut self) -> u64 {
        u64::from_le_bytes(self.bytes(8).try_into().unwrap())
    }
    fn block(&mut self) -> Vec<u8> {
        let n = self.word() as usize;
        assert!(n <= 2_000_000);
        self.bytes(n).to_vec()
    }
    fn done(&self) {
        assert_eq!(self.at, self.bytes.len(), "no trailing protocol bytes");
    }
}
struct Observation {
    rule: u64,
    debit: u64,
    words: [u64; 20],
    frame: Vec<u8>,
}
struct Case {
    wire: Vec<u8>,
    constructor: u64,
    layout: u64,
    work: u64,
    anchor: Vec<u8>,
    observations: Vec<Observation>,
}
fn prepare(mode: &str) -> Vec<Case> {
    let bytes = peer(mode);
    let mut data = Reader::new(&bytes);
    let count = data.word();
    assert!(count <= 512);
    let mut cases = Vec::new();
    for _ in 0..count {
        let wire = data.block();
        let constructor = data.word();
        let layout = data.word();
        let work = data.word();
        let count = data.word();
        let anchor = data.block();
        assert!(count <= 128);
        let mut observations = Vec::new();
        for _ in 0..count {
            let rule = data.word();
            let debit = data.word();
            let n = data.word() as usize;
            assert!(n <= 98304);
            let words = std::array::from_fn(|_| data.word());
            let frame = data.bytes(n).to_vec();
            observations.push(Observation {
                rule,
                debit,
                words,
                frame,
            });
        }
        cases.push(Case {
            wire,
            constructor,
            layout,
            work,
            anchor,
            observations,
        });
    }
    data.done();
    cases
}
fn compare(mode: &str) {
    let cases = prepare(mode);
    let mut input = (cases.len() as u64).to_le_bytes().to_vec();
    for case in &cases {
        input.extend(&case.wire);
    }
    let output = execute(protocol(), &input);
    let mut data = Reader::new(&output);
    let mut actions = 0;
    for (index, case) in cases.iter().enumerate() {
        let stride = data.word();
        assert_eq!(data.word(), stride, "case {index}: frame/anchor layout");
        if case.layout == 1 {
            assert_eq!(stride, 1);
        } else {
            assert!(stride > 1);
        }
        assert_eq!(data.word(), case.constructor, "case {index}: constructor");
        let mut work = case.work;
        for (turn, observation) in case.observations.iter().enumerate() {
            let actual: [u64; 20] = std::array::from_fn(|_| data.word());
            for (field, (&got, &expected)) in actual.iter().zip(&observation.words).enumerate() {
                if field != 7 {
                    assert_eq!(
                        got, expected,
                        "{mode} case {index} action {turn} field {field}"
                    );
                }
            }
            assert!(
                actual[7] <= work,
                "shared work never replenished: {mode} case {index} action {turn}"
            );
            match observation.rule {
                1 => assert_eq!(
                    actual[7], work,
                    "metadata/replay/observation must spend no work"
                ),
                2 => assert_eq!(
                    actual[7],
                    work.checked_sub(observation.debit).unwrap(),
                    "exact frame tariff before non-path work"
                ),
                3 => assert!(
                    actual[7] <= work.checked_sub(observation.debit).unwrap(),
                    "path work is additional to precharged frame tariff"
                ),
                other => panic!("unknown peer work rule {other}"),
            }
            work = actual[7];
            assert_eq!(
                data.bytes(observation.frame.len()),
                observation.frame,
                "{mode} case {index} action {turn}: immutable complete source frame"
            );
            actions += 1;
        }
        assert_eq!(
            data.bytes(case.anchor.len()),
            case.anchor,
            "case {index}: borrowed trust anchor immutable"
        );
    }
    data.done();
    eprintln!(
        "TLS authentication {mode}: {} layout cases, {actions} observations",
        cases.len()
    );
}
#[test]
fn server_flight_authentication_matches_real_chain_signature_and_finished_peer() {
    compare("positive");
}
#[test]
fn server_authentication_retries_budgets_and_terminal_failures_withhold_peer() {
    compare("negative");
}
#[test]
fn ordinary_server_authentication_consumer_executes_without_error_projection() {
    let bytes = peer("ordinary");
    let mut data = Reader::new(&bytes);
    let input = data.block();
    let expected = data.block();
    data.done();
    assert_eq!(execute(&compile("plain"), &input), expected);
}

// The wider key receiver has an independent ordinary framed peer. Cryptographic
// expected decisions come from EVP, not the production dispatch implementation.
fn signature_protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("signature_protocol"))
}
fn compare_signatures(mode: &str) {
    let prepared=peer_file("signature_peer.py",mode);
    let mut prepared=Reader::new(&prepared);
    let input=prepared.block();let expected=prepared.block();prepared.done();
    let output=execute(signature_protocol(),&input);
    let mut output=Reader::new(&output);let mut expected=Reader::new(&expected);
    let count=expected.word();assert!((1..=256).contains(&count));
    let mut actions=0;
    for case in 0..count {
        let layout=expected.word();let constructor=expected.word();let mut work=expected.word();let anchor=expected.block();let observations=expected.word();
        let stride=output.word();assert_eq!(output.word(),stride,"same anchor/frame stride");
        if layout==1 {assert_eq!(stride,1);}else{assert!(stride>1);}
        assert_eq!(output.word(),constructor,"{mode} case {case}: constructor");
        for action in 0..observations {
            let rule=expected.word();let debit=expected.word();let cap=expected.word();let words:[u64;17]=std::array::from_fn(|_|expected.word());
            let before=output.word();assert_eq!(before,work.min(cap),"{mode} case {case} action {action}: shared allowance tightening only");
            let actual:[u64;17]=std::array::from_fn(|_|output.word());
            for field in 0..17 {if field!=7 {assert_eq!(actual[field],words[field],"{mode} case {case} action {action} field {field}");}}
            match rule {
                1=>assert_eq!(actual[7],before,"latched failure/unaffordable frame changes no credits"),
                2=>assert_eq!(actual[7],before.checked_sub(debit).unwrap(),"{mode} case {case} action {action}: exact frame plus shared proof reservation"),
                3=>assert!(actual[7]<=before.checked_sub(debit).unwrap(),"certificate classification/import/edges add work to frame tariff"),
                _=>panic!("unknown work rule")
            }
            work=actual[7];actions+=1;
        }
        assert_eq!(output.bytes(anchor.len()),anchor,"immutable configured anchor");
    }
    expected.done();output.done();eprintln!("TLS multisignature {mode}: {count} layout cases, {actions} observations");
}
#[test]
fn rsa_pss_and_ecdsa_certificate_verify_publish_owned_keys_for_both_transcript_hashes() {compare_signatures("positive");}
#[test]
fn proof_policies_signature_hashes_and_shared_allowance_fail_closed() {compare_signatures("negative");}
#[test]
fn ordinary_rsa_and_ecdsa_authentication_consumer_uses_owned_peer_key() {
    let bytes=peer_file("signature_peer.py","ordinary");let mut data=Reader::new(&bytes);
    let input=data.block();let expected=data.block();data.done();
    assert_eq!(execute(&compile("signature_plain"),&input),expected);
}
// A positive diagnostic control, kept separate from the six authentication
// API gates. No expected-error fossil: either selected fixture must execute.
#[test]
fn authentication_error_match_positive_control() {
    let selected=std::env::var("LANIUS_AUTH_ERROR_MATCH_CONTROL")
        .unwrap_or_else(|_|"match_auth_error_explicit".to_owned());
    assert!(matches!(selected.as_str(),"match_auth_error_explicit"|"match_auth_error_wildcard"),"unsupported authentication Error control");
    assert_eq!(execute(&compile(&selected),&[]),Vec::<u8>::new());
}
