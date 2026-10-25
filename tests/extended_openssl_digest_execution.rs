//! Execute the OpenSSL boundary against independent CPython digests and faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/openssl_digest")
        .join(name)
}

fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("OpenSSL digest", command, Duration::from_secs(30))
}

fn success(output: &Output) {
    common::assert_command_success("OpenSSL digest", output);
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn compile(name: &str) -> common::TempArtifact {
    let entry = fixture(&format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("OpenSSL digest native link", move || {
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["crypto".into()],
            ..Default::default()
        };
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("OpenSSL digest {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_openssl_digest", name, None);
    // Native linking introduces PLT/startup sections. Validate those with the
    // native-link checker; the single-text freestanding checker is unsuitable.
    std::fs::write(executable.path(), bytes).unwrap();
    success(&run(Command::new("python3")
        .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path())));
    let dynamic = run(Command::new("readelf").arg("-d").arg(executable.path()));
    success(&dynamic);
    assert!(
        String::from_utf8_lossy(&dynamic.stdout).contains("libcrypto.so.3"),
        "OpenSSL 3 must be a native dependency: {dynamic:?}"
    );
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn protocol() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| compile("protocol"))
}

fn fault_program() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| compile("faults"))
}

#[derive(Clone, Debug)]
struct Case {
    algorithm: u64,
    layout: u64,
    mode: u64,
    parameter: u64,
    input_offset: u64,
    output_offset: u64,
    bytes: Vec<u8>,
}

impl Case {
    fn new(algorithm: u64, layout: u64, bytes: Vec<u8>) -> Self {
        Self {
            algorithm,
            layout,
            mode: 0,
            parameter: 0,
            input_offset: 3,
            output_offset: 5,
            bytes,
        }
    }
}

fn packet(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for case in cases {
        for word in [
            case.algorithm,
            case.layout,
            case.mode,
            case.parameter,
            case.input_offset,
            case.output_offset,
            case.bytes.len() as u64,
        ] {
            bytes.extend(word.to_le_bytes());
        }
        bytes.extend(&case.bytes);
    }
    bytes
}

fn words(output: &[u8]) -> Vec<u64> {
    assert_eq!(output.len() % 8, 0, "truncated digest protocol output");
    output
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_openssl_digest", "input", None);
    file.write_bytes(bytes);
    file
}

fn oracle(packet: &[u8]) -> Vec<u64> {
    let source = input(packet);
    let output = run(Command::new("python3")
        .arg(fixture("oracle.py"))
        .stdin(std::fs::File::open(source.path()).unwrap()));
    success(&output);
    words(&output.stdout)
}

fn compare(cases: &[Case]) -> Vec<u64> {
    let packet = packet(cases);
    let expected = oracle(&packet);
    let source = input(&packet);
    let output =
        run(Command::new(protocol().path()).stdin(std::fs::File::open(source.path()).unwrap()));
    success(&output);
    let actual = words(&output.stdout);
    assert_eq!(actual.len(), expected.len(), "digest output word count");
    let mut at = 0;
    for (index, case) in cases.iter().enumerate() {
        let size = if case.algorithm % 2 == 0 { 32 } else { 64 };
        assert_eq!(
            &actual[at..at + size + 1],
            &expected[at..at + size + 1],
            "digest case {index}: {case:?}"
        );
        at += size + 1;
    }
    assert_eq!(at, actual.len());
    actual
}

fn unhex(text: &str) -> Vec<u8> {
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}

