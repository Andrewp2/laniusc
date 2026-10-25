//! FIPS 180-4 SHA-512 family, independent CAVP/hashlib oracles and owner-free streaming.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::Duration,
};

const SEED: u64 = 0x73b1_9ca5_5123_8428;
const FRAME: usize = 65;
const RECORD: usize = FRAME * 3;

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/sha512")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("SHA-512 family {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_sha512", name, None);
    artifact.write_bytes(bytes); // Shared strict ELF and jump-target checking.
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn run(name: &str, command: &mut Command) -> Output {
    common::process_output_with_timeout(name, command, Duration::from_secs(55))
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn traced(executable: &common::TempArtifact, input: &common::TempArtifact, name: &str) -> Output {
    let trace = common::TempArtifact::new("laniusc_sha512", "trace", None);
    let output = run(
        name,
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,mremap,munmap,brk",
                "-e",
                "signal=none",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(executable.path())
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "SHA-512 consumers allocate nothing: {events}"
    );
    output
}
fn hex(source: &str) -> Vec<u8> {
    assert!(source.len().is_multiple_of(2));
    source
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let digit = |value: u8| match value {
                b'0'..=b'9' => value - b'0',
                b'a'..=b'f' => value - b'a' + 10,
                b'A'..=b'F' => value - b'A' + 10,
                _ => panic!("invalid fixture hex"),
            };
            digit(pair[0]) * 16 + digit(pair[1])
        })
        .collect()
}
#[derive(Clone)]
struct Case {
    variant: u8,
    layout: u8,
    schedule: u8,
    message: Vec<u8>,
    official: Option<Vec<u8>>,
    label: String,
}
fn next(random: &mut u64) -> u64 {
    *random = random.wrapping_add(0x9e37_79b9_7f4a_7c15);
    let mut value = *random;
    value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}
fn cases() -> Vec<Case> {
    let mut cases = Vec::new();
    let mut official_counts = [0; 4];
    for (index, line) in include_str!("fixtures/stdlib_foundation/sha512/nist_cavp_vectors.txt")
        .lines()
        .enumerate()
    {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        let fields: Vec<_> = line.split('|').collect();
        assert_eq!(fields.len(), 4);
        let variant: u8 = fields[0].parse().unwrap();
        let length: usize = fields[1].parse().unwrap();
        let message = hex(fields[2]);
        let answer = hex(fields[3]);
        assert_eq!(message.len(), length);
        official_counts[variant as usize] += 1;
        for layout in 0..2 {
            cases.push(Case {
                variant,
                layout,
                schedule: (index % 4) as u8,
                message: message.clone(),
                official: Some(answer.clone()),
                label: format!("NIST variant={variant} length={length} layout={layout}"),
            });
        }
    }
    assert_eq!(
        official_counts, [23; 4],
        "all four official vector selections are present"
    );
    let boundaries = [
        0, 1, 2, 3, 7, 8, 15, 16, 31, 32, 63, 64, 95, 96, 110, 111, 112, 113, 119, 120, 126, 127,
        128, 129, 130, 223, 224, 225, 239, 240, 255, 256, 257, 383, 384, 385, 511, 512, 513, 1023,
        1024, 1025, 2047, 2048, 4095, 4096, 8191, 8192,
    ];
    for length in boundaries {
        let message: Vec<u8> = (0..length)
            .map(|i| ((i * 37) ^ (i / 17) ^ 0xa5) as u8)
            .collect();
        for variant in 0..4 {
            for layout in 0..2 {
                for schedule in 0..4 {
                    cases.push(Case { variant, layout, schedule, message: message.clone(), official: None, label: format!("boundary variant={variant} length={length} layout={layout} schedule={schedule}") });
                }
            }
        }
    }
    let mut random = SEED;
    for index in 0..96 {
        let length = (next(&mut random) % 8193) as usize;
        let message: Vec<u8> = (0..length).map(|_| next(&mut random) as u8).collect();
        for variant in 0..4 {
            let layout = (next(&mut random) % 2) as u8;
            let schedule = (next(&mut random) % 4) as u8;
            cases.push(Case { variant, layout, schedule, message: message.clone(), official: None, label: format!("seed={SEED:#x} random={index} variant={variant} length={length} layout={layout} schedule={schedule}") });
        }
    }
    cases
}
fn encode(cases: &[Case]) -> Vec<u8> {
    let mut output = (cases.len() as u32).to_le_bytes().to_vec();
    for case in cases {
        output.extend([case.variant, case.layout, case.schedule, 0]);
        output.extend((case.message.len() as u32).to_le_bytes());
        output.extend(&case.message);
    }
    output
}
const PYTHON: &str = r#"
import hashlib, struct, sys
source=sys.stdin.buffer.read(); count=struct.unpack_from('<I',source)[0]; at=4; out=bytearray()
for high,low in [(2**61-1,2**64-1),(8,1),(0x0123456789abcdef,0xe123456789abcde0)]:
    out += (((high<<64)|low)<<3).to_bytes(16,'big')
