//! RFC 8439 Poly1305 vectors, libsodium and an independent integer formula.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::Duration,
};
const SEED: u64 = 0x1305_8439_c0de_17ff;
const RECORD: usize = 64;
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/poly1305")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("Poly1305 {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_poly1305", name, None);
    output.write_bytes(bytes);
    std::fs::set_permissions(output.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    output
}
fn run(name: &str, command: &mut Command) -> Output {
    common::process_output_with_timeout(name, command, Duration::from_secs(55))
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn traced(executable: &common::TempArtifact, input: &common::TempArtifact) -> Output {
    let trace = common::TempArtifact::new("laniusc_poly1305", "trace", None);
    let output = run(
        "Poly1305 native",
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
        "Poly1305 allocates nothing: status={:?} stdout_bytes={} trace={events}",
        output.status,
        output.stdout.len()
    );
    output
}
fn hex(text: &str) -> Vec<u8> {
    assert!(text.len().is_multiple_of(2));
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let digit = |byte| match byte {
                b'0'..=b'9' => byte - b'0',
                b'a'..=b'f' => byte - b'a' + 10,
                b'A'..=b'F' => byte - b'A' + 10,
                _ => panic!("invalid fixture hex"),
            };
            digit(pair[0]) * 16 + digit(pair[1])
        })
        .collect()
}
struct Case {
    key: Vec<u8>,
    message: Vec<u8>,
    layout: u8,
    schedule: u8,
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
    let mut official = 0;
    for line in include_str!("fixtures/stdlib_foundation/poly1305/rfc8439_vectors.txt").lines() {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        let fields: Vec<_> = line.split('|').collect();
        assert_eq!(fields.len(), 4);
        let key = hex(fields[1]);
        let message = hex(fields[2]);
        let tag = hex(fields[3]);
        assert_eq!(key.len(), 32);
        assert_eq!(tag.len(), 16);
        official += 1;
        for layout in 0..2 {
            for schedule in 0..4 {
                cases.push(Case {
                    key: key.clone(),
                    message: message.clone(),
                    layout,
                    schedule,
                    official: Some(tag.clone()),
                    label: format!("RFC {} layout={layout} schedule={schedule}", fields[0]),
                });
            }
        }
    }
    assert_eq!(official, 12, "section2.5.2 plus all11 appendixA.3 vectors");
    let mut one = vec![0; 32];
    one[0] = 1;
    let mut two = vec![0; 32];
    two[0] = 2;
    two[16..].fill(255);
    let keys = [
        vec![0; 32],
        vec![255; 32],
        one,
        two,
        (0..32).map(|i| (i * 17 + 3) as u8).collect(),
    ];
    for length in [
        0, 1, 2, 3, 7, 8, 14, 15, 16, 17, 18, 31, 32, 33, 47, 48, 49, 63, 64, 65, 127, 128, 129,
        255, 256, 257, 511, 512, 513, 1023, 1024, 1025, 4095, 4096, 8191, 8192,
    ] {
        let message: Vec<u8> = (0..length)
            .map(|i| ((i * 37) ^ (i / 13) ^ 0xd7) as u8)
            .collect();
        for (key_index, key) in keys.iter().enumerate() {
            for layout in 0..2 {
                for schedule in 0..4 {
                    cases.push(Case { key:key.clone(),message:message.clone(),layout,schedule,official:None,label:format!("boundary length={length} key={key_index} layout={layout} schedule={schedule}") });
                }
            }
        }
    }
    let mut random = SEED;
    for index in 0..256 {
        let key = (0..32).map(|_| next(&mut random) as u8).collect();
        let length = (next(&mut random) % 8193) as usize;
        let message = (0..length).map(|_| next(&mut random) as u8).collect();
        let layout = (next(&mut random) % 2) as u8;
        let schedule = (next(&mut random) % 4) as u8;
        cases.push(Case {
            key,
            message,
            layout,
            schedule,
            official: None,
            label: format!(
                "seed={SEED:#x} random={index} length={length} layout={layout} schedule={schedule}"
            ),
        });
    }
    for index in 0..64 {
        let key: Vec<u8> = (0..32).map(|_| next(&mut random) as u8).collect();
        let mut clamped = key.clone();
        for byte in [3, 7, 11, 15] {
            clamped[byte] &= 15;
        }
        for byte in [4, 8, 12] {
            clamped[byte] &= 252;
        }
        let length = (next(&mut random) % 1025) as usize;
        let message: Vec<u8> = (0..length).map(|_| next(&mut random) as u8).collect();
        for (layout, key) in [key, clamped].into_iter().enumerate() {
            cases.push(Case {
                key,
                message: message.clone(),
                layout: layout as u8,
                schedule: 2 + layout as u8,
                official: None,
                label: format!("clamp equivalence index={index} side={layout} length={length}"),
            });
        }
    }
    assert_eq!(cases.len(), 1920);
    cases
}
fn encode(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u32).to_le_bytes().to_vec();
    for case in cases {
        bytes.extend([case.layout, case.schedule, 0, 0]);
        bytes.extend((case.message.len() as u32).to_le_bytes());
        bytes.extend(&case.key);
        bytes.extend(&case.message);
    }
    bytes
}
const PYTHON_BASE: &str = r#"
import ctypes,struct,sys
lib=ctypes.CDLL('libsodium.so.23'); lib.sodium_init.restype=ctypes.c_int
assert lib.sodium_init()>=0
mac=lib.crypto_onetimeauth_poly1305
mac.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_ulonglong,ctypes.c_void_p]; mac.restype=ctypes.c_int
def oracle(key,message):
    assert len(key)==32
    r=bytearray(key[:16])
    for i in [3,7,11,15]: r[i]&=15
    for i in [4,8,12]: r[i]&=252
    r=int.from_bytes(r,'little'); a=0; p=2**130-5
    for offset in range(0,len(message),16):
        block=message[offset:offset+16]
        a=((a+int.from_bytes(block,'little')+2**(8*len(block)))*r)%p
    expected=((a+int.from_bytes(key[16:],'little'))%(2**128)).to_bytes(16,'little')
    out=ctypes.create_string_buffer(16); data=ctypes.create_string_buffer(message,max(1,len(message))); k=ctypes.create_string_buffer(key,32)
    assert mac(out,data,len(message),k)==0
    assert out.raw==expected,('independent oracle mismatch',key.hex(),message.hex())
    return expected
