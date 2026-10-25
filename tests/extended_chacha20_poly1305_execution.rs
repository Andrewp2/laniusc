//! RFC8439 and independent libsodium IETF AEAD checks, without Cargo crypto dependencies.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/extended/chacha20_poly1305/{name}.lani"
    ));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("ChaCha20-Poly1305", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("AEAD fixture: {error}"));
    let exe = common::TempArtifact::new("laniusc_aead", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
#[derive(Clone, Debug)]
struct Case {
    operation: u64,
    layout: u64,
    inplace: bool,
    key: Vec<u8>,
    nonce: Vec<u8>,
    aad: Vec<u8>,
    input: Vec<u8>,
    tag: Vec<u8>,
    capacity: usize,
    target: u64,
    variant: u64,
    known: Option<(Vec<u8>, Vec<u8>)>,
}
fn case(operation: u64, key: &[u8], nonce: &[u8], aad: &[u8], input: &[u8], tag: &[u8]) -> Case {
    Case {
        operation,
        layout: 0,
        inplace: false,
        key: key.to_vec(),
        nonce: nonce.to_vec(),
        aad: aad.to_vec(),
        input: input.to_vec(),
        tag: tag.to_vec(),
        capacity: input.len(),
        target: 0,
        variant: 0,
        known: None,
    }
}
fn layouts(value: Case, cases: &mut Vec<Case>) {
    for layout in [0, 1] {
        for inplace in [false, true] {
            let mut value = value.clone();
            value.layout = layout;
            value.inplace = inplace;
            if !inplace {
                value.capacity += 9;
            }
            cases.push(value);
        }
    }
}
fn pattern(length: usize, salt: usize) -> Vec<u8> {
    (0..length)
        .map(|index| ((index * 73 + salt) & 255) as u8)
        .collect()
}
fn hex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|digits| u8::from_str_radix(std::str::from_utf8(digits).unwrap(), 16).unwrap())
        .collect()
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        for word in [
            c.operation,
            c.layout,
            c.inplace as u64,
            c.key.len() as u64,
            c.nonce.len() as u64,
            c.aad.len() as u64,
            c.input.len() as u64,
            c.tag.len() as u64,
            c.capacity as u64,
            c.target,
            c.variant,
        ] {
            bytes.extend(word.to_le_bytes());
        }
        for part in [&c.key, &c.nonce, &c.aad, &c.input, &c.tag] {
            bytes.extend(part);
        }
    }
    bytes
}
// The host oracle calls libsodium's independent IETF AEAD implementation. It
// separately checks authentication with decrypt; no Lanius crypto is reused.
const ORACLE: &str = r#"
import ctypes,struct,sys
s=ctypes.CDLL('libsodium.so.23'); assert s.sodium_init()>=0
U=ctypes.c_ulonglong; P=ctypes.c_void_p
enc=s.crypto_aead_chacha20poly1305_ietf_encrypt
enc.argtypes=[P,ctypes.POINTER(U),P,U,P,U,P,P,P]; enc.restype=ctypes.c_int
dec=s.crypto_aead_chacha20poly1305_ietf_decrypt
dec.argtypes=[P,ctypes.POINTER(U),P,P,U,P,U,P,P]; dec.restype=ctypes.c_int
def seal(key,nonce,aad,message):
 out=ctypes.create_string_buffer(len(message)+16); n=U()
 assert enc(out,ctypes.byref(n),message,len(message),aad,len(aad),None,nonce,key)==0
 assert n.value==len(message)+16; return out.raw[:n.value]
def open_(key,nonce,aad,cipher,tag):
 out=ctypes.create_string_buffer(max(1,len(cipher))); n=U()
 result=dec(out,ctypes.byref(n),None,cipher+tag,len(cipher)+len(tag),aad,len(aad),nonce,key)
 if result!=0: return None
 assert n.value==len(cipher); return out.raw[:n.value]
data=sys.stdin.buffer.read(); at=0
def words(n):
 global at
 result=struct.unpack_from('<'+'Q'*n,data,at); at+=8*n; return result
def take(n):
 global at
 result=data[at:at+n]; assert len(result)==n; at+=n; return result
count,=words(1)
for _ in range(count):
 op,layout,inplace,kl,nl,al,il,tl,cap,target,variant=words(11)
 key,nonce,aad,source,tag=take(kl),take(nl),take(al),take(il),take(tl)
 out=(source+bytes([222])*max(0,cap-il))[:cap] if inplace else bytes([222])*cap
 result=None; written=0; status=0
 if target: status=1
 elif kl!=32: status=2
 elif nl!=12: status=3
 elif tl!=16: status=4
 elif cap<il: status=5
 elif op==0:
  combined=seal(key,nonce,aad,source); result,tag=combined[:-16],combined[-16:]
 else:
  result=open_(key,nonce,aad,source,tag)
  if result is None: status=6
 if status==0:
  assert result is not None; written=len(result); out=result+out[written:]
 sys.stdout.buffer.write(struct.pack('<QQQQ',status,written,cap,tl)+out+tag)
