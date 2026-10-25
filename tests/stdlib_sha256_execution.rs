// Two canonical native programs: ordinary imported use, then streaming differential contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs::File,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/sha256")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_sha256", name, None);
    exe.write_bytes(bytes); // Common strict ELF and native x86 jump validation.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn run(name: &str, exe: &common::TempArtifact, input: Option<&common::TempArtifact>) -> Vec<u8> {
    let trace = common::TempArtifact::new("laniusc_sha256", name, None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path());
    if let Some(input) = input {
        command.stdin(File::open(input.path()).unwrap());
    }
    let output = common::process_output_with_timeout(name, &mut command, Duration::from_secs(20));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let allocations = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        allocations.is_empty(),
        "hashing must allocate/release no backing: {allocations}"
    );
    output.stdout
}

#[test]
fn sha224_and_sha256_plain_imported_consumers_execute_without_error_projection() {
    let exe = executable("plain.lani");
    assert!(run("plain imported SHA-2 consumer", &exe, None).is_empty());
}

const HASHLIB: &str = r#"
import hashlib, struct, sys
# NIST's official byte-oriented worked examples anchor the independent oracle.
long = b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'
for variant, message, expected in [
    (0,b'abc','ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
    (0,long,'248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'),
    (1,b'abc','23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7'),
    (1,long,'75388b16512776cc5dba5da1fd890150b0c6455cb4f58b1952522525')]:
    assert (hashlib.sha224 if variant else hashlib.sha256)(message).hexdigest() == expected
source = open(sys.argv[1], 'rb').read()
out = bytearray(); at = 0
while at < len(source):
    variant, length, schedule, layout = struct.unpack_from('<4Q', source, at); at += 32
    message = source[at:at+length]; assert len(message) == length; at += length
    result = (hashlib.sha224 if variant else hashlib.sha256)(message).digest()
    out += struct.pack('<Q', len(result)) + result + bytes(32-len(result))
assert at == len(source)
sys.stdout.buffer.write(out)
"#;

#[test]
fn sha2_vectors_chunk_schedules_and_state_contracts_match_hashlib() {
    let mut input = Vec::new();
    let mut records = Vec::new();
    let mut append = |variant: u64, message: &[u8], schedule: u64, layout: u64| {
        let record = [variant, message.len() as u64, schedule, layout];
        for value in record {
            input.extend_from_slice(&value.to_le_bytes());
        }
        input.extend_from_slice(message);
        records.push(record);
    };
    for variant in 0..2 {
        for length in [
            0usize, 1, 2, 3, 7, 31, 54, 55, 56, 57, 62, 63, 64, 65, 66, 111, 112, 119, 120, 127,
            128, 129, 255, 256, 257, 511, 512, 513, 1024, 4096,
        ] {
            let message: Vec<u8> = (0..length)
                .map(|i| ((i * 131 + i / 7 + 19) & 255) as u8)
                .collect();
            for schedule in 0..8 {
                for layout in 0..2 {
                    append(variant, &message, schedule, layout);
                }
            }
        }
        for message in [
            b"abc".as_slice(),
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_slice(),
        ] {
            for schedule in [0, 1] {
                for layout in 0..2 {
                    append(variant, message, schedule, layout);
                }
            }
        }
    }
    assert_eq!(records.len(), 976);
    let input_file = common::TempArtifact::new("laniusc_sha256", "model_input", None);
    input_file.write_bytes(input);
    let oracle = common::process_output_with_timeout(
        "independent hashlib SHA-2 oracle",
        Command::new("python3")
            .arg("-c")
            .arg(HASHLIB)
            .arg(input_file.path()),
        Duration::from_secs(10),
    );
    assert!(
        oracle.status.success() && oracle.stderr.is_empty(),
        "{oracle:?}"
    );
    assert_eq!(oracle.stdout.len(), records.len() * 40);
    let exe = executable("model.lani");
    let actual = run("SHA-2 state and chunk model", &exe, Some(&input_file));
    if actual != oracle.stdout {
        let at = actual
            .iter()
            .zip(&oracle.stdout)
            .position(|(a, b)| a != b)
            .unwrap_or(actual.len().min(oracle.stdout.len()));
        let case = at / 40;
        panic!("SHA-2 case {case} {:?}, response byte {}, actual {:?}, expected {:?}; total lengths {} vs {}", records.get(case), at%40, actual.get(case*40..(case*40+40).min(actual.len())), oracle.stdout.get(case*40..(case*40+40).min(oracle.stdout.len())), actual.len(), oracle.stdout.len());
    }
}
