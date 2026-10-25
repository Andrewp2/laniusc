//! RFC vectors and independent hashlib/hmac checks through one protocol ELF.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/extended/hmac_hkdf/protocol.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("HMAC-SHA-256/HKDF-SHA-256 protocol", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("HMAC/HKDF protocol: {error}"));
        let exe = common::TempArtifact::new("laniusc_hmac_hkdf", "protocol", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
#[derive(Debug)]
struct Case {
    operation: u64,
    layout: u64,
    a: Vec<u8>,
    b: Vec<u8>,
    c: Vec<u8>,
    length: usize,
    chunk: usize,
    known: Option<Vec<u8>>,
}
fn case(operation: u64, a: &[u8], b: &[u8], c: &[u8], length: usize) -> Case {
    Case {
        operation,
        layout: 0,
        a: a.to_vec(),
        b: b.to_vec(),
        c: c.to_vec(),
        length,
        chunk: 7,
        known: None,
    }
}
fn layouts(make: impl Fn() -> Case, cases: &mut Vec<Case>) {
    for layout in [0, 1] {
        let mut value = make();
        value.layout = layout;
        cases.push(value);
    }
}
fn hex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|digits| u8::from_str_radix(std::str::from_utf8(digits).unwrap(), 16).unwrap())
        .collect()
}
fn pattern(length: usize, salt: usize) -> Vec<u8> {
    (0..length)
        .map(|index| ((index * 73 + salt) & 255) as u8)
        .collect()
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut data = (cases.len() as u64).to_le_bytes().to_vec();
    for case in cases {
        for word in [
            case.operation,
            case.layout,
            case.a.len() as u64,
            case.b.len() as u64,
            case.c.len() as u64,
            case.length as u64,
            case.chunk as u64,
        ] {
            data.extend(word.to_le_bytes());
        }
        data.extend(&case.a);
        data.extend(&case.b);
        data.extend(&case.c);
    }
    data
}
const ORACLE: &str = r#"
import hashlib,hmac,struct,sys
data=sys.stdin.buffer.read(); at=0
def words(n):
 global at
 value=struct.unpack_from('<'+'Q'*n,data,at); at+=8*n; return value
def take(n):
 global at
 value=data[at:at+n]; assert len(value)==n; at+=n; return value
def mac(key,message): return hmac.new(key,message,hashlib.sha256).digest()
def expand(prk,info,length):
 out=b''; previous=b''
 for counter in range(1,(length+31)//32+1):
  previous=mac(prk,previous+info+bytes([counter])); out+=previous
 return out[:length]
count,=words(1)
for _ in range(count):
 operation,layout,alen,blen,clen,length,chunk=words(7)
 a,b,c=take(alen),take(blen),take(clen); status=0
 if operation==0: result=mac(a,b)
 elif operation==1: result=mac(a or bytes(32),b)
 elif operation==2:
  if len(a)<32: status=2; result=b''
  elif length>8160: status=3; result=b''
  else: result=expand(a,b,length)
 elif operation==3:
  if length>8160: status=3; result=b''
  else: result=expand(mac(a or bytes(32),b),c,length)
 elif operation==4:
  ka=bytes([11])*20; kb=b'Jefe'; ma=b'Hi There'; mb=b'what do ya want for nothing?'
  result=mac(ka,ma)+mac(kb,mb)+mac(ka,b'Hi !')+mac(ka,ma)+mac(kb,b'')
 elif operation==5: result=mac(a,b)
 else: raise AssertionError(operation)
 sys.stdout.buffer.write(struct.pack('<QQ',status,len(result))+result)
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
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let value = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    value
}
fn compare(cases: Vec<Case>) {
    let file = common::TempArtifact::new("laniusc_hmac_hkdf", "input", None);
    file.write_bytes(input(&cases));
    let oracle = common::process_output_with_timeout(
        "Python HMAC/HKDF reference",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(10),
    );
    checked(&oracle);
    let trace = common::TempArtifact::new("laniusc_hmac_hkdf", "memory", None);
    let native = common::process_output_with_timeout(
        "native HMAC/HKDF protocol",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "hash/MAC/KDF operations allocate no memory: {events}"
    );
    let mut actual_at = 0;
    let mut expected_at = 0;
    for (index, case) in cases.iter().enumerate() {
        let input_stride = word(&native.stdout, &mut actual_at) as i64;
        let output_stride = word(&native.stdout, &mut actual_at) as i64;
        if case.layout == 0 {
            assert!(
                input_stride < 0 && output_stride < 0,
                "case {index}: native strided arrays"
            );
        } else {
            assert_eq!(
                (input_stride, output_stride),
                (1, 1),
                "case {index}: packed bytes"
            );
        }
        let status = word(&native.stdout, &mut actual_at);
        let length = word(&native.stdout, &mut actual_at) as usize;
        let expected_status = word(&oracle.stdout, &mut expected_at);
        let expected_length = word(&oracle.stdout, &mut expected_at) as usize;
        assert_eq!(
            (status, length),
            (expected_status, expected_length),
            "case {index}: {case:?}"
        );
        let actual = &native.stdout[actual_at..actual_at + length];
        let expected = &oracle.stdout[expected_at..expected_at + expected_length];
        assert_eq!(actual, expected, "case {index}: {case:?}");
        if let Some(known) = &case.known {
            assert_eq!(
                &expected[..known.len()],
                known,
                "published RFC vector, case {index}"
            );
        }
        actual_at += length;
        expected_at += expected_length;
    }
    assert_eq!(actual_at, native.stdout.len(), "no trailing native bytes");
    assert_eq!(expected_at, oracle.stdout.len(), "no trailing oracle bytes");
    eprintln!("HMAC/HKDF protocol commands={}", cases.len());
}