names=['sha512','sha384','sha512_224','sha512_256']
for index in range(count):
    variant,layout,schedule,_=source[at:at+4]; size=struct.unpack_from('<I',source,at+4)[0]; at+=8
    message=source[at:at+size]; at+=size
    answer=hashlib.new(names[variant],message).digest()
    fork=hashlib.new(names[variant],message[:73]+bytes([255,0,17])).digest()
    for value in [answer,fork,answer]: out += bytes([len(value)])+value+bytes(64-len(value))
assert at==len(source)
sys.stdout.buffer.write(out)
"#;

#[test]
fn sha512_family_cavp_hashlib_streaming_views_snapshots_and_length_contracts_execute() {
    let executable = executable("runtime.lani"); // Compile once for the entire batch.
    let cases = cases();
    let input = common::TempArtifact::new("laniusc_sha512", "cases", None);
    input.write_bytes(encode(&cases));
    let expected = run(
        "SHA-512 Python hashlib oracle",
        Command::new("python3")
            .args(["-c", PYTHON])
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
    );
    checked(&expected);
    assert_eq!(expected.stdout.len(), 48 + RECORD * cases.len());
    let actual = traced(&executable, &input, "SHA-512 batched native cases");
    let completed = actual.stdout.len().saturating_sub(48) / RECORD;
    assert_eq!(
        actual.status.code(),
        Some(0),
        "completed={completed}/{} next={:?} stderr={:?}",
        cases.len(),
        cases.get(completed).map(|case| &case.label),
        actual.stderr
    );
    checked(&actual);
    assert_eq!(actual.stdout.len(), expected.stdout.len());
    assert_eq!(
        &actual.stdout[..48],
        &expected.stdout[..48],
        "fabricated count carry/overflow/padding arithmetic; not enormous-message hashing"
    );
    for (index, case) in cases.iter().enumerate() {
        let range = 48 + index * RECORD..48 + (index + 1) * RECORD;
        assert_eq!(
            &actual.stdout[range.clone()],
            &expected.stdout[range.clone()],
            "case={index} {}",
            case.label
        );
        if let Some(answer) = &case.official {
            let start = range.start;
            assert_eq!(
                actual.stdout[start] as usize,
                answer.len(),
                "{}",
                case.label
            );
            assert_eq!(
                &actual.stdout[start + 1..start + 1 + answer.len()],
                answer,
                "official CAVP: {}",
                case.label
            );
        }
    }
    eprintln!(
        "SHA-512 family: {} batched cases, 92 official vectors in both layouts; three independent digest publications per case; zero allocation calls",
        cases.len()
    );
}

#[test]
fn sha512_family_ordinary_stream_consumer_matches_hashlib_without_allocation() {
    let executable = executable("consumer.lani"); // One ordinary consumer compiled once.
    let input = common::TempArtifact::new("laniusc_sha512", "stream", None);
    let messages = [
        Vec::new(), b"abc".to_vec(),
        b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu".to_vec(),
        (0..=255).collect(), vec![b'a'; 1_000_000],
        (0..131_201).map(|i| ((i*29) ^ (i/251)) as u8).collect(),
    ];
    for (index, message) in messages.into_iter().enumerate() {
        input.write_bytes(&message);
        let expected = run("SHA-512 stream hashlib oracle", Command::new("python3").args(["-c", "import hashlib,sys; data=sys.stdin.buffer.read(); sys.stdout.buffer.write(b''.join(hashlib.new(n,data).digest() for n in ['sha512','sha384','sha512_224','sha512_256']))"]).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&expected);
        let actual = traced(&executable, &input, "SHA-512 ordinary stream");
        checked(&actual);
        assert_eq!(
            actual.stdout,
            expected.stdout,
            "ordinary consumer case={index} length={}",
            message.len()
        );
    }
}
