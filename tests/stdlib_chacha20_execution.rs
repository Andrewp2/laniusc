// Ordinary imported use plus one batched RFC/libsodium differential program.
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
        .join("tests/fixtures/stdlib_foundation/chacha20")
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
    let exe = common::TempArtifact::new("laniusc_chacha20", name, None);
    exe.write_bytes(bytes); // Common strict ELF and native x86 instruction checks.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(label: &str, exe: &common::TempArtifact, input: Option<&common::TempArtifact>) -> Vec<u8> {
    let trace = common::TempArtifact::new("laniusc_chacha20", label, None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path());
    if let Some(input) = input {
        command.stdin(File::open(input.path()).unwrap());
    }
    let output = common::process_output_with_timeout(label, &mut command, Duration::from_secs(20));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "ChaCha20 must allocate/release no backing: {events}"
    );
    output.stdout
}
#[test]
fn ietf_chacha20_plain_imported_consumer_executes_without_error_projection() {
    let exe = executable("plain.lani");
    assert!(run("plain ChaCha20 consumer", &exe, None).is_empty());
}
const SODIUM: &str = r#"
import ctypes, struct, sys
lib=ctypes.CDLL('libsodium.so.23'); assert lib.sodium_init() >= 0
xor=lib.crypto_stream_chacha20_ietf_xor_ic
xor.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_ulonglong,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_void_p]
xor.restype=ctypes.c_int
def encrypt(key,nonce,counter,message):
    out=ctypes.create_string_buffer(max(1,len(message)))
    source=ctypes.create_string_buffer(message,len(message)+1)
    k=ctypes.create_string_buffer(key,33); n=ctypes.create_string_buffer(nonce,13)
    assert xor(out,source,len(message),n,counter,k) == 0
    return out.raw[:len(message)]
# RFC8439 sections2.3.2/2.4.2 and A.1/A.2, independent of generated cases.
assert encrypt(bytes(32),bytes(12),0,bytes(64)).hex() == '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586'
assert encrypt(bytes(range(32)),bytes.fromhex('000000090000004a00000000'),1,bytes(64)).hex() == '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e'
sunscreen=b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
assert encrypt(bytes(range(32)),bytes.fromhex('000000000000004a00000000'),1,sunscreen).hex() == '6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d'
source=open(sys.argv[1],'rb').read(); at=0; out=bytearray()
while at < len(source):
    mode,counter,length,schedule,layout=struct.unpack_from('<5Q',source,at); at+=40
    key=source[at:at+32]; nonce=source[at+32:at+44]; at+=44
    message=source[at:at+length]; assert len(message)==length; at+=length
    result=encrypt(key,nonce,counter,message)
    out+=struct.pack('<Q',len(result))+result