#[test]
fn rfc4231_sha256_vectors_and_streamed_key_block_boundaries_match_python() {
    // RFC4231 cases1..7. Case5 publishes only a16-byte prefix; the API still
    // returns32 bytes and the complete tag is checked against Python.
    let vectors = [
        (vec![11;20], b"Hi There".to_vec(), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
        (b"Jefe".to_vec(), b"what do ya want for nothing?".to_vec(), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"),
        (vec![170;20], vec![221;50], "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"),
        ((1..=25).collect(), vec![205;50], "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"),
        (vec![12;20], b"Test With Truncation".to_vec(), "a3b6167473100ee06e0c796c2955552b"),
        (vec![170;131], b"Test Using Larger Than Block-Size Key - Hash Key First".to_vec(), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"),
        (vec![170;131], b"This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.".to_vec(), "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2")
    ];
    let mut cases = Vec::new();
    for (key, message, tag) in vectors {
        layouts(
            || {
                let mut value = case(0, &key, &message, &[], 0);
                value.known = Some(hex(tag));
                value
            },
            &mut cases,
        );
    }
    for key_length in [0, 1, 31, 32, 63, 64, 65, 131] {
        for message_length in [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 1024] {
            let key = pattern(key_length, 17);
            let message = pattern(message_length, 251);
            layouts(
                || {
                    let mut value = case(0, &key, &message, &[], 0);
                    value.chunk = [1, 7, 64, 73][message_length % 4];
                    value
                },
                &mut cases,
            );
        }
    }
    assert_eq!(cases.len(), 190);
    compare(cases);
}

#[test]
fn rfc5869_sha256_extract_expand_and_full_output_boundaries_match_python() {
    let vectors = [
        (vec![11;22], (0..13).collect::<Vec<u8>>(), (240..250).collect::<Vec<u8>>(), 42,
         "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5",
         "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"),
        ((0..80).collect(), (96..176).collect(), (176..=255).collect(), 82,
         "06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244",
         "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87"),
        (vec![11;22], vec![], vec![], 42,
         "19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04",
         "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
    ];
    let mut cases = Vec::new();
    for (ikm, salt, info, length, prk, okm) in vectors {
        layouts(
            || {
                let mut value = case(1, &salt, &ikm, &[], 0);
                value.known = Some(hex(prk));
                value
            },
            &mut cases,
        );
        layouts(
            || {
                let mut value = case(2, &hex(prk), &info, &[], length);
                value.known = Some(hex(okm));
                value
            },
            &mut cases,
        );
        layouts(
            || {
                let mut value = case(3, &salt, &ikm, &info, length);
                value.known = Some(hex(okm));
                value
            },
            &mut cases,
        );
    }
    let prk = pattern(32, 17);
    let info = pattern(37, 39);
    for length in [0, 1, 31, 32, 33, 8159, 8160, 8161] {
        layouts(|| case(2, &prk, &info, &[], length), &mut cases);
    }
    for prk_length in [0, 1, 31] {
        for length in [0, 33] {
            layouts(
                || case(2, &pattern(prk_length, 19), &info, &[], length),
                &mut cases,
            );
        }
    }
    for prk_length in [65, 131] {
        for length in [1, 33, 82] {
            layouts(
                || case(2, &pattern(prk_length, 19), &info, &[], length),
                &mut cases,
            );
        }
    }
    for (index, salt_length) in [0, 1, 63, 64, 65, 131].into_iter().enumerate() {
        let salt = pattern(salt_length, 23);
        let ikm = pattern([0, 22, 55, 64, 65, 129][index], 91);
        let context = pattern(index * 7, 133);
        layouts(|| case(1, &salt, &ikm, &[], 0), &mut cases);
        layouts(|| case(3, &salt, &ikm, &context, 33), &mut cases);
    }
    // RFC5869 empty salt is equivalent to HashLen zero bytes.
    layouts(|| case(1, &[0; 32], &[11; 22], &[], 0), &mut cases);
    layouts(|| case(3, &[0; 32], &[11; 22], &[], 42), &mut cases);
    layouts(|| case(3, &[], &[], &[], 0), &mut cases);
    assert_eq!(cases.len(), 88);
    compare(cases);
}

#[test]
fn keyed_state_and_digest_values_are_independent_and_invalid_views_preserve_output() {
    let mut cases = Vec::new();
    layouts(|| case(4, &[], &[], &[], 0), &mut cases);
    layouts(
        || case(5, &pattern(32, 53), &pattern(65, 97), &pattern(17, 139), 0),
        &mut cases,
    );
    assert_eq!(cases.len(), 4);
    compare(cases);
}
