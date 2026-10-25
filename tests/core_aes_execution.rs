//! AES block execution: primary FIPS197 vectors and independent OpenSSL EVP.
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
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/aes/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("AES block", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("AES fixture: {e}"));
    let exe = common::TempArtifact::new("laniusc_aes", name, None);
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
    decrypt: bool,
    layout: u64,
    alias: u64,
    copied: bool,
    key: Vec<u8>,
    input: Vec<u8>,
    capacity: usize,
    target: u64,
    variant: u64,
    known: Option<Vec<u8>>,
}
fn case(key: &[u8], input: &[u8], decrypt: bool) -> Case {
    Case {
        decrypt,
        layout: 0,
        alias: 0,
        copied: false,
        key: key.to_vec(),
        input: input.to_vec(),
        capacity: 25,
        target: 0,
        variant: 0,
        known: None,
    }
}
fn hex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|v| u8::from_str_radix(std::str::from_utf8(v).unwrap(), 16).unwrap())
        .collect()
}
fn pattern(n: usize, salt: usize) -> Vec<u8> {
    (0..n)
        .map(|i| ((i * 73 + salt + i / 7) & 255) as u8)
        .collect()
}
fn layouts(value: Case, cases: &mut Vec<Case>) {
    for layout in [0, 1] {
        for alias in 0..4 {
            for copied in [false, true] {
                let mut v = value.clone();
                v.layout = layout;
                v.alias = alias;
                v.copied = copied;
                cases.push(v);
            }
        }
    }
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        for v in [
            c.decrypt as u64,
            c.layout,
            c.alias,
            c.copied as u64,
            c.key.len() as u64,
            c.input.len() as u64,
            c.capacity as u64,
            c.target,
            c.variant,
            0,
        ] {
            bytes.extend(v.to_le_bytes());
        }
        bytes.extend(&c.key);
        bytes.extend(&c.input);
    }
    bytes
}
const ORACLE: &str = r#"
import ctypes,ctypes.util,struct,sys
s=ctypes.CDLL(ctypes.util.find_library('crypto'));P=ctypes.c_void_p;I=ctypes.c_int
s.EVP_CIPHER_CTX_new.restype=P;s.EVP_CIPHER_CTX_free.argtypes=[P]
s.EVP_CIPHER_CTX_set_padding.argtypes=[P,I];s.EVP_CIPHER_CTX_set_padding.restype=I
for bits in [128,192,256]:getattr(s,'EVP_aes_'+str(bits)+'_ecb').restype=P
for direction in ['Encrypt','Decrypt']:
 init=getattr(s,'EVP_'+direction+'Init_ex');init.argtypes=[P,P,P,P,P];init.restype=I
 update=getattr(s,'EVP_'+direction+'Update');update.argtypes=[P,P,ctypes.POINTER(I),P,I];update.restype=I
 final=getattr(s,'EVP_'+direction+'Final_ex');final.argtypes=[P,P,ctypes.POINTER(I)];final.restype=I
def block(key,source,decrypt):
 ctx=s.EVP_CIPHER_CTX_new();assert ctx
 try:
  d='Decrypt' if decrypt else 'Encrypt';cipher=getattr(s,'EVP_aes_'+str(len(key)*8)+'_ecb')()
  assert getattr(s,'EVP_'+d+'Init_ex')(ctx,cipher,None,key,None)==1
  assert s.EVP_CIPHER_CTX_set_padding(ctx,0)==1
  out=ctypes.create_string_buffer(32);n=I()
  assert getattr(s,'EVP_'+d+'Update')(ctx,out,ctypes.byref(n),source,16)==1;total=n.value
  assert getattr(s,'EVP_'+d+'Final_ex')(ctx,ctypes.byref(out,total),ctypes.byref(n))==1;total+=n.value
  assert total==16;return out.raw[:16]
 finally:s.EVP_CIPHER_CTX_free(ctx)
data=sys.stdin.buffer.read();at=0
def words(n):
 global at
 result=struct.unpack_from('<'+'Q'*n,data,at);at+=8*n;return result
def take(n):
 global at
 result=data[at:at+n];assert len(result)==n;at+=n;return result
count,=words(1)
for _ in range(count):
 decrypt,layout,alias,copied,kl,il,cap,target,variant,reserved=words(10)
 key,source=take(kl),take(il);memory=bytearray([222]*64);memory[3:3+il]=source
 start={0:3,1:3,2:4,3:2}[alias];out=memory[start:start+cap] if alias else bytes([222])*cap
 status=0;written=0
 if target==1:status=1
 elif kl not in [16,24,32]:status=2
 elif target:status=1
 elif il!=16:status=3
 elif cap<16:status=4
 else:
  out=block(key,source,decrypt)+out[16:];written=16
 sys.stdout.buffer.write(struct.pack('<QQQ',status,written,cap)+out)