assert at==len(source); sys.stdout.buffer.write(out)
"#;
#[test]
fn ietf_chacha20_vectors_streaming_layouts_and_counter_contracts_match_libsodium() {
    let mut input = Vec::new();
    let mut records = Vec::new();
    let mut ends = Vec::new();
    let mut expected_size = 0;
    let mut append = |mode: u64,
                      counter: u32,
                      message: &[u8],
                      schedule: u64,
                      layout: u64,
                      key: &[u8; 32],
                      nonce: &[u8; 12]| {
        let record = [mode, counter as u64, message.len() as u64, schedule, layout];
        for value in record {
            input.extend_from_slice(&value.to_le_bytes());
        }
        input.extend_from_slice(key);
        input.extend_from_slice(nonce);
        input.extend_from_slice(message);
        records.push(record);
        expected_size += 8 + message.len();
        ends.push(expected_size);
    };
    let key: [u8; 32] = std::array::from_fn(|i| ((i * 17 + 211) & 255) as u8);
    let nonce: [u8; 12] = std::array::from_fn(|i| ((i * 29 + 131) & 255) as u8);
    for counter in [0, u32::MAX - 1, u32::MAX] {
        for length in [
            0usize, 1, 31, 63, 64, 65, 127, 128, 129, 255, 256, 257, 1024,
        ] {
            if length as u64 > (u32::MAX as u64 + 1 - counter as u64) * 64 {
                continue;
            }
            let message: Vec<u8> = (0..length)
                .map(|i| ((i * 131 + i / 7 + 19) & 255) as u8)
                .collect();
            for mode in 0..4 {
                for schedule in 0..if mode % 2 == 0 { 1 } else { 4 } {
                    for layout in 0..4 {
                        append(mode, counter, &message, schedule, layout, &key, &nonce);
                    }
                }
            }
        }
    }
    // The four A.1 block vectors plus section2.3.2 and terminal counterMAX.
    let sequence: [u8; 32] = std::array::from_fn(|i| i as u8);
    let mut last = [0u8; 32];
    last[31] = 1;
    let mut second = [0u8; 32];
    second[1] = 255;
    for (k, n, counter) in [
        ([0; 32], [0; 12], 0),
        ([0; 32], [0; 12], 1),
        (last, [0; 12], 1),
        (second, [0; 12], 2),
        (sequence, [0, 0, 0, 9, 0, 0, 0, 74, 0, 0, 0, 0], 1),
        (key, nonce, u32::MAX),
    ] {
        for layout in 0..4 {
            append(4, counter, &[0; 64], 0, layout, &k, &n);
        }
    }
    let poem=b"'Twas brillig, and the slithy toves\nDid gyre and gimble in the wabe:\nAll mimsy were the borogoves,\nAnd the mome raths outgrabe.";
    let poem_key: [u8; 32] = [
        0x1c, 0x92, 0x40, 0xa5, 0xeb, 0x55, 0xd3, 0x8a, 0xf3, 0x33, 0x88, 0x86, 0x04, 0xf6, 0xb5,
        0xf0, 0x47, 0x39, 0x17, 0xc1, 0x40, 0x2b, 0x80, 0x09, 0x9d, 0xca, 0x5c, 0xbc, 0x20, 0x70,
        0x75, 0xc0,
    ];
    for (k,n,counter,message) in [
        (sequence,[0,0,0,0,0,0,0,74,0,0,0,0],1,b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".as_slice()),
        ([0;32],[0;12],0,[0;64].as_slice()),
        (poem_key,[0,0,0,0,0,0,0,0,0,0,0,2],42,poem.as_slice()),
    ] {for mode in 0..4 {for layout in 0..4 {append(mode,counter,message,2,layout,&k,&n);}}}
    assert_eq!(records.len(), 1112);
    let input_file = common::TempArtifact::new("laniusc_chacha20", "model_input", None);
    input_file.write_bytes(input);
    let oracle = common::process_output_with_timeout(
        "independent libsodium IETF ChaCha20 oracle",
        Command::new("python3")
            .arg("-c")
            .arg(SODIUM)
            .arg(input_file.path()),
        Duration::from_secs(10),
    );
    assert!(
        oracle.status.success() && oracle.stderr.is_empty(),
        "{oracle:?}"
    );
    assert_eq!(oracle.stdout.len(), expected_size);
    let exe = executable("model.lani");
    let actual = run(
        "ChaCha20 counter and stream models",
        &exe,
        Some(&input_file),
    );
    if actual != oracle.stdout {
        let at = actual
            .iter()
            .zip(&oracle.stdout)
            .position(|(a, b)| a != b)
            .unwrap_or(actual.len().min(oracle.stdout.len()));
        let case = ends.partition_point(|end| *end <= at);
        let start = if case == 0 { 0 } else { ends[case - 1] };
        let end = ends.get(case).copied().unwrap_or(start);
        panic!("ChaCha20 case {case} {:?}, response byte {}, actual {:?}, expected {:?}; total lengths {} vs {}",records.get(case),at-start,actual.get(start..end.min(actual.len())),oracle.stdout.get(start..end.min(oracle.stdout.len())),actual.len(),oracle.stdout.len());
    }
}