const FIXED_VECTORS: [[&str; 2]; 4] = [
    [
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    ],
    [
        "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
        "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    ],
    [
        "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
        "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
    ],
    [
        "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26",
        "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0",
    ],
];

#[test]
fn fixed_vectors_match_openssl_and_independent_python_for_all_layouts_and_offsets() {
    let algorithms = ["-sha256", "-sha512", "-sha3-256", "-sha3-512"];
    let mut cases = Vec::new();
    let mut fixed = Vec::new();
    for (algorithm, option) in algorithms.iter().enumerate() {
        for (vector, bytes) in [b"".as_slice(), b"abc".as_slice()].iter().enumerate() {
            let source = input(bytes);
            let external = run(Command::new("openssl")
                .args(["dgst", option, "-binary"])
                .stdin(std::fs::File::open(source.path()).unwrap()));
            success(&external);
            let expected = unhex(FIXED_VECTORS[algorithm][vector]);
            assert_eq!(
                external.stdout, expected,
                "OpenSSL {option} vector {vector}"
            );
            for layout in 0..3 {
                for (input_offset, output_offset) in [(0, 0), (3, 5), (31, 31)] {
                    let mut case = Case::new(algorithm as u64, layout, bytes.to_vec());
                    case.input_offset = input_offset;
                    case.output_offset = output_offset;
                    cases.push(case);
                    fixed.push(expected.len() as u64);
                    fixed.extend(expected.iter().map(|byte| u64::from(*byte)));
                }
            }
        }
    }
    assert_eq!(compare(&cases), fixed);
}

#[test]
fn every_short_input_partition_and_empty_update_preserves_the_logical_digest() {
    let mut cases = Vec::new();
    for algorithm in 0..4 {
        for layout in 0..3 {
            for bytes in [b"abc".to_vec(), vec![0, 1, 127, 128, 254, 255]] {
                // Every composition into nonempty contiguous updates.
                for mask in 0..1 << (bytes.len() - 1) {
                    let mut case = Case::new(algorithm, layout, bytes.clone());
                    case.mode = 2;
                    case.parameter = mask as u64;
                    case.input_offset = (mask * 7 % 32) as u64;
                    case.output_offset = (mask * 11 % 32) as u64;
                    cases.push(case);
                }
                // Empty first/last updates and each possible two-way split.
                for split in 0..=bytes.len() {
                    let mut case = Case::new(algorithm, layout, bytes.clone());
                    case.mode = 1;
                    case.parameter = split as u64;
                    cases.push(case);
                }
            }
        }
    }
    compare(&cases);
}

#[test]
fn block_and_staging_boundaries_match_independent_digests_with_recoverable_errors() {
    let mut cases = Vec::new();
    for algorithm in 0..4 {
        for layout in 0..3 {
            for length in [
                0, 1, 63, 64, 65, 71, 72, 73, 127, 128, 129, 135, 136, 137, 1023, 1024, 1025, 2047,
                2048, 2049, 3073, 4096,
            ] {
                let bytes: Vec<u8> = (0..length)
                    .map(|at| ((at * 73 + 19) ^ (at / 251)) as u8)
                    .collect();
                for width in [1, 63, 1023, 1024, 1025, 4096] {
                    if width == 1 && length > 137 {
                        continue;
                    }
                    let mut case = Case::new(algorithm, layout, bytes.clone());
                    case.mode = 3;
                    case.parameter = width;
                    case.input_offset = (length % 32) as u64;
                    case.output_offset = ((length * 3 + 1) % 32) as u64;
                    cases.push(case);
                }
            }
        }
    }
    compare(&cases);
}

#[test]
fn native_failures_capture_the_first_error_count_only_this_call_and_release_once() {
    let interposer = common::TempArtifact::new("laniusc_openssl_digest", "faults", Some("so"));
    success(&run(Command::new("cc")
        .args([
            "-shared", "-fPIC", "-std=c11", "-Wall", "-Wextra", "-Werror",
        ])
        .arg(fixture("fault_interposer.c"))
        .arg("-o")
        .arg(interposer.path())
        .args(["-ldl", "-lcrypto"])));
    for (mode, cause, stage, completed, trace) in [
        ("fetch", 5, 1, 0, "F"),
        ("fetch-empty", 5, 1, 0, "F"),
        ("size-native", 5, 2, 0, "FSm"),
        ("size-unexpected", 4, 2, 0, "FSm"),
        ("context", 5, 3, 0, "FSCm"),
        ("init", 5, 4, 0, "FSCIcm"),
        ("update-first", 5, 5, 0, "FSCIPUcm"),
        ("update-second", 5, 5, 1024, "FSCIPUUcm"),
        ("update-second-empty", 5, 5, 1024, "FSCIPUUcm"),
        ("update-third", 5, 5, 2048, "FSCIPUUUcm"),
        ("final", 5, 6, 0, "FSCIPUUUDcm"),
        ("final-empty", 5, 6, 0, "FSCIPUUUDcm"),
    ] {
        let events = common::TempArtifact::new("laniusc_openssl_digest", mode, Some("trace"));
        let output = run(Command::new(fault_program().path())
            .env("LD_PRELOAD", interposer.path())
            .env("LANIUS_OPENSSL_FAULT", mode)
            .env("LANIUS_OPENSSL_TRACE", events.path()));
        success(&output);
        assert_eq!(
            words(&output.stdout),
            vec![
                cause,
                stage,
                if cause == 5 && !mode.ends_with("-empty") {
                    0x40000123
                } else {
                    0
                },
                completed,
                0
            ],
            "fault {mode}"
        );
        assert_eq!(
            std::fs::read_to_string(events.path()).unwrap(),
            trace,
            "native call/release sequence for fault {mode}"
        );
    }
}