assert at==len(data)
"#;
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdout bytes={} stderr={:?}",
        output.stdout.len(),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let result = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    result
}
fn compare(cases: Vec<Case>) {
    let data = common::TempArtifact::new("laniusc_aes", "input", None);
    data.write_bytes(input(&cases));
    let oracle = common::process_output_with_timeout(
        "OpenSSL AES block oracle",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())),
        Duration::from_secs(10),
    );
    checked(&oracle);
    let trace = common::TempArtifact::new("laniusc_aes", "memory", None);
    let native = common::process_output_with_timeout(
        "native AES blocks",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let mut a = 0;
    let mut e = 0;
    for (index, c) in cases.iter().enumerate() {
        let strides = (
            word(&native.stdout, &mut a) as i64,
            word(&native.stdout, &mut a) as i64,
        );
        if c.layout == 0 {
            assert!(strides.0 < 0 && strides.1 < 0);
        } else {
            assert_eq!(strides, (1, 1));
        }
        for _ in 0..3 {
            assert_eq!(
                word(&native.stdout, &mut a),
                word(&oracle.stdout, &mut e),
                "case{index}: {c:?}"
            );
        }
        assert_eq!(
            &native.stdout[a..a + c.capacity],
            &oracle.stdout[e..e + c.capacity],
            "case{index}: {c:?}"
        );
        if let Some(known) = &c.known {
            assert_eq!(&oracle.stdout[e..e + 16], known, "FIPS197 case{index}");
        }
        a += c.capacity;
        e += c.capacity;
    }
    assert_eq!(a, native.stdout.len());
    assert_eq!(e, oracle.stdout.len());
    eprintln!("AES block protocol commands={}", cases.len());
}
#[test]
fn fips197_all_key_widths_and_full_byte_domain_match_openssl() {
    // Original FIPS197 appendixC, unchanged algorithm in the 2023 update.
    let plain = hex("00112233445566778899aabbccddeeff");
    let mut cases = Vec::new();
    for (length, cipher) in [
        (16, "69c4e0d86a7b0430d8cdb78070b4c55a"),
        (24, "dda97ca4864cdfe06eaf70a0ec0d7191"),
        (32, "8ea2b7ca516745bfeafc49904b496089"),
    ] {
        let key: Vec<u8> = (0..length).map(|i| i as u8).collect();
        let cipher = hex(cipher);
        let mut enc = case(&key, &plain, false);
        enc.known = Some(cipher.clone());
        layouts(enc, &mut cases);
        let mut dec = case(&key, &cipher, true);
        dec.known = Some(plain.clone());
        layouts(dec, &mut cases);
    }
    // Zero-key forward initial round visits every S-box input byte; independent
    // inverse checks and diverse keys exercise both algebraic transformations.
    for value in 0..256 {
        for decrypt in [false, true] {
            let mut v = case(&[0; 16], &vec![value as u8; 16], decrypt);
            v.layout = (value % 2) as u64;
            v.alias = (value % 4) as u64;
            v.copied = value % 3 == 0;
            cases.push(v);
        }
    }
    for length in [16, 24, 32] {
        for seed in 0..24 {
            for decrypt in [false, true] {
                let mut v = case(
                    &pattern(length, seed * 13),
                    &pattern(16, seed * 19),
                    decrypt,
                );
                v.layout = (seed % 2) as u64;
                v.alias = (seed % 4) as u64;
                v.copied = seed % 2 == 0;
                cases.push(v);
            }
        }
    }
    assert_eq!(cases.len(), 752);
    compare(cases);
}
#[test]
fn constructor_block_and_destination_errors_preserve_bytes() {
    let mut cases = Vec::new();
    for decrypt in [false, true] {
        let base = case(&pattern(24, 9), &pattern(16, 17), decrypt);
        for target in 1..=3 {
            for variant in 0..3 {
                let mut v = base.clone();
                v.target = target;
                v.variant = variant;
                layouts(v, &mut cases);
            }
        }
        for length in [0, 1, 15, 17, 23, 25, 31, 33] {
            let mut v = base.clone();
            v.key = pattern(length, 3);
            layouts(v, &mut cases);
        }
        for length in [0, 1, 15, 17, 32] {
            let mut v = base.clone();
            v.input = pattern(length, 7);
            layouts(v, &mut cases);
        }
        for cap in [0, 1, 15] {
            let mut v = base.clone();
            v.capacity = cap;
            layouts(v, &mut cases);
        }
        let mut v = base.clone();
        v.input.clear();
        v.capacity = 0;
        layouts(v, &mut cases);
        // Constructor first: malformed key metadata precedes its invalid length;
        // invalid key length is returned before attempting block method calls.
        let mut v = base.clone();
        v.key.clear();
        v.target = 1;
        layouts(v, &mut cases);
        let mut v = base.clone();
        v.key.clear();
        v.target = 2;
        layouts(v, &mut cases);
        // Both block views validated before block length/capacity.
        let mut v = base.clone();
        v.input.clear();
        v.capacity = 0;
        v.target = 3;
        layouts(v, &mut cases);
    }
    assert_eq!(cases.len(), 928);
    compare(cases);
}
#[test]
fn ordinary_consumer_retains_copied_schedule_and_overlapping_blocks() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_aes", "plain_memory", None);
    let output = common::process_output_with_timeout(
        "ordinary AES consumer",
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
