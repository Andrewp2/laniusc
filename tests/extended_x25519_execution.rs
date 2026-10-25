//! RFC7748 and independent libsodium/Python-field models for real Lanius X25519.
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
    let entry = root.join("tests/fixtures/extended/x25519").join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("X25519 {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_x25519", name, None);
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
fn execute(file: &common::TempArtifact, input: &[u8], seconds: u64) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_x25519", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_x25519", "memory", None);
    let output = common::process_output_with_timeout(
        "X25519 allocation-free native gate",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(seconds),
    );
    success(&output);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "X25519 allocates nothing"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect()
}
fn hex(value: &str) -> [u8; 32] {
    assert_eq!(value.len(), 64);
    let mut result = [0; 32];
    for (at, digits) in value.as_bytes().chunks_exact(2).enumerate() {
        result[at] = u8::from_str_radix(std::str::from_utf8(digits).unwrap(), 16).unwrap();
    }
    result
}
fn alice() -> [u8; 32] {
    hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
}
fn bob() -> [u8; 32] {
    hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
}
fn basepoint() -> [u8; 32] {
    let mut bytes = [0; 32];
    bytes[0] = 9;
    bytes
}
#[derive(Clone, Debug)]
struct Case {
    operation: u64,
    layout: u64,
    mode: u64,
    repeat: u64,
    scalar: [u8; 32],
    point: [u8; 32],
    known: Option<[u8; 32]>,
}
fn case(operation: u64, scalar: [u8; 32], point: [u8; 32]) -> Case {
    Case {
        operation,
        layout: 0,
        mode: 0,
        repeat: 0,
        scalar,
        point,
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
    let mut result = (cases.len() as u64).to_le_bytes().to_vec();
    for case in cases {
        for value in [case.operation, case.layout, case.mode, case.repeat] {
            result.extend(value.to_le_bytes());
        }
        result.extend(case.scalar);
        result.extend(case.point);
    }
    result
}
const ORACLE: &str = r#"
import ctypes,struct,sys
lib=ctypes.CDLL('libsodium.so.23'); lib.sodium_init.restype=ctypes.c_int
assert lib.sodium_init()>=0
shared=lib.crypto_scalarmult_curve25519; base=lib.crypto_scalarmult_curve25519_base
shared.argtypes=[ctypes.c_void_p]*3; shared.restype=ctypes.c_int
base.argtypes=[ctypes.c_void_p]*2; base.restype=ctypes.c_int
p=2**255-19
def sodium(k,u=None):
 out=ctypes.create_string_buffer(32); kb=ctypes.create_string_buffer(k)
 if u is None: status=base(out,kb)
 else: status=shared(out,kb,ctypes.create_string_buffer(u))
 return status,out.raw
def field_model(k,u):
 k=bytearray(k); k[0]&=248; k[31]=(k[31]&127)|64; k=int.from_bytes(k,'little')
 x1=(int.from_bytes(u,'little')&((1<<255)-1))%p
 x2,z2,x3,z3,swap=1,0,x1,1,0
 for bit in range(254,-1,-1):
  current=(k>>bit)&1; swap^=current
  if swap: x2,x3=x3,x2; z2,z3=z3,z2
  swap=current
  a=(x2+z2)%p; aa=a*a%p; b=(x2-z2)%p; bb=b*b%p; e=(aa-bb)%p
  c=(x3+z3)%p; d=(x3-z3)%p; da=d*a%p; cb=c*b%p
  x3=(da+cb)**2%p; z3=x1*(da-cb)**2%p; x2=aa*bb%p; z2=e*(aa+121665*e)%p
 if swap: x2,x3=x3,x2; z2,z3=z3,z2
 return (x2*pow(z2,p-2,p)%p).to_bytes(32,'little')
def public(k):
 status,out=sodium(k); assert status==0
 assert out==field_model(k,b'\x09'+bytes(31)); return out
def agreement(k,u):
 expected=field_model(k,u); status,out=sodium(k,u)
 if expected==bytes(32):
  assert status!=0 # Sodium error output is unspecified and is never compared.
  return 4,None
 canonical=((int.from_bytes(u,'little')&((1<<255)-1))%p).to_bytes(32,'little')
 canonical_status,canonical_out=sodium(k,canonical)
 assert canonical_status==0 and canonical_out==expected
 if status==0: assert out==expected
 else: assert u!=canonical # A stricter library decoder cannot define RFC input policy.
 return 0,expected
def word(n): sys.stdout.buffer.write(struct.pack('<Q',n))
def key(value):
 assert len(value)==32
 for byte in value: word(byte)
data=sys.stdin.buffer; count=struct.unpack('<Q',data.read(8))[0]
for _ in range(count):
 op,layout,mode,repeat=struct.unpack('<QQQQ',data.read(32)); k=data.read(32); u=data.read(32)
 if op==0: word(0); key(public(k))
 elif op==1:
  code,out=agreement(k,u); word(code)
  if code==0: key(out)
 elif op==2: word([1,1,1,2,2,3,3,1,2,1,1,2,1,2,3,2][mode])
 elif op==3:
  original=public(k); mutated=bytes([original[0]^255])+original[1:]
  changed=bytearray(k); changed[12]^=1
  word(0); key(original); key(mutated); key(public(bytes(changed)))
 else:
  for i in range(repeat):
   status,out=sodium(k,u); assert status==0; k,u=out,k
  word(0); key(k)
"#;
fn expected(cases: &[Case]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_x25519", "oracle_input", None);
    source.write_bytes(input(cases));
    let output = common::process_output_with_timeout(
        "independent libsodium and Python prime-field X25519 oracles",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(20),
    );
    success(&output);
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect()
}
fn compare(cases: &[Case], seconds: u64) {
    let expected = expected(cases);
    let actual = execute(protocol(), &input(cases), seconds);
    let mut at = 0;
    for case in cases {
        let code = expected[at];
        let length = if code != 0 {
            1
        } else if case.operation == 3 {
            97
        } else {
            33
        };
        assert_eq!(
            actual.get(at..at + length),
            Some(&expected[at..at + length]),
            "X25519 case {case:?}"
        );
        if let Some(known) = case.known {
            assert_eq!(code, 0);
            assert_eq!(
                &expected[at + 1..at + 33],
                known.map(u64::from).as_slice(),
                "RFC oracle anchor {case:?}"
            );
        }
        at += length;
    }
    assert_eq!(actual.len(), at);
    assert_eq!(expected.len(), at);
}
#[test]
fn ordinary_x25519_alice_bob_consumers_execute_without_error_projection() {
    let output = execute(&compile("plain.lani"), b"", 10);
    assert!(output.is_empty());
}
#[test]
fn x25519_rfc_vectors_encoding_policies_layouts_and_errors_match_independent_oracles() {
    let mut cases = Vec::new();
    for (scalar, point, output) in [
        (
            "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
            "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
            "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
        ),
        (
            "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
            "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
            "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
        ),
    ] {
        let mut value = case(1, hex(scalar), hex(point));
        value.known = Some(hex(output));
        layouts(&mut cases, value);
    }
    let ap = hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
    let bp = hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
    for (scalar, point, operation, known) in [
        (alice(), basepoint(), 0, ap),
        (bob(), basepoint(), 0, bp),
        (
            alice(),
            bp,
            1,
            hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"),
        ),
        (
            bob(),
            ap,
            1,
            hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"),
        ),
    ] {
        let mut value = case(operation, scalar, point);
        value.known = Some(known);
        layouts(&mut cases, value);
    }
    for low in 0..8 {
        for high in [0, 64, 128, 192] {
            let mut scalar = alice();
            scalar[0] = (scalar[0] & 248) | low;
            scalar[31] ^= high;
            layouts(&mut cases, case(0, scalar, basepoint()));
        }
    }
    for low in 0..19 {
        let mut point = [255; 32];
        point[0] = 237 + low;
        point[31] = 127;
        for top in [0, 128] {
            let mut u = point;
            u[31] ^= top;
            layouts(&mut cases, case(1, alice(), u));
        }
    }
    for low in [0, 1] {
        let mut point = [0; 32];
        point[0] = low;
        layouts(&mut cases, case(1, bob(), point));
        point[31] |= 128;
        layouts(&mut cases, case(1, bob(), point));
    }
    let mut p_minus_one = [255; 32];
    p_minus_one[0] = 236;
    p_minus_one[31] = 127;
    layouts(&mut cases, case(1, alice(), p_minus_one));
    let mut seed = 0x7748_2551_9202_6102_u64;
    for _ in 0..16 {
        let mut scalar = [0; 32];
        let mut point = [0; 32];
        for byte in scalar.iter_mut().chain(point.iter_mut()) {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            *byte = seed as u8;
        }
        layouts(&mut cases, case(0, scalar, basepoint()));
        layouts(&mut cases, case(1, scalar, point));
        point[31] ^= 128;
        layouts(&mut cases, case(1, scalar, point));
    }
    for mode in 0..16 {
        let mut value = case(2, alice(), bp);
        value.mode = mode;
        layouts(&mut cases, value);
    }
    for scalar in [alice(), bob(), [0; 32], [255; 32]] {
        layouts(&mut cases, case(3, scalar, bp));
    }
    compare(&cases, 45);
    eprintln!(
        "{} X25519 model commands, packed/strided nonzero starts and unchanged guards",
        cases.len()
    );
}
#[test]
fn x25519_rfc_iteration_one_and_thousand_match_sodium() {
    let mut cases = Vec::new();
    for (repeat, known) in [
        (
            1,
            "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079",
        ),
        (
            1000,
            "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51",
        ),
    ] {
        let mut value = case(4, basepoint(), basepoint());
        value.layout = 1;
        value.repeat = repeat;
        value.known = Some(hex(known));
        cases.push(value);
    }
    compare(&cases, 45);
    eprintln!("RFC X25519 iteration1/1000: 1001 ladder invocations in one native process");
}