"#;
const PYTHON_BATCH: &str = r#"
source=sys.stdin.buffer.read(); count=struct.unpack_from('<I',source)[0]; at=4; out=bytearray()
for index in range(count):
    layout,schedule=source[at:at+2]; size=struct.unpack_from('<I',source,at+4)[0]; at+=8
    key=source[at:at+32]; at+=32; message=source[at:at+size]; at+=size
    second=bytearray(key); second[0]^=128; second[31]^=85
    third=bytearray(second); third[1]^=90
    for k,m in [(key,message),(bytes(second),message),(key,message),(bytes(third),bytes([0,255,13,7]))]: out+=oracle(k,m)
assert at==len(source)
sys.stdout.buffer.write(out)
"#;
fn oracle(input: &common::TempArtifact, batch: bool) -> Output {
    let body = if batch {
        PYTHON_BATCH
    } else {
        "source=sys.stdin.buffer.read(); sys.stdout.buffer.write(oracle(source[:32],source[32:]))"
    };
    let program = format!("{PYTHON_BASE}\n{body}");
    let output = run(
        "Poly1305 libsodium and Python integer oracles",
        Command::new("python3")
            .args(["-c", &program])
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
    );
    checked(&output);
    output
}

#[test]
fn poly1305_rfc8439_libsodium_bigint_incremental_views_and_lifecycle_execute() {
    let executable = executable("runtime.lani"); // Compile once for all native cases.
    let cases = cases();
    let input = common::TempArtifact::new("laniusc_poly1305", "batch", None);
    input.write_bytes(encode(&cases));
    let expected = oracle(&input, true);
    assert_eq!(expected.stdout.len(), RECORD * cases.len());
    let actual = traced(&executable, &input);
    let completed = actual.stdout.len() / RECORD;
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
    for (index, case) in cases.iter().enumerate() {
        let start = index * RECORD;
        assert_eq!(
            &actual.stdout[start..start + RECORD],
            &expected.stdout[start..start + RECORD],
            "case={index} {}",
            case.label
        );
        if let Some(tag) = &case.official {
            assert_eq!(
                &actual.stdout[start..start + 16],
                tag,
                "official vector: {}",
                case.label
            );
        }
    }
    for pair in actual.stdout[(1920 - 128) * RECORD..].chunks_exact(2 * RECORD) {
        assert_eq!(
            &pair[..16],
            &pair[RECORD..RECORD + 16],
            "changing only clamped key bits preserves tag"
        );
    }
    eprintln!(
        "Poly1305:1920 native cases;12 complete RFC vectors ×2 layouts ×4 schedules; libsodium+bigint oracles; zero allocation calls"
    );
}
#[test]
fn poly1305_plain_stream_consumer_without_error_projection_allocates_nothing() {
    let executable = executable("consumer.lani");
    let input = common::TempArtifact::new("laniusc_poly1305", "stream", None);
    let mut random = SEED ^ 0x7777;
    let messages = [
        Vec::new(),
        vec![0; 15],
        vec![255; 16],
        (0..17).collect(),
        b"Cryptographic Forum Research Group".to_vec(),
        (0..1_000_003)
            .map(|i| ((i * 29) ^ (i / 251)) as u8)
            .collect(),
    ];
    for (index, message) in messages.into_iter().enumerate() {
        let mut key: Vec<u8> = (0..32).map(|_| next(&mut random) as u8).collect();
        key[0] = index as u8;
        let mut bytes = key;
        bytes.extend(&message);
        input.write_bytes(bytes);
        let expected = oracle(&input, false);
        let actual = traced(&executable, &input);
        checked(&actual);
        assert_eq!(
            actual.stdout,
            expected.stdout,
            "ordinary stream index={index} length={}",
            message.len()
        );
    }
}
