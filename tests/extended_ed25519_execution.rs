//! Pure Ed25519: RFC8032, libsodium, and independent bigint projective-group policy oracle.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/ed25519").join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("Ed25519 {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_ed25519", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol.lani"))
}
fn success(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn words(bytes: &[u8]) -> Vec<u64> {
    assert_eq!(bytes.len() % 8, 0);
    bytes
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_ed25519", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_ed25519", "memory", None);
    let output = common::process_output_with_timeout(
        "allocation-free Ed25519 native batch",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(45),
    );
    success(&output);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "Ed25519 allocated"
    );
    words(&output.stdout)
}
fn unhex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|v| u8::from_str_radix(std::str::from_utf8(v).unwrap(), 16).unwrap())
        .collect()
}
#[derive(Clone, Debug)]
struct Case {
    operation: u64,
    layout: u64,
    mode: u64,
    seed: [u8; 32],
    public: [u8; 32],
    signature: [u8; 64],
    message: Vec<u8>,
    known: Option<Vec<u64>>,
}
fn case(operation: u64, seed: [u8; 32], message: Vec<u8>) -> Case {
    Case {
        operation,
        layout: 0,
        mode: 0,
        seed,
        public: [0; 32],
        signature: [0; 64],
        message,
        known: None,
    }
}
fn layouts(cases: &mut Vec<Case>, value: Case) {
    for layout in [0, 1] {
        let mut item = value.clone();
        item.layout = layout;
        cases.push(item);
    }
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        for word in [c.operation, c.layout, c.mode, c.message.len() as u64] {
            bytes.extend(word.to_le_bytes());
        }
        bytes.extend(c.seed);
        bytes.extend(c.public);
        bytes.extend(c.signature);
        bytes.extend(&c.message);
    }
    bytes
}
const ORACLE: &str = r#"
import ctypes,hashlib,struct,sys
lib=ctypes.CDLL('libsodium.so.23');lib.sodium_init.restype=ctypes.c_int;assert lib.sodium_init()>=0
kp=lib.crypto_sign_seed_keypair;kp.argtypes=[ctypes.c_void_p]*3;kp.restype=ctypes.c_int
sign=lib.crypto_sign_detached;sign.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_ulonglong,ctypes.c_void_p];sign.restype=ctypes.c_int
verify=lib.crypto_sign_verify_detached;verify.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_ulonglong,ctypes.c_void_p];verify.restype=ctypes.c_int
p=2**255-19;L=2**252+27742317777372353535851937790883648493;d=-121665*pow(121666,p-2,p)%p
I=pow(2,(p-1)//4,p);O=(0,1,1)
B=(15112221349535400772501151409588531511454012693041857206046113283949847762202,46316835694926478169428394003475163141307993866256225615783033603165251855960,1)
# Independent homogeneous projective addition (three coordinates), rather than
# production's extended four-coordinate formulas and specialized doubling.
def add(P,Q):
 x,y,z=P;u,v,w=Q;a=z*w%p;b=a*a%p;c=x*u%p;e=y*v%p;f=d*c*e%p;g=(b-f)%p;h=(b+f)%p
 return (a*g*((x+y)*(u+v)-c-e)%p,a*h*(e+c)%p,g*h%p)
def mul(P,n):
 out=O
 while n:
  if n&1:out=add(out,P)
  P=add(P,P);n>>=1
 return out
def equal(P,Q):return (P[0]*Q[2]-Q[0]*P[2])%p==0 and (P[1]*Q[2]-Q[1]*P[2])%p==0
def enc(P):
 x,y,z=P;q=pow(z,p-2,p);x=x*q%p;y=y*q%p;return (y|((x&1)<<255)).to_bytes(32,'little')
def dec(data):
 n=int.from_bytes(data,'little');sgn=n>>255;y=n%2**255
 if y>=p:return None
 y2=y*y%p;z=(y2-1)*pow(d*y2+1,p-2,p)%p;x=pow(z,(p+3)//8,p)
 if x*x%p!=z:x=x*I%p
 if x*x%p!=z or (x==0 and sgn):return None
 if x&1!=sgn:x=p-x
 return (x,y,1)
def strict(pk,m,sig):
 s=int.from_bytes(sig[32:],'little')
 if s>=L:return False
 A=dec(pk);R=dec(sig[:32])
 if A is None or R is None or equal(A,O):return False
 if not equal(mul(A,L),O) or not equal(mul(R,L),O):return False
 k=int.from_bytes(hashlib.sha512(sig[:32]+pk+m).digest(),'little')%L
 return equal(mul(B,s),add(R,mul(A,k)))
def keys(seed):
 pk=ctypes.create_string_buffer(32);sk=ctypes.create_string_buffer(64);assert kp(pk,sk,ctypes.create_string_buffer(seed))==0
 h=bytearray(hashlib.sha512(seed).digest());h[0]&=248;h[31]=(h[31]&63)|64;a=int.from_bytes(h[:32],'little')
 assert pk.raw==enc(mul(B,a));return pk.raw,sk.raw,a,bytes(h[32:])
def signed(seed,m):
 pk,sk,a,prefix=keys(seed);out=ctypes.create_string_buffer(64);size=ctypes.c_ulonglong()
 assert sign(out,ctypes.byref(size),ctypes.create_string_buffer(m),len(m),ctypes.create_string_buffer(sk))==0 and size.value==64
 r=int.from_bytes(hashlib.sha512(prefix+m).digest(),'little')%L;R=enc(mul(B,r));k=int.from_bytes(hashlib.sha512(R+pk+m).digest(),'little')%L
 assert out.raw==R+((r+k*a)%L).to_bytes(32,'little');assert strict(pk,m,out.raw)
 assert verify(ctypes.create_string_buffer(out.raw),ctypes.create_string_buffer(m),len(m),ctypes.create_string_buffer(pk))==0
 return pk,out.raw
def word(n):sys.stdout.buffer.write(struct.pack('<Q',n))
def value(data):
 for b in data:word(b)
def record(pk,m,sig,layout=0):return struct.pack('<QQQQ',2,layout,0,len(m))+bytes(32)+pk+sig+m
def generate():
 seed=bytes(range(32));m=bytes(range(64));pk,sig=signed(seed,m);cases=[]
 def emit(A,R,S=sig[32:],message=m):
  for layout in (0,1):cases.append(record(A,message,R+S,layout))
 emit(pk,sig[:32])
 # Valid independently generated keys/signatures across SHA-512 boundaries.
 for n in (0,1,31,32,63,64,65,111,112,127,128,129,255,256,1023,2048):
  ss=hashlib.sha512(b'Ed25519 test seed'+n.to_bytes(4,'little')).digest()[:32]
  mm=bytes((j*29+n)%256 for j in range(n));pp,gg=signed(ss,mm)
  emit(pp,gg[:32],gg[32:],mm)
 # Canonical y boundaries and the sign bit, in either encoded point.
 for y in (p,p+1,2**255-1):
  for signbit in (0,1):
   bad=(y|(signbit<<255)).to_bytes(32,'little');emit(bad,sig[:32]);emit(pk,bad)
 for y in (1,p-1):
  bad=(y|(1<<255)).to_bytes(32,'little');emit(bad,sig[:32]);emit(pk,bad)
 for y in range(32):
  bad=y.to_bytes(32,'little')
  if dec(bad) is None:emit(bad,sig[:32]);emit(pk,bad)
 # Find a full order-eight torsion point without relying on a hardcoded list.
 T=None
 for y in range(2,128):
  P=dec(y.to_bytes(32,'little'))
  if P is not None:
   t=mul(P,L)
   if equal(mul(t,8),O) and not equal(mul(t,4),O):T=t;break
 assert T is not None
 R=dec(sig[:32]);A=dec(pk)
 for n in range(8):
  t=mul(T,n);emit(enc(t),sig[:32]);emit(pk,enc(t));emit(enc(add(A,t)),sig[:32]);emit(pk,enc(add(R,t)))
 # Scalar boundary/malleability and all high scalar byte bits.
 s=int.from_bytes(sig[32:],'little')
 for n in (0,L-1,L,L+1,s+L,2**253-1,2**255,2**256-1):emit(pk,sig[:32],n.to_bytes(32,'little'))
 # A known secret scalar a=1, canonical identity R: exact valid equation,
 # deliberately accepted here despite libsodium's small-order-R rejection.
 a_pk=enc(B);zero_nonce=enc(O);k=int.from_bytes(hashlib.sha512(zero_nonce+a_pk+m).digest(),'little')%L
 identity_signature=zero_nonce+k.to_bytes(32,'little');assert strict(a_pk,m,identity_signature)
 assert verify(ctypes.create_string_buffer(identity_signature),ctypes.create_string_buffer(m),len(m),ctypes.create_string_buffer(a_pk))!=0
 emit(a_pk,zero_nonce,k.to_bytes(32,'little'));emit(a_pk,zero_nonce,((k+1)%L).to_bytes(32,'little'));emit(a_pk,zero_nonce,(k+L).to_bytes(32,'little'))
 emit(a_pk,zero_nonce,k.to_bytes(32,'little'),bytes([m[0]^1])+m[1:])
 # Identity key has an exact equation for R=B,S=1, but is rejected as weak.
 emit(enc(O),enc(B),(1).to_bytes(32,'little'))
 # Mixed-order A and R with a valid exact (and thus cofactored) equation;
 # subgroup admission must reject them independently of equation success.
 mixed_a=enc(add(B,T));mixed_r=enc(add(B,T))
 for nonce in range(256):
  mm=b'mixed-order'+bytes([nonce]);h=int.from_bytes(hashlib.sha512(mixed_r+mixed_a+mm).digest(),'little')%L
  if (h+1)%8==0:
   forged=mixed_r+((h+1)%L).to_bytes(32,'little');assert equal(mul(B,(h+1)%L),add(dec(mixed_r),mul(dec(mixed_a),h)))
   assert not strict(mixed_a,mm,forged);emit(mixed_a,mixed_r,forged[32:],mm);break
 else:raise AssertionError('mixed-order search')
 sys.stdout.buffer.write(struct.pack('<Q',len(cases))+b''.join(cases))
if len(sys.argv)>1:generate();sys.exit(0)
data=sys.stdin.buffer;count=struct.unpack('<Q',data.read(8))[0]
for _ in range(count):
 op,layout,mode,n=struct.unpack('<QQQQ',data.read(32));seed=data.read(32);pk=data.read(32);sig=data.read(64);m=data.read(n)
 if op==0:word(0);value(keys(seed)[0])
 elif op==1:word(0);value(signed(seed,m)[1])
 elif op==2:
  expected=strict(pk,m,sig);status=verify(ctypes.create_string_buffer(sig),ctypes.create_string_buffer(m),len(m),ctypes.create_string_buffer(pk))
  if expected and sig[:32]!=enc(O):assert status==0
  word(0);word(int(expected))
 elif op==3:
  codes=[1,1,1,2,2,1,1,2,3,4,1,3,1,1,1,1,0,0,2,3,4,1,2];word(codes[mode])
  if mode==16:value(signed(seed,b'')[1])
  if mode==17:word(int(strict(pk,b'',sig)))
 else:
  pk1,sig1=signed(seed,m);changed=bytearray(seed);changed[12]^=1;mm=bytes([m[0]^128])+m[1:] if m else m;pk2,sig2=signed(bytes(changed),mm)
  word(0);value(pk1);value(bytes([pk1[0]^255])+pk1[1:]);value(pk2);value(sig1);value(sig1[:63]+bytes([sig1[63]^128]));value(sig2)
assert data.read()==b''
"#;
fn python(input: Option<&[u8]>, generate: bool) -> Vec<u8> {
    let source = common::TempArtifact::new("laniusc_ed25519", "oracle_input", None);
    source.write_bytes(input.unwrap_or(&[]));
    let mut command = Command::new("python3");
    command.args(["-c", ORACLE]);
    if generate {
        command.arg("generate");
    }
    command.stdin(std::fs::File::open(source.path()).unwrap());
    let output = common::process_output_with_timeout(
        "independent Ed25519 libsodium/bigint oracle",
        &mut command,
        Duration::from_secs(35),
    );
    success(&output);
    output.stdout
}
fn compare(cases: &[Case]) {
    // One reusable ELF; bounded batches keep individual native processes below
    // the admission limit and report the exact failing record and operation.
    for batch in cases.chunks(24) {
        let bytes = input(batch);
        let expected = words(&python(Some(&bytes), false));
        let actual = execute(protocol(), &bytes);
        let mut at = 0;
        for c in batch {
            let code = expected[at];
            let size = if code != 0 {
                1
            } else {
                match c.operation {
                    0 => 33,
                    1 => 65,
                    2 => 2,
                    4 => 289,
                    3 => {
                        if c.mode == 16 {
                            65
                        } else {
                            2
                        }
                    }
                    _ => unreachable!(),
                }
            };
            assert!(at + size <= actual.len(), "short native output at {c:?}");
            assert_eq!(&actual[at..at + size], &expected[at..at + size], "{c:?}");
            if let Some(known) = &c.known {
                assert_eq!(&actual[at..at + size], known, "fixed RFC {c:?}");
            }
            at += size;
        }
        assert_eq!(at, actual.len());
        assert_eq!(at, expected.len());
    }
}
fn official() -> Vec<Case> {
    let mut cases = Vec::new();
    for line in include_str!("fixtures/extended/ed25519/rfc8032.tsv")
        .lines()
        .filter(|l| !l.starts_with('#'))
    {
        let f: Vec<_> = line.split('\t').collect();
        assert_eq!(f.len(), 5);
        let seed = unhex(f[1]).try_into().unwrap();
        let public: [u8; 32] = unhex(f[2]).try_into().unwrap();
        let message = unhex(f[3]);
        let signature: [u8; 64] = unhex(f[4]).try_into().unwrap();
        for operation in 0..3 {
            let mut c = case(operation, seed, message.clone());
            c.public = public;
            c.signature = signature;
            c.known = Some(match operation {
                0 => std::iter::once(0).chain(public.map(u64::from)).collect(),
                1 => std::iter::once(0).chain(signature.map(u64::from)).collect(),
                _ => vec![0, 1],
            });
            layouts(&mut cases, c);
        }
    }
    assert_eq!(cases.len(), 30);
    cases
}
#[test]
fn rfc8032_all_pure_vectors_key_sign_verify_both_layouts() {
    compare(&official());
}
#[test]
fn deterministic_libsodium_messages_padding_layouts_and_independent_copies() {
    let mut cases = Vec::new();
    let mut state = 0x8032_2551_9abc_def0u64;
    for length in [
        0, 1, 2, 31, 32, 63, 64, 65, 111, 112, 127, 128, 129, 255, 256, 1023, 2048,
    ] {
        let mut next = || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state as u8
        };
        let seed = std::array::from_fn(|_| next());
        let message = (0..length).map(|_| next()).collect::<Vec<_>>();
        for operation in [0, 1] {
            layouts(&mut cases, case(operation, seed, message.clone()));
        }
    }
    for length in [0, 1, 129] {
        layouts(&mut cases, case(4, [length as u8; 32], vec![73; length]));
    }
    compare(&cases);
}
#[test]
fn canonical_subgroups_identity_nonce_and_scalar_malleability() {
    let bytes = python(None, true);
    let mut at = 8;
    let count = u64::from_le_bytes(bytes[..8].try_into().unwrap()) as usize;
    let mut cases = Vec::new();
    for _ in 0..count {
        let controls = words(&bytes[at..at + 32]);
        at += 32;
        let seed = bytes[at..at + 32].try_into().unwrap();
        at += 32;
        let public = bytes[at..at + 32].try_into().unwrap();
        at += 32;
        let signature = bytes[at..at + 64].try_into().unwrap();
        at += 64;
        let n = controls[3] as usize;
        let message = bytes[at..at + n].to_vec();
        at += n;
        cases.push(Case {
            operation: controls[0],
            layout: controls[1],
            mode: controls[2],
            seed,
            public,
            signature,
            message,
            known: None,
        });
    }
    assert_eq!(at, bytes.len());
    assert!(cases.len() > 150);
    compare(&cases);
}
#[test]
fn every_signed_component_byte_mutation_and_bounds_precedence() {
    let original = official()
        .into_iter()
        .find(|c| c.operation == 2 && c.message.len() == 64)
        .unwrap();
    let mut cases = Vec::new();
    for field in 0..3 {
        let length = if field == 0 { 32 } else { 64 };
        for i in 0..length {
            let mut c = original.clone();
            c.known = Some(vec![0, 0]);
            c.layout = (i % 2) as u64;
            match field {
                0 => c.public[i] ^= 1,
                1 => c.signature[i] ^= 1,
                _ => c.message[i] ^= 1,
            }
            cases.push(c);
        }
    }
    for mode in 0..=22 {
        let mut c = original.clone();
        c.operation = 3;
        c.mode = mode;
        c.known = None;
        layouts(&mut cases, c);
    }
    compare(&cases);
}
#[test]
fn ordinary_consumer_without_error_variant_projection() {
    let file = compile("consumer.lani");
    assert!(execute(&file, &[]).is_empty());
}
