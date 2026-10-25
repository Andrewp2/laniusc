//! NIST AES-GCM vectors and independent OpenSSL EVP checks, without Cargo crypto dependencies.
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
    let entry = root.join(format!("tests/fixtures/extended/aes_gcm/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("AES-GCM", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("AEAD fixture: {error}"));
    let exe = common::TempArtifact::new("laniusc_gcm", name, None);
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
// The host oracle calls OpenSSL's independent AES-GCM implementation. It
// separately checks authentication with decrypt; no Lanius crypto is reused.
const ORACLE: &str = r#"
import ctypes,ctypes.util,struct,sys
s=ctypes.CDLL(ctypes.util.find_library('crypto')); P=ctypes.c_void_p; I=ctypes.c_int
s.EVP_CIPHER_CTX_new.restype=P; s.EVP_CIPHER_CTX_free.argtypes=[P]
s.EVP_CIPHER_CTX_ctrl.argtypes=[P,I,I,P]; s.EVP_CIPHER_CTX_ctrl.restype=I
for direction in ['Encrypt','Decrypt']:
 init=getattr(s,'EVP_'+direction+'Init_ex'); init.argtypes=[P,P,P,P,P]; init.restype=I
 update=getattr(s,'EVP_'+direction+'Update'); update.argtypes=[P,P,ctypes.POINTER(I),P,I]; update.restype=I
 final=getattr(s,'EVP_'+direction+'Final_ex'); final.argtypes=[P,P,ctypes.POINTER(I)]; final.restype=I
for bits in [128,192,256]: getattr(s,'EVP_aes_'+str(bits)+'_gcm').restype=P
def crypt(key,nonce,aad,message,tag=None):
 ctx=s.EVP_CIPHER_CTX_new(); assert ctx
 try:
  direction='Encrypt' if tag is None else 'Decrypt'
  init=getattr(s,'EVP_'+direction+'Init_ex'); update=getattr(s,'EVP_'+direction+'Update'); final=getattr(s,'EVP_'+direction+'Final_ex')
  cipher=getattr(s,'EVP_aes_'+str(len(key)*8)+'_gcm')()
  assert init(ctx,cipher,None,None,None)==1
  assert s.EVP_CIPHER_CTX_ctrl(ctx,9,len(nonce),None)==1
  assert init(ctx,None,None,key,nonce)==1
  n=I(); out=ctypes.create_string_buffer(len(message)+16)
  if aad: assert update(ctx,None,ctypes.byref(n),aad,len(aad))==1
  total=0
  if message:
   assert update(ctx,out,ctypes.byref(n),message,len(message))==1; total=n.value
  if tag is not None:
   supplied=ctypes.create_string_buffer(tag,16)
   assert s.EVP_CIPHER_CTX_ctrl(ctx,17,16,supplied)==1
  result=final(ctx,ctypes.byref(out,total),ctypes.byref(n))
  if result!=1:
   assert tag is not None; return None
  total+=n.value; assert total==len(message)
  if tag is not None: return out.raw[:total]
  produced=ctypes.create_string_buffer(16)
  assert s.EVP_CIPHER_CTX_ctrl(ctx,16,16,produced)==1
  return out.raw[:total],produced.raw
 finally: s.EVP_CIPHER_CTX_free(ctx)
# Construct a general-IV case whose J0 low word is fffffffe. The actual GCM
# output still comes solely from OpenSSL; field arithmetic only chooses the IV.
if len(sys.argv)>1:
 assert sys.argv[1]=='counter-wrap'; key=bytes.fromhex(sys.argv[2])
 cipher=getattr(s,'EVP_aes_'+str(len(key)*8)+'_ecb'); cipher.restype=P
 s.EVP_CIPHER_CTX_set_padding.argtypes=[P,I]; s.EVP_CIPHER_CTX_set_padding.restype=I
 ctx=s.EVP_CIPHER_CTX_new(); assert ctx
 try:
  assert s.EVP_EncryptInit_ex(ctx,cipher(),None,key,None)==1
  assert s.EVP_CIPHER_CTX_set_padding(ctx,0)==1
  out=ctypes.create_string_buffer(32); n=I()
  assert s.EVP_EncryptUpdate(ctx,out,ctypes.byref(n),bytes(16),16)==1; assert n.value==16
  h=int.from_bytes(out.raw[:16],'big')
 finally: s.EVP_CIPHER_CTX_free(ctx)
 def mul(x,y):
  z=0; v=y
  for i in range(128):
   if (x>>(127-i))&1: z^=v
   v=(v>>1)^((0xe1<<120) if v&1 else 0)
  return z
 def power(x,n):
  result=1<<127
  while n:
   if n&1: result=mul(result,x)
   x=mul(x,x); n>>=1
  return result
 wanted=int.from_bytes(bytes(range(12))+bytes.fromhex('fffffffe'),'big')
 hh=mul(h,h); inv=power(hh,(1<<128)-2); assert mul(hh,inv)==1<<127
 iv=mul(wanted^mul(128,h),inv)
 assert mul(mul(iv,h)^128,h)==wanted
 sys.stdout.buffer.write(iv.to_bytes(16,'big')); sys.exit(0)
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
 elif kl not in [16,24,32]: status=2
 elif nl==0: status=3
 elif tl!=16: status=4
 elif cap<il: status=5
 elif op%2==0: result,tag=crypt(key,nonce,aad,source)
 else:
  result=crypt(key,nonce,aad,source,tag)
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
    let file = common::TempArtifact::new("laniusc_gcm", "open_inputs", None);
    file.write_bytes(input(cases));
    let reference = common::process_output_with_timeout(
        "OpenSSL decryption-input preparation",
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
        if value.operation % 2 == 0 {
            assert_eq!(status, 0);
            assert_eq!(written, value.input.len());
            let mut open = value.clone();
            open.operation += 1;
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
    let file = common::TempArtifact::new("laniusc_gcm", "input", None);
    file.write_bytes(input(&cases));
    let oracle = common::process_output_with_timeout(
        "OpenSSL AES-GCM reference",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(10),
    );
    checked(&oracle);
    let trace = common::TempArtifact::new("laniusc_gcm", "memory", None);
    let native = common::process_output_with_timeout(
        "native AES-GCM protocol",
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
                "published NIST output case{index}"
            );
            assert_eq!(
                &expected[c.capacity..],
                known_tag,
                "published NIST tag case{index}"
            );
        }
        actual_at += length;
        expected_at += length;
    }
    assert_eq!(actual_at, native.stdout.len());
    assert_eq!(expected_at, oracle.stdout.len());
    eprintln!("AES-GCM protocol commands={}", cases.len());
}
// NIST AES_GCM.pdf examples1 and5, all three key widths. Full tags only.
fn nist_cases() -> Vec<Case> {
    let key = hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308");
    let nonce = hex("cafebabefacedbaddecaf888");
    let aad = hex("3ad77bb40d7a3660a89ecaf32466ef97f5d3d585");
    let plain = hex(concat!(
        "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72",
        "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
    ));
    let ciphertexts = [
        concat!(
            "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e",
            "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091"
        ),
        concat!(
            "3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c",
            "7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda2710"
        ),
        concat!(
            "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa",
            "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662"
        ),
    ];
    let empty_tags = [
        "3247184b3c4f69a44dbcd22887bbb418",
        "c835aa88aebbc94f5a02e179fdcfc3e4",
        "fd2caa16a5832e76aa132c1453eeda7e",
    ];
    let tags = [
        "f07c2528eea2fca1211f905e1b6a881b",
        "93ea28c659e269902a80acd208e7fc80",
        "e097195f4532da895fb917a5a55c6aa0",
    ];
    let mut result = Vec::new();
    for (index, length) in [16, 24, 32].into_iter().enumerate() {
        for op in [0, 2] {
            let mut empty = case(op, &key[..length], &nonce, &[], &[], &[222; 16]);
            empty.known = Some((vec![], hex(empty_tags[index])));
            layouts(empty, &mut result);
            let mut nonempty = case(op, &key[..length], &nonce, &aad, &plain, &[222; 16]);
            nonempty.known = Some((hex(ciphertexts[index]), hex(tags[index])));
            layouts(nonempty, &mut result);
        }
    }
    result
}
#[test]
fn nist_vectors_nonce_aad_and_payload_boundaries_match_openssl() {
    let mut cases = nist_cases();
    // Cross padding and counter-block boundaries without a huge Cartesian test.
    for keylen in [16, 24, 32] {
        for (i, length) in [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257]
            .into_iter()
            .enumerate()
        {
            let nonce_lengths = [1, 8, 12, 13, 15, 16, 17, 31, 32, 33, 64, 128, 12, 12];
            let aad_lengths = [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 257];
            let mut value = case(
                if i % 2 == 0 { 0 } else { 2 },
                &pattern(keylen, i),
                &pattern(nonce_lengths[i], i + 5),
                &pattern(aad_lengths[i], 29),
                &pattern(length, 71),
                &[222; 16],
            );
            value.layout = (i % 2) as u64;
            value.inplace = i % 3 == 0;
            if !value.inplace {
                value.capacity += 9;
            }
            cases.push(value);
        }
    }
    // A legal TLS-sized payload, in both directions through the independent peer.
    for layout in [0, 1] {
        let mut value = case(
            0,
            &pattern(16, 193),
            &pattern(12, 101),
            &pattern(5, 7),
            &pattern(16384, 37),
            &[222; 16],
        );
        value.layout = layout;
        value.inplace = layout == 1;
        cases.push(value);
    }
    for length in [16, 24, 32] {
        cases.push(case(
            2,
            &pattern(length, 177),
            &pattern(15, 63),
            &pattern(33, 101),
            &[],
            &[222; 16],
        ));
    }
    let key = pattern(24, 33);
    let key_hex: String = key.iter().map(|byte| format!("{byte:02x}")).collect();
    let nonce = common::process_output_with_timeout(
        "OpenSSL-derived GHASH counter-wrap nonce",
        Command::new("python3").args(["-c", ORACLE, "counter-wrap", &key_hex]),
        Duration::from_secs(10),
    );
    checked(&nonce);
    assert_eq!(nonce.stdout.len(), 16);
    for layout in [0, 1] {
        let mut value = case(
            2,
            &key,
            &nonce.stdout,
            &pattern(17, 27),
            &pattern(49, 39),
            &[222; 16],
        );
        value.layout = layout;
        value.inplace = layout == 1;
        cases.push(value);
    }
    add_independent_open_cases(&mut cases);
    assert_eq!(cases.len(), 194);
    compare(cases);
}
#[test]
fn every_authenticated_component_mutation_preserves_destination() {
    // First obtain a valid non-96-bit nonce vector from OpenSSL.
    let mut prepared = vec![case(
        0,
        &pattern(32, 7),
        &pattern(17, 9),
        &pattern(17, 19),
        &pattern(33, 31),
        &[222; 16],
    )];
    add_independent_open_cases(&mut prepared);
    let original = prepared.pop().unwrap();
    let mut cases = Vec::new();
    for component in 0..5 {
        let length = match component {
            0 => original.key.len(),
            1 => original.nonce.len(),
            2 => original.aad.len(),
            3 => original.input.len(),
            _ => original.tag.len(),
        };
        for index in 0..length {
            let mut value = original.clone();
            value.known = None;
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
    assert_eq!(cases.len(), 460);
    compare(cases);
}
#[test]
fn invalid_views_lengths_capacities_and_priority_preserve_destinations() {
    let mut cases = Vec::new();
    for operation in [0, 1] {
        let base = case(
            operation,
            &pattern(16, 9),
            &pattern(12, 11),
            &pattern(17, 13),
            &pattern(33, 17),
            &[222; 16],
        );
        for target in 1..=6 {
            for variant in 0..3 {
                let mut v = base.clone();
                v.target = target;
                v.variant = variant;
                layouts(v, &mut cases);
            }
        }
        for length in [0, 15, 17, 23, 25, 31, 33] {
            let mut v = base.clone();
            v.key = pattern(length, 3);
            layouts(v, &mut cases);
        }
        let mut v = base.clone();
        v.nonce.clear();
        layouts(v, &mut cases);
        for length in [0, 4, 8, 12, 15, 17] {
            let mut v = base.clone();
            v.tag = pattern(length, 3);
            layouts(v, &mut cases);
        }
        for cap in [0, 32] {
            for layout in [0, 1] {
                for inplace in [false, true] {
                    let mut v = base.clone();
                    v.capacity = cap;
                    v.layout = layout;
                    v.inplace = inplace;
                    cases.push(v);
                }
            }
        }
        for target in 1..=6 {
            let mut v = case(operation, &[], &[], &[], &[], &[]);
            v.target = target;
            v.variant = 2;
            layouts(v, &mut cases);
        }
        // Nonce, then tag, then capacity priority after a valid key.
        for (nonce, tag, cap) in [(0, 0, 0), (12, 0, 0), (12, 16, 0)] {
            let mut v = base.clone();
            v.nonce = pattern(nonce, 3);
            v.tag = pattern(tag, 3);
            v.capacity = cap;
            cases.push(v);
        }
    }
    // Key-method malformed views, after constructing a valid independent key.
    for operation in [2, 3] {
        for target in 2..=6 {
            for variant in 0..3 {
                let mut v = case(
                    operation,
                    &pattern(24, 7),
                    &pattern(12, 9),
                    &[],
                    &[],
                    &[222; 16],
                );
                v.target = target;
                v.variant = variant;
                cases.push(v);
            }
        }
    }
    for operation in [2, 3] {
        for (nonce_len, tag_len) in [(0, 16), (12, 0), (12, 15), (12, 17)] {
            cases.push(case(
                operation,
                &pattern(32, 19),
                &pattern(nonce_len, 11),
                &[],
                &[],
                &pattern(tag_len, 9),
            ));
        }
        for target in [0, 1] {
            let mut value = case(operation, &[], &pattern(12, 11), &[], &[], &[222; 16]);
            value.target = target;
            value.variant = 2;
            cases.push(value);
        }
    }
    assert_eq!(cases.len(), 368);
    compare(cases);
}
#[test]
fn ordinary_consumer_uses_copied_key_and_both_aead_directions() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_gcm", "plain_memory", None);
    let output = common::process_output_with_timeout(
        "ordinary AES-GCM consumer",
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