assert at==len(data)
"#;
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdout bytes={}, prefix={:?}, stderr={:?}",
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(32)],
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "stderr={:?}",
        String::from_utf8_lossy(&output.stderr)
    );
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let value = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    value
}
// Derive decryption inputs from the independent host implementation, so all
// padding/block boundaries are tested in both directions without a native
// seal/open round trip being the only oracle.
fn add_independent_open_cases(cases: &mut Vec<Case>) {
    let file = common::TempArtifact::new("laniusc_aead", "open_inputs", None);
    file.write_bytes(input(cases));
    let reference = common::process_output_with_timeout(
        "libsodium decryption-input preparation",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(10),
    );
    checked(&reference);
    let mut at = 0;
    let mut opens = Vec::new();
    for value in cases.iter() {
        let status = word(&reference.stdout, &mut at);
        let written = word(&reference.stdout, &mut at) as usize;
        let capacity = word(&reference.stdout, &mut at) as usize;
        let taglen = word(&reference.stdout, &mut at) as usize;
        if value.operation == 0 {
            assert_eq!(status, 0);
            assert_eq!(written, value.input.len());
            let mut open = value.clone();
            open.operation = 1;
            open.input = reference.stdout[at..at + written].to_vec();
            open.tag = reference.stdout[at + capacity..at + capacity + taglen].to_vec();
            open.known = Some((value.input.clone(), open.tag.clone()));
            opens.push(open);
        }
        at += capacity + taglen;
    }
    assert_eq!(at, reference.stdout.len());
    cases.extend(opens);
}
fn compare(cases: Vec<Case>) {
    let file = common::TempArtifact::new("laniusc_aead", "input", None);
    file.write_bytes(input(&cases));
    let oracle = common::process_output_with_timeout(
        "libsodium IETF AEAD reference",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(10),
    );
    checked(&oracle);
    let trace = common::TempArtifact::new("laniusc_aead", "memory", None);
    let native = common::process_output_with_timeout(
        "native IETF AEAD protocol",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "AEAD must allocate no memory"
    );
    let mut actual_at = 0;
    let mut expected_at = 0;
    for (index, c) in cases.iter().enumerate() {
        let input_stride = word(&native.stdout, &mut actual_at) as i64;
        let output_stride = word(&native.stdout, &mut actual_at) as i64;
        if c.layout == 0 {
            assert!(
                input_stride < 0 && output_stride < 0,
                "case{index}: strided arrays"
            );
        } else {
            assert_eq!(
                (input_stride, output_stride),
                (1, 1),
                "case{index}: packed bytes"
            );
        }
        for _ in 0..4 {
            assert_eq!(
                word(&native.stdout, &mut actual_at),
                word(&oracle.stdout, &mut expected_at),
                "case{index}: {c:?}"
            );
        }
        let length = c.capacity + c.tag.len();
        let actual = &native.stdout[actual_at..actual_at + length];
        let expected = &oracle.stdout[expected_at..expected_at + length];
        assert_eq!(actual, expected, "case{index}: {c:?}");
        if let Some((known_output, known_tag)) = &c.known {
            assert_eq!(
                &expected[..known_output.len()],
                known_output,
                "published RFC output case{index}"
            );
            assert_eq!(
                &expected[c.capacity..],
                known_tag,
                "published RFC tag case{index}"
            );
        }
        actual_at += length;
        expected_at += length;
    }
    assert_eq!(actual_at, native.stdout.len());
    assert_eq!(expected_at, oracle.stdout.len());
    eprintln!("IETF AEAD protocol commands={}", cases.len());
}
fn rfc_example() -> (Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>) {
    (hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"),hex("070000004041424344454647"),hex("50515253c0c1c2c3c4c5c6c7"),
    b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".to_vec(),
    hex(concat!("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6","3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36","92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc","3ff4def08e4b7a9de576d26586cec64b6116")),hex("1ae10b594f09e26a7e902ecbd0600691"))
}
#[test]
fn rfc8439_and_padding_block_boundaries_match_libsodium() {
    let mut cases = Vec::new();
    let (key, nonce, aad, plain, cipher, tag) = rfc_example();
    let mut seal = case(0, &key, &nonce, &aad, &plain, &[222; 16]);
    seal.known = Some((cipher.clone(), tag.clone()));
    layouts(seal, &mut cases);
    let mut open = case(1, &key, &nonce, &aad, &cipher, &tag);
    open.known = Some((plain, tag));
    layouts(open, &mut cases);
    // RFC8439 A.5 includes the literal slash bytes around the UTF-8 quotation.
    let key = hex("1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0");
    let nonce = hex("000000000102030405060708");
    let aad = hex("f33388860000000000004e91");
    let plain="Internet-Drafts are draft documents valid for a maximum of six months and may be updated, replaced, or obsoleted by other documents at any time. It is inappropriate to use Internet-Drafts as reference material or to cite them other than as /“work in progress./”".as_bytes();
    let cipher = hex(concat!(
        "64a0861575861af460f062c79be643bd5e805cfd345cf389f108670ac76c8cb2",
        "4c6cfc18755d43eea09ee94e382d26b0bdb7b73c321b0100d4f03b7f355894cf",
        "332f830e710b97ce98c8a84abd0b948114ad176e008d33bd60f982b1ff37c855",
        "9797a06ef4f0ef61c186324e2b3506383606907b6a7c02b0f9f6157b53c867e4",
        "b9166c767b804d46a59b5216cde7a4e99040c5a40433225ee282a1b0a06c523e",
        "af4534d7f83fa1155b0047718cbc546a0d072b04b3564eea1b422273f548271a",
        "0bb2316053fa76991955ebd63159434ecebb4e466dae5a1073a6727627097a10",
        "49e617d91d361094fa68f0ff77987130305beaba2eda04df997b714d6c6f2c29",
        "a6ad5cb4022b02709b"
    ));
    let tag = hex("eead9d67890cbb22392336fea1851f38");
    let mut open = case(1, &key, &nonce, &aad, &cipher, &tag);
    open.known = Some((plain.to_vec(), tag.clone()));
    layouts(open, &mut cases);
    let mut seal = case(0, &key, &nonce, &aad, plain, &[222; 16]);
    seal.known = Some((cipher, tag));
    layouts(seal, &mut cases);
    for alen in [0, 1, 15, 16, 17, 31, 32, 33] {
        for length in [
            0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 1024,
        ] {
            layouts(
                case(
                    0,
                    &pattern(32, alen + length),
                    &pattern(12, alen),
                    &pattern(alen, 19),
                    &pattern(length, 71),
                    &[222; 16],
                ),
                &mut cases,
            );
        }
    }
    // Empty output with exact zero capacity is exercised in both layouts and
    // alias modes; disjoint cases otherwise carry an untouched capacity suffix.
    for layout in [0, 1] {
        let mut empty = case(0, &[0; 32], &[0; 12], &[], &[], &[222; 16]);
        empty.layout = layout;
        cases.push(empty);
    }
    assert_eq!(cases.len(), 594);
    add_independent_open_cases(&mut cases);
    assert_eq!(cases.len(), 1180);
    compare(cases);
}
#[test]
fn every_authenticated_component_mutation_rejects_before_destination_changes() {
    let (key, nonce, aad, _, cipher, tag) = rfc_example();
    let original = case(1, &key, &nonce, &aad, &cipher, &tag);
    let mut cases = Vec::new();
    // Every byte of every authenticated component, not just first/last bytes.
    for component in 0..5 {
        let length = match component {
            0 => key.len(),
            1 => nonce.len(),
            2 => aad.len(),
            3 => cipher.len(),
            _ => tag.len(),
        };
        for index in 0..length {
            let mut value = original.clone();
            let bytes = match component {
                0 => &mut value.key,
                1 => &mut value.nonce,
                2 => &mut value.aad,
                3 => &mut value.input,
                _ => &mut value.tag,
            };
            bytes[index] ^= 1u8 << (index % 8);
            layouts(value, &mut cases);
        }
    }
    assert_eq!(cases.len(), 744);
    compare(cases);
}
#[test]
fn invalid_views_lengths_and_capacities_preserve_all_destination_bytes() {
    let (key, nonce, aad, plain, cipher, tag) = rfc_example();
    let mut cases = Vec::new();
    for operation in [0, 1] {
        let source = if operation == 0 { &plain } else { &cipher };
        let base = case(operation, &key, &nonce, &aad, source, &tag);
        for target in 1..=6 {
            for variant in 0..3 {
                let mut value = base.clone();
                value.target = target;
                value.variant = variant;
                layouts(value, &mut cases);
            }
        }
        for length in [0, 31, 33] {
            let mut value = base.clone();
            value.key = pattern(length, 9);
            layouts(value, &mut cases);
        }
        for length in [0, 11, 13] {
            let mut value = base.clone();
            value.nonce = pattern(length, 9);
            layouts(value, &mut cases);
        }
        for length in [0, 15, 17] {
            let mut value = base.clone();
            value.tag = pattern(length, 9);
            layouts(value, &mut cases);
        }
        for capacity in [0, source.len() - 1] {
            for layout in [0, 1] {
                for inplace in [false, true] {
                    let mut value = base.clone();
                    value.capacity = capacity;
                    value.layout = layout;
                    value.inplace = inplace;
                    cases.push(value);
                }
            }
        }
        // Bounds precedes wrong key/nonce/tag sizes and capacity, even empty input.
        for target in 1..=6 {
            let mut value = case(operation, &[], &[], &[], &[], &[]);
            value.target = target;
            value.variant = 2;
            layouts(value, &mut cases);
        }
    }
    assert_eq!(cases.len(), 280);
    compare(cases);
}
#[test]
fn ordinary_consumer_seals_and_opens_without_error_projection() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_aead", "plain_memory", None);
    let output = common::process_output_with_timeout(
        "ordinary AEAD consumer",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(exe.path()),
        Duration::from_secs(5),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
