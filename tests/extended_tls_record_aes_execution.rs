//! TLS1.3 record state/bytes against an independent hashlib/hmac/OpenSSL peer.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn compile(stem: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/extended/tls_record_aes/{stem}.lani"
    ));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TLS record fixture", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("TLS record {stem}: {error}"));
    let exe = common::TempArtifact::new("laniusc_tls_record_aes", stem, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
#[derive(Debug, Clone)]
struct Case {
    operation: u64,
    layout: u64,
    kind: u64,
    padding: i64,
    sequence: u64,
    variant: u64,
    capacity: usize,
    secret: [u8; 32],
    data: Vec<u8>,
}
fn case(operation: u64, length: usize) -> Case {
    Case {
        operation,
        layout: 0,
        kind: 23,
        padding: 0,
        sequence: 0,
        variant: 0,
        capacity: if operation == 0 || operation == 3 {
            16650
        } else {
            length + 4
        },
        secret: std::array::from_fn(|index| (index * 7 + 3) as u8),
        data: (0..length).map(|index| (index * 73 + 11) as u8).collect(),
    }
}
fn layouts(value: Case, cases: &mut Vec<Case>) {
    for layout in [0, 1] {
        let mut next = value.clone();
        next.layout = layout;
        cases.push(next);
    }
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for case in cases {
        for word in [
            case.operation,
            case.layout,
            case.kind,
            case.padding as u64,
            case.sequence,
            case.variant,
            case.data.len() as u64,
            case.capacity as u64,
        ] {
            bytes.extend(word.to_le_bytes());
        }
        bytes.extend(case.secret);
        bytes.extend(&case.data);
    }
    bytes
}
const PEER: &str = r#"

import ctypes,ctypes.util,hashlib,hmac,struct,sys
s=ctypes.CDLL(ctypes.util.find_library('crypto')); P=ctypes.c_void_p; I=ctypes.c_int
s.EVP_CIPHER_CTX_new.restype=P; s.EVP_CIPHER_CTX_free.argtypes=[P]
s.EVP_CIPHER_CTX_ctrl.argtypes=[P,I,I,P]; s.EVP_CIPHER_CTX_ctrl.restype=I
for direction in ['Encrypt','Decrypt']:
 init=getattr(s,'EVP_'+direction+'Init_ex'); init.argtypes=[P,P,P,P,P]; init.restype=I
 update=getattr(s,'EVP_'+direction+'Update'); update.argtypes=[P,P,ctypes.POINTER(I),P,I]; update.restype=I
 final=getattr(s,'EVP_'+direction+'Final_ex'); final.argtypes=[P,P,ctypes.POINTER(I)]; final.restype=I
for bits in [128,192,256]: getattr(s,'EVP_aes_'+str(bits)+'_gcm').restype=P
def crypt(key,nonce,aad,message,tag=None,chacha=False):
 ctx=s.EVP_CIPHER_CTX_new(); assert ctx
 try:
  direction='Encrypt' if tag is None else 'Decrypt'
  init=getattr(s,'EVP_'+direction+'Init_ex'); update=getattr(s,'EVP_'+direction+'Update'); final=getattr(s,'EVP_'+direction+'Final_ex')
  cipher_fn=s.EVP_chacha20_poly1305 if chacha else getattr(s,'EVP_aes_'+str(len(key)*8)+'_gcm'); cipher_fn.restype=P
  cipher=cipher_fn()
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
def expand(secret,label,length):
 label=b'tls13 '+label; info=struct.pack('>H',length)+bytes([len(label)])+label+b'\0'
 # All TLS labels here request at most one SHA256 block.
 return hmac.new(secret,info+b'\1',hashlib.sha256).digest()[:length]
def keys(secret,sequence,chacha=False):
 key=expand(secret,b'key',32 if chacha else 16); iv=expand(secret,b'iv',12)
 nonce=bytes(a^b for a,b in zip(iv,bytes(4)+sequence.to_bytes(8,'big'))); return key,nonce
def record(secret,sequence,plain,chacha=False):
 key,nonce=keys(secret,sequence,chacha); header=b'\x17\x03\x03'+struct.pack('>H',len(plain)+16)
 ciphertext,tag=crypt(key,nonce,header,plain,chacha=chacha)
 return header+ciphertext+tag
def decrypt(secret,sequence,packet):
 key,nonce=keys(secret,sequence)
 return crypt(key,nonce,packet[:5],packet[5:-16],packet[-16:])
def q(*words): return struct.pack('<'+'Q'*len(words),*words)
source=sys.stdin.buffer.read(); at=0
def words(n):
 global at
 value=struct.unpack_from('<'+'Q'*n,source,at); at+=8*n; return value
def take(n):
 global at
 value=source[at:at+n]; assert len(value)==n; at+=n; return value
count,=words(1); native=q(count); expected=b''
for _ in range(count):
 operation,layout,kind,padding,sequence,variant,length,capacity=words(8); secret=take(32); data=take(length)
 signed_padding=padding if padding<2**63 else padding-2**64
 observed=b''; result=b''; result_kind=0; status=0; after=sequence; exhausted=sequence>=2**24 or (variant==4 if operation in (0,3) else variant==30); poisoned=False
 packet=data
 if operation in (0,3):
  if variant in (1,2,5,6): status=1
  elif exhausted: status=8
  elif kind not in (21,22,23): status=3
  elif len(data)>16384 or (kind==21 and len(data)!=2) or (kind==22 and not data): status=4
  elif signed_padding<0 or signed_padding>16384-len(data): status=5
  elif capacity<len(data)+signed_padding+22: status=7
  else:
   result=record(secret,sequence,data+bytes([kind])+bytes(signed_padding))
   after+=1; exhausted=after>=2**24
 elif operation in (1,4):
  plain=data+bytes([kind])+bytes(max(0,signed_padding))
  if variant==9: plain=bytes(max(1,len(data)))
  if variant==10: plain=data+b'\x18'
  if variant==11: plain=data+b'\x14'
  if variant==12: plain=b'\x16'+bytes(7)
  if variant==13: plain=b'\x15'
  if variant==14: plain=b'x\x15'
  if variant==15: plain=b'xyz\x15'
  if variant==16: plain=b'x'*16385+b'\x17'
  packet=record(secret,sequence,plain)
  if variant==1: packet=packet[:-1]+bytes([packet[-1]^1])
  if variant==2: packet=packet[:5]+bytes([packet[5]^1])+packet[6:]
  if variant==3: packet=b'\x14'+packet[1:]
  if variant==4: packet=packet[:2]+b'\x01'+packet[3:]
  if variant==5: packet=packet[:-1]
  if variant==6: packet+=b'\0'
  if variant==7: packet=packet[:4]+bytes([packet[4]^1])+packet[5:]
  if variant==8: packet=b'\x17\x03\x03'+struct.pack('>H',16641)
  if variant==17: packet=b'\x17\x03\x03\x00\x10'+bytes(16)
  if variant==18: packet=packet[:4]
  if variant==19: packet=record(secret,sequence,plain,True)
  if variant==20: packet=record(secret,sequence^1,plain)
  if variant==21: packet=record(bytes([secret[0]^1])+secret[1:],sequence,plain)
  observed=bytes([222])*capacity
  if variant in (31,32): status=1
  elif exhausted: status=8
  elif len(packet)<5: status=10; poisoned=True
  else:
   declared=int.from_bytes(packet[3:5],'big')
   if declared>16640: status=6; poisoned=True
   elif packet[:3]!=b'\x17\x03\x03' or declared<17 or len(packet)!=declared+5: status=10; poisoned=True
   elif capacity<declared-16: status=7
   else:
    decrypted=decrypt(secret,sequence,packet)
    if decrypted is None: status=11; poisoned=True
    else:
     observed=decrypted+bytes([222])*(capacity-len(decrypted))
     unpadded=decrypted.rstrip(b'\0')
     if len(decrypted)>16385: status=6; poisoned=True
     elif not unpadded or unpadded[-1] not in (21,22,23): status=12; poisoned=True
     else:
      result_kind=unpadded[-1]; result=unpadded[:-1]
      if len(result)>16384 or (result_kind==21 and len(result)!=2) or (result_kind==22 and not result): status=12; poisoned=True; result_kind=0; result=b''
      else: after+=1; exhausted=after>=2**24
 elif operation==2:
  current=secret; result=b''
  for step in range(4):
   if step>=2: current=expand(current,b'traffic upd',32)
   seq=1 if step==1 else 0; rec=record(current,seq,data+b'\x17'+bytes(step*3)); result+=q(len(rec))+rec
 elif operation==5:
  current=secret; result=b''
  for step in range(4):
   if step==2: current=expand(current,b'traffic upd',32)
   seq=2**24-2+step if step<2 else step-2
   payload=b'\x18\x00\x00\x01\x00' if step==1 else data
   kind_value=22 if step==1 else 23; pad=3 if step==2 else 0
   rec=record(current,seq,payload+bytes([kind_value])+bytes(pad)); result+=q(len(rec))+rec
 else: raise AssertionError(operation)
 native+=q(operation,layout,kind,padding,sequence,variant,len(packet),capacity)+secret+packet
 if operation in (2,5): expected+=result
 else: expected+=q(status,after,int(exhausted),int(poisoned),result_kind,len(result),len(observed))+result+observed
assert at==len(source)
sys.stdout.buffer.write(q(len(native))+native+expected)
"#;
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdout={} prefix={:?}, stderr={:?}",
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(40)],
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let next = at.checked_add(8).unwrap();
    let word = u64::from_le_bytes(
        bytes
            .get(*at..next)
            .expect("complete u64 response")
            .try_into()
            .unwrap(),
    );
    *at = next;
    word
}
fn peer(cases: &[Case]) -> (Vec<u8>, Vec<u8>) {
    let file = common::TempArtifact::new("laniusc_tls_record_aes", "peer_input", None);
    file.write_bytes(input(cases));
    let output = common::process_output_with_timeout(
        "Python hashlib/hmac/OpenSSL TLS record peer",
        Command::new("python3")
            .args(["-c", PEER])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(15),
    );
    checked(&output);
    let mut at = 0;
    let length = word(&output.stdout, &mut at) as usize;
    let native = output.stdout[at..at + length].to_vec();
    let expected = output.stdout[at + length..].to_vec();
    (native, expected)
}
fn compare(cases: Vec<Case>) {
    let (bytes, expected) = peer(&cases);
    let file = common::TempArtifact::new("laniusc_tls_record_aes", "native_input", None);
    file.write_bytes(bytes);
    let trace = common::TempArtifact::new("laniusc_tls_record_aes", "memory", None);
    let native = common::process_output_with_timeout(
        "native TLS record protocol",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(protocol().path())
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "record operations allocate no memory"
    );
    let mut actual_at = 0;
    let mut expected_at = 0;
    for (index, case) in cases.iter().enumerate() {
        let a = word(&native.stdout, &mut actual_at) as i64;
        let b = word(&native.stdout, &mut actual_at) as i64;
        if case.layout == 0 {
            assert!(a < 0 && b < 0, "case {index}: native strided arrays");
        } else {
            assert_eq!((a, b), (1, 1), "case {index}: packed bytes");
        }
        if case.operation == 2 || case.operation == 5 {
            for step in 0..4 {
                let n = word(&native.stdout, &mut actual_at) as usize;
                let m = word(&expected, &mut expected_at) as usize;
                assert_eq!(n, m);
                assert_eq!(
                    &native.stdout[actual_at..actual_at + n],
                    &expected[expected_at..expected_at + m],
                    "case {index}, step {step}: {case:?}"
                );
                actual_at += n;
                expected_at += m;
            }
            continue;
        }
        let actual: Vec<_> = (0..7)
            .map(|_| word(&native.stdout, &mut actual_at))
            .collect();
        let reference: Vec<_> = (0..7).map(|_| word(&expected, &mut expected_at)).collect();
        assert_eq!(actual, reference, "case {index}: {case:?}");
        let n = (actual[5] + actual[6]) as usize;
        assert_eq!(
            &native.stdout[actual_at..actual_at + n],
            &expected[expected_at..expected_at + n],
            "case {index}, emitted/authenticated bytes: {case:?}"
        );
        actual_at += n;
        expected_at += n;
    }
    assert_eq!(actual_at, native.stdout.len(), "no trailing native output");
    assert_eq!(expected_at, expected.len(), "no trailing peer output");
    eprintln!("AES TLS record protocol commands={}", cases.len());
}
#[test]
fn ordinary_aes_record_consumer_owns_secret_and_updates_cached_key() {
    let mut first = case(0, 5);
    first.secret = [0; 32];
    first.data = b"hello".to_vec();
    first.padding = 7;
    let (_, reference) = peer(&[first]);
    let mut at = 0;
    for _ in 0..5 {
        word(&reference, &mut at);
    }
    let length = word(&reference, &mut at) as usize;
    word(&reference, &mut at);
    let mut expected = reference[at..at + length].to_vec();
    // Derive the updated secret independently, then use the AEAD peer with
    // that secret to produce the generation1/sequence0 empty record.
    let secret = common::process_output_with_timeout("independent traffic update", Command::new("python3").args(["-c", "import hashlib,hmac,sys; label=b'tls13 traffic upd'; info=b'\\x00\\x20'+bytes([len(label)])+label+b'\\0'; sys.stdout.buffer.write(hmac.new(bytes(32),info+b'\\1',hashlib.sha256).digest())"]), Duration::from_secs(5));
    checked(&secret);
    assert_eq!(secret.stdout.len(), 32);
    let mut second = case(0, 0);
    second.secret.copy_from_slice(&secret.stdout);
    let (_, reference) = peer(&[second]);
    let mut at = 0;
    for _ in 0..5 {
        word(&reference, &mut at);
    }
    let n = word(&reference, &mut at) as usize;
    word(&reference, &mut at);
    expected.extend(&reference[at..at + n]);
    let exe = compile("plain");
    let trace = common::TempArtifact::new("laniusc_tls_record_aes", "plain_memory", None);
    let output = common::process_output_with_timeout(
        "ordinary TLS record consumer",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert_eq!(output.stdout, expected);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn aes_tls13_records_match_openssl_over_types_sizes_padding_and_strides() {
    let mut cases = Vec::new();
    for length in [0, 1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 1024] {
        for operation in [0, 1] {
            let mut value = case(operation, length);
            value.padding = if length % 2 == 0 { 0 } else { 7 };
            value.sequence = if length % 2 == 0 { 0x00010203 } else { 0 };
            value.capacity = length + 32;
            layouts(value, &mut cases);
        }
    }
    for (length, padding) in [(16384, 0), (16383, 1), (1, 16383)] {
        for operation in [0, 1] {
            let mut value = case(operation, length);
            value.padding = padding;
            value.capacity = 16650;
            layouts(value, &mut cases);
        }
    }
    for (kind, length) in [(21, 2), (22, 1), (22, 64)] {
        for operation in [0, 1] {
            let mut value = case(operation, length);
            value.kind = kind;
            value.padding = 3;
            value.capacity = length + 32;
            layouts(value, &mut cases);
        }
    }
    for length in [0, 17, 1024] {
        let mut value = case(2, length);
        value.capacity = 16650;
        layouts(value, &mut cases);
    }
    assert_eq!(cases.len(), 86);
    compare(cases);
}
#[test]
fn aes_record_limits_reserve_old_keyupdate_slot_and_reset_only_with_new_key() {
    let mut cases = Vec::new();
    for sequence in [
        255,
        256,
        (1 << 24) - 2,
        (1 << 24) - 1,
        1 << 24,
        (1 << 24) + 1,
        u64::MAX,
    ] {
        for operation in [0, 1] {
            let mut value = case(operation, 7);
            value.sequence = sequence;
            value.capacity = 100;
            layouts(value, &mut cases);
        }
    }
    for length in [0, 17] {
        let mut value = case(5, length);
        value.capacity = 16650;
        layouts(value, &mut cases);
    }
    assert_eq!(cases.len(), 32);
    compare(cases);
}
#[test]
fn aes_record_failures_poison_without_publishing_and_retry_metadata_atomically() {
    let mut cases = vec![];
    for variant in [1, 2, 5, 6, 4] {
        let mut value = case(0, 5);
        value.variant = variant;
        layouts(value, &mut cases);
    }
    for kind in [0, 20, 24, 255] {
        let mut value = case(0, 0);
        value.kind = kind;
        layouts(value, &mut cases);
    }
    for (kind, length) in [(21, 0), (21, 1), (21, 3), (22, 0), (23, 16385)] {
        let mut value = case(0, length);
        value.kind = kind;
        layouts(value, &mut cases);
    }
    for (length, padding) in [
        (0, -1),
        (0, 16385),
        (5, 16380),
        (16384, 1),
        (1, i32::MAX as i64),
    ] {
        let mut value = case(0, length);
        value.padding = padding;
        layouts(value, &mut cases);
    }
    for capacity in [0, 21, 26] {
        let mut value = case(0, 5);
        value.capacity = capacity;
        layouts(value, &mut cases);
    }
    for variant in 1..=21 {
        let mut value = case(1, 7);
        value.variant = variant;
        value.capacity = if variant == 16 { 16390 } else { 64 };
        layouts(value, &mut cases);
    }
    for variant in [30, 31, 32] {
        let mut value = case(1, 5);
        value.variant = variant;
        layouts(value, &mut cases);
    }
    for capacity in [0, 1, 5] {
        let mut value = case(1, 5);
        value.capacity = capacity;
        layouts(value, &mut cases);
    }
    for operation in [3, 4] {
        let mut value = case(operation, 5);
        value.capacity = 100;
        layouts(value, &mut cases);
    }
    assert_eq!(cases.len(), 102);
    compare(cases);
}
