//! Borrowed DER framing/value/writer contracts against independent Python integers.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/der")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("DER", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("DER {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_der", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn execute(file: &common::TempArtifact, input: &[u8]) -> Vec<u64> {
    let source = common::TempArtifact::new("laniusc_der", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_der", "trace", None);
    let output = common::process_output_with_timeout(
        "DER zero-allocation native execution",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(file.path())
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "DER must allocate nothing"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    output
        .stdout
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}
#[derive(Clone, Debug)]
struct Case {
    op: u64,
    layout: u64,
    mode: u64,
    a: u64,
    b: u64,
    c: u64,
    capacity: u64,
    input: Vec<u8>,
}
fn case(op: u64, mode: u64, input: Vec<u8>) -> Case {
    Case {
        op,
        mode,
        layout: 0,
        a: 0,
        b: 4,
        c: 0,
        capacity: 8208,
        input,
    }
}
fn layouts(cases: &mut Vec<Case>, value: Case) {
    for layout in [0, 1] {
        let mut value = value.clone();
        value.layout = layout;
        cases.push(value);
    }
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        for word in [
            c.op,
            c.layout,
            c.mode,
            c.a,
            c.b,
            c.c,
            c.capacity,
            c.input.len() as u64,
        ] {
            bytes.extend(word.to_le_bytes());
        }
        bytes.extend(&c.input);
    }
    bytes
}
// Host-only corpus construction; the independent oracle below uses big integers,
// decoded mathematical values and Python codecs rather than these encoders.
fn base128(mut value: u128) -> Vec<u8> {
    let mut out = vec![(value & 127) as u8];
    value >>= 7;
    while value != 0 {
        out.push((value as u8 & 127) | 128);
        value >>= 7;
    }
    out.reverse();
    out
}
fn tlv(class: u8, constructed: bool, number: u32, content: &[u8]) -> Vec<u8> {
    let mut out = vec![(class << 6) | (u8::from(constructed) << 5) | number.min(31) as u8];
    if number >= 31 {
        out.extend(base128(number as u128));
    }
    if content.len() < 128 {
        out.push(content.len() as u8);
    } else {
        let bytes = content.len().to_be_bytes();
        let first = bytes.iter().position(|b| *b != 0).unwrap();
        out.push(128 + (bytes.len() - first) as u8);
        out.extend(&bytes[first..]);
    }
    out.extend(content);
    out
}
fn integer(value: i128) -> Vec<u8> {
    let bytes = value.to_be_bytes();
    let mut at = 0;
    while at < 15
        && ((bytes[at] == 0 && bytes[at + 1] < 128) || (bytes[at] == 255 && bytes[at + 1] >= 128))
    {
        at += 1;
    }
    bytes[at..].to_vec()
}
fn hex(text: &str) -> Vec<u8> {
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
const ORACLE: &str = r#"
import datetime,re,struct,sys
MASK=(1<<64)-1
class Bad(Exception):
 def __init__(self,code,at=0): self.code,self.at=code,at
def fail(c,at=0): raise Bad(c,at)
def parse(data,start):
 n=len(data)
 if start==n: fail(2,start)
 first=data[start]; p=start+1; tag=first&31
 if tag==31:
  begin=p
  while True:
   if p==n: fail(2,p)
   octet=data[p]
   if p==begin and octet&127==0: fail(8,p)
   tag=(0 if p==begin else tag)*128+(octet&127)
   if tag>(1<<32)-1: fail(4,p)
   p+=1
   if octet<128: break
  if tag<31: fail(8,start)
 if first>>6==0 and tag==0: fail(3,start)
 if p==n: fail(2,p)
 lp=p; lead=data[p]; p+=1; length=lead
 if lead==128: fail(7,lp)
 if lead==255: fail(5,lp)
 if lead>128:
  width=lead&127
  if width>n-p: fail(2,n)
  if data[p]==0: fail(8,p)
  if width>4: fail(6,lp)
  length=int.from_bytes(data[p:p+width],'big'); p+=width
  if length<128: fail(8,lp)
  if length>(1<<31)-1: fail(6,lp)
 if length>n-p: fail(2,n)
 return (first>>6,bool(first&32),tag,start,p+length,p,data[p:p+length])
def exact(data):
 v=parse(data,0)
 if v[4]!=len(data): fail(9,v[4])
 return v
def fields(v): return [v[0],int(v[1]),v[2],v[3],v[4]-v[3],v[5],len(v[6]),*v[6]]
def children(data):
 out=[0,0]; p=0
 while p<len(data):
  before=p
  try: v=parse(data,p)
  except Bad as e: return out+[e.code,e.at,before,before]
  p=v[4]; out.extend([0,0,before,p]+fields(v))
 return out+[255,0,p,p]
def intbytes(value):
 width=max(1,(value.bit_length()+8)//8)
 b=value.to_bytes(width,'big',signed=True)
 while len(b)>1 and int.from_bytes(b[1:],'big',signed=True)==value: b=b[1:]
 return b
def validint(b):
 if not b: fail(11)
 value=int.from_bytes(b,'big',signed=True)
 if intbytes(value)!=b: fail(8)
 return value
def oid_groups(b):
 if not b: fail(11)
 initial=True
 for at,x in enumerate(b):
  if initial and x==128: fail(8,at)
  initial=x<128
 if not initial: fail(2,len(b))
def arcs(b):
 out=[]; p=0; first=True
 while p<len(b):
  before=p; v=0; limit=MASK+(80 if first else 0)
  while True:
   v=v*128+(b[p]&127)
   if v>limit: return out+[13,p,before,before]
   p+=1
   if b[p-1]<128: break
  if first:
   root=min(v//40,2); second=v-40*root
   out.extend([0,0,before,p,root,0,0,p,p,second]); first=False
  else: out.extend([0,0,before,p,v])
 return out+[255,0,p,p]
def typed(mode,v):
 cls,constructed,tag,_,_,_,b=v
 numbers=[1,2,2,2,3,4,5,6,12,19,22]
 if mode<=10 and (cls!=0 or constructed or tag!=numbers[mode]): fail(10)
 if mode==0:
  if len(b)!=1: fail(11)
  if b[0] not in [0,255]: fail(8)
  return [0,0,int(bool(b[0]))]
 if mode in [1,2,3]:
  value=validint(b)
  if mode==1: return [0,0,len(b),*b]
  if mode==2 and not -(1<<63)<=value<(1<<63): fail(12)
  if mode==3 and not 0<=value<=MASK: fail(12)
  return [0,0,value&MASK]
 if mode==4:
  if not b or b[0]>7 or (len(b)==1 and b[0]): fail(11)
  if len(b)>1 and b[-1]&((1<<b[0])-1): fail(8,len(b)-1)
  return [0,0,b[0],len(b)-1,*b[1:]]
 if mode==5: return [0,0,len(b),*b]
 if mode==6:
  if b: fail(11)
  return [0,0,0]
 if mode==7: oid_groups(b); return [0,0,len(b),*b]+arcs(b)
 if mode==8:
  try: b.decode('utf-8')
  except UnicodeDecodeError: fail(11)
  return [0,0,len(b),*b]
 if mode in [9,10]:
  allowed=b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '()+,-./:=?"
  for i,x in enumerate(b):
   if (mode==9 and x not in allowed) or (mode==10 and x>127): fail(11,i)
  return [0,0,len(b),*b]
 if mode==11:
  if cls!=0 or constructed or tag not in [23,24]: fail(10)
  width=2 if tag==23 else 4
  if not re.fullmatch(rb'[0-9]{'+str(width+10).encode()+rb'}Z',b): fail(11)
  year=int(b[:width]); year=year+(1900 if year>=50 else 2000) if width==2 else year
  parts=[year]+[int(b[i:i+2]) for i in range(width,width+10,2)]
  try: datetime.datetime(*parts)
  except ValueError: fail(11)
  return [0,0,*parts]
 if not constructed or (mode==13 and (cls!=0 or tag!=16)) or (mode==14 and (cls!=0 or tag!=17)): fail(10)
 return children(b)
def header(cls,constructed,tag,length):
 if cls==0 and tag==0: fail(3)
 if length<0: fail(1)
 ident=bytes([(cls<<6)|(bool(constructed)<<5)|min(tag,31)])
 if tag>=31:
  width=(tag.bit_length()+6)//7
  ident+=bytes(((tag>>(7*i))&127)|(128 if i else 0) for i in reversed(range(width)))
 if length<128: return ident+bytes([length])
 b=length.to_bytes((length.bit_length()+7)//8,'big'); return ident+bytes([128+len(b)])+b
data=sys.stdin.buffer.read(); at=0; count,=struct.unpack_from('<Q',data,at); at+=8
for _ in range(count):
 op,layout,mode,a,b,c,cap,n=struct.unpack_from('<8Q',data,at); at+=64; source=data[at:at+n]; at+=n; out=[]
 try:
  if op==0:
   try: out=[0,0]+fields(exact(source))
   except Bad as e: out=[e.code,e.at]
   out+=children(source)
  elif op==1: out=typed(mode,exact(source))
  else:
   if op==2:
    length=c&0xffffffff; length=length-(1<<32) if length&(1<<31) else length
    encoded=header(mode,a,b,length)
   elif op==3: encoded=header(mode,a,b,len(source))+source
   elif op==4: encoded=b'\x01\x01'+(b'\xff' if c else b'\x00')
   elif op==5: validint(source); encoded=b'\x02'+(bytes([len(source)]) if len(source)<128 else header(0,False,2,len(source))[1:])+source
   elif op==6: encoded=intbytes(c if c<(1<<63) else c-(1<<64)); encoded=header(0,False,2,len(encoded))+encoded
   elif op==7:
    encoded=c.to_bytes(max(1,(c.bit_length()+7)//8),'big')
    if encoded[0]&128: encoded=b'\0'+encoded
    encoded=header(0,False,2,len(encoded))+encoded
   if len(encoded)>cap: fail(14)
   out=[0,0,len(encoded),*encoded]
 except Bad as e: out=[e.code,e.at]
 sys.stdout.buffer.write(struct.pack('<Q',len(out))+struct.pack('<'+'Q'*len(out),*out))
assert at==len(data)
"#;
fn check(cases: &[Case]) {
    assert!(cases.len() <= 4096);
    let bytes = input(cases);
    let file = common::TempArtifact::new("laniusc_der", "oracle-input", None);
    file.write_bytes(&bytes);
    let output = common::process_output_with_timeout(
        "independent Python DER oracle",
        Command::new("python3")
            .args(["-c", ORACLE])
            .stdin(std::fs::File::open(file.path()).unwrap()),
        Duration::from_secs(10),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len() % 8, 0);
    let expected: Vec<u64> = output
        .stdout
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect();
    let actual = execute(protocol(), &bytes);
    let (mut p, mut q) = (0, 0);
    for (index, case) in cases.iter().enumerate() {
        let length = expected[p] as usize;
        p += 1;
        assert!(
            q + length <= actual.len(),
            "short native output case{index}: {case:?}"
        );
        assert_eq!(
            &actual[q..q + length],
            &expected[p..p + length],
            "DER case{index}: {case:?}"
        );
        p += length;
        q += length;
    }
    assert_eq!(p, expected.len());
    assert_eq!(q, actual.len());
    eprintln!("DER independent commands: {}", cases.len());
}
#[test]
fn ordinary_consumer_uses_der_without_error_layout_projection() {
    assert!(execute(&compile("plain"), &[]).is_empty());
}
#[test]
fn der_framing_values_writes_cursors_and_atomic_errors_match_independent_models() {
    let mut cases = Vec::new();
    for cls in 0..4 {
        for constructed in [false, true] {
            for tag in [0, 1, 16, 30, 31, 127, 128, 16383, 16384, u32::MAX] {
                layouts(
                    &mut cases,
                    case(0, 0, tlv(cls, constructed, tag, &[0, 255, 7])),
                );
            }
        }
    }
    for length in [0, 1, 126, 127, 128, 129, 255, 256, 4096, 8188] {
        let data: Vec<u8> = (0..length).map(|i| (i * 73 + 9) as u8).collect();
        let bytes = tlv(0, false, 4, &data);
        layouts(&mut cases, case(0, 0, bytes.clone()));
        layouts(&mut cases, case(1, 5, bytes));
        let mut writer = case(3, 0, data);
        writer.b = 4;
        for capacity in [0, length as u64 + 1, length as u64 + 5] {
            writer.capacity = capacity;
            layouts(&mut cases, writer.clone());
        }
    }
    let malformed: Vec<Vec<u8>> = vec![
        vec![],
        vec![0],
        vec![0, 0],
        vec![32, 0],
        vec![4],
        vec![4, 128],
        vec![4, 255],
        vec![4, 129],
        vec![4, 129, 0],
        vec![4, 129, 1, 0],
        vec![4, 130, 0, 128],
        vec![4, 132, 128, 0, 0, 0],
        vec![4, 133, 1, 0, 0, 0, 0],
        vec![31],
        vec![31, 0, 0],
        vec![31, 128, 31, 0],
        vec![31, 30, 0],
        vec![31, 144, 128, 128, 128, 0, 0],
        vec![31, 255, 255, 255, 255, 255, 127, 0],
        vec![4, 2, 1],
        vec![4, 0, 5, 0],
        vec![4, 0, 4, 2, 1],
    ];
    for bytes in malformed {
        layouts(&mut cases, case(0, 0, bytes));
    }
    let long = tlv(2, true, u32::MAX, &[1, 1, 255, 2, 1, 0]);
    for end in 0..long.len() {
        layouts(&mut cases, case(0, 0, long[..end].to_vec()));
    }
    for value in [
        i128::MIN,
        -(1i128 << 80),
        i64::MIN as i128,
        -32769,
        -32768,
        -129,
        -128,
        -1,
        0,
        1,
        127,
        128,
        255,
        256,
        32767,
        32768,
        i64::MAX as i128,
        (1i128 << 63),
        u64::MAX as i128,
        1i128 << 80,
        i128::MAX,
    ] {
        let body = integer(value);
        for mode in [1, 2, 3] {
            layouts(&mut cases, case(1, mode, tlv(0, false, 2, &body)));
        }
        for cap in [0, body.len() as u64 + 1, body.len() as u64 + 5] {
            let mut c = case(5, 0, body.clone());
            c.capacity = cap;
            layouts(&mut cases, c);
        }
    }
    for body in [
        vec![],
        vec![0, 0],
        vec![255, 255],
        vec![0, 127],
        vec![255, 128],
    ] {
        for mode in [1, 2, 3] {
            layouts(&mut cases, case(1, mode, tlv(0, false, 2, &body)));
        }
        layouts(&mut cases, case(5, 0, body));
    }
    for value in [
        0,
        1,
        127,
        128,
        255,
        256,
        u32::MAX as u64,
        i64::MAX as u64,
        1 << 63,
        (-129i64) as u64,
        (-128i64) as u64,
        (-32769i64) as u64,
        u64::MAX,
    ] {
        for op in [6, 7] {
            for cap in [0, 2, 3, 11, 20] {
                let mut c = case(op, 0, vec![]);
                c.c = value;
                c.capacity = cap;
                layouts(&mut cases, c);
            }
        }
    }
    for cls in 0..4 {
        for tag in [0, 30, 31, 128, u32::MAX as u64] {
            for length in [
                0,
                127,
                128,
                255,
                256,
                65535,
                65536,
                i32::MAX as u64,
                u64::MAX,
            ] {
                let mut c = case(2, cls, vec![]);
                c.a = 1;
                c.b = tag;
                c.c = length;
                c.capacity = 11;
                layouts(&mut cases, c);
            }
        }
    }
    for value in [0, 1] {
        for cap in [0, 2, 3, 8] {
            let mut c = case(4, 0, vec![]);
            c.c = value;
            c.capacity = cap;
            layouts(&mut cases, c);
        }
    }
    for body in [vec![], vec![0], vec![255], vec![1], vec![0, 0]] {
        layouts(&mut cases, case(1, 0, tlv(0, false, 1, &body)));
    }
    for unused in 0..=8 {
        for last in [0, 1, 128, 255] {
            layouts(&mut cases, case(1, 4, tlv(0, false, 3, &[unused, last])));
        }
        layouts(&mut cases, case(1, 4, tlv(0, false, 3, &[unused])));
    }
    layouts(&mut cases, case(1, 4, tlv(0, false, 3, &[])));
    for body in [vec![], vec![0]] {
        layouts(&mut cases, case(1, 6, tlv(0, false, 5, &body)));
    }
    for arcs in [
        vec![0u128, 0],
        vec![0, 39, 0],
        vec![1, 0],
        vec![1, 39, 127, 128],
        vec![2, 0],
        vec![2, 999, 3],
        vec![2, u64::MAX as u128],
        vec![2, u64::MAX as u128 + 1],
        vec![2, 1, u64::MAX as u128],
        vec![2, 1, u64::MAX as u128 + 1],
        vec![2, 1, 1u128 << 100],
    ] {
        let mut body = base128(arcs[0] * 40 + arcs[1]);
        for arc in &arcs[2..] {
            body.extend(base128(*arc));
        }
        layouts(&mut cases, case(1, 7, tlv(0, false, 6, &body)));
    }
    for body in [
        vec![],
        vec![128, 0],
        vec![42, 128, 0],
        vec![42, 129],
        vec![255; 20],
    ] {
        layouts(&mut cases, case(1, 7, tlv(0, false, 6, &body)));
    }
    for body in [
        b"".to_vec(),
        b"a\0b".to_vec(),
        "é🙂".as_bytes().to_vec(),
        vec![192, 128],
        vec![237, 160, 128],
        vec![244, 144, 128, 128],
        vec![240, 159, 153],
    ] {
        layouts(&mut cases, case(1, 8, tlv(0, false, 12, &body)));
    }
    for body in [
        b"AZaz09 '()+,-./:=?".to_vec(),
        b"@".to_vec(),
        b"_".to_vec(),
        b"\0".to_vec(),
        vec![128],
    ] {
        layouts(&mut cases, case(1, 9, tlv(0, false, 19, &body)));
    }
    for body in [vec![], (0..=127).collect(), vec![128], vec![255]] {
        layouts(&mut cases, case(1, 10, tlv(0, false, 22, &body)));
    }
    for (tag, time) in [
        (23, "491231235959Z"),
        (23, "500101000000Z"),
        (23, "000229000000Z"),
        (23, "990229000000Z"),
        (23, "2610241234Z"),
        (23, "261024123456+0000"),
        (23, "261024240000Z"),
        (23, "261024123460Z"),
        (24, "20500101000000Z"),
        (24, "20000229000000Z"),
        (24, "19000229000000Z"),
        (24, "00000101000000Z"),
        (24, "99991231235959Z"),
        (24, "20261024123456.1Z"),
        (24, "20261301000000Z"),
        (24, "2026102412345AZ"),
    ] {
        layouts(&mut cases, case(1, 11, tlv(0, false, tag, time.as_bytes())));
    }
    let sequence = [tlv(0, false, 2, &[7]), tlv(0, false, 1, &[255])].concat();
    for (cls, constructed, tag, body) in [
        (0, true, 16, sequence.clone()),
        (0, true, 17, sequence.clone()),
        (2, true, 3, sequence),
        (0, true, 16, vec![2, 2, 7]),
        (0, true, 17, vec![2, 1, 2, 2, 1, 1]),
        (0, false, 16, vec![]),
    ] {
        for mode in [12, 13, 14] {
            layouts(&mut cases, case(1, mode, tlv(cls, constructed, tag, &body)));
        }
    }
    for mode in 0..=14 {
        layouts(&mut cases, case(1, mode, tlv(1, false, 4, &[])));
    }
    for number in 0u32..32 {
        let body: Vec<u8> = (0..(number % 11))
            .map(|v| (v * 17 + number) as u8)
            .collect();
        let canonical = tlv(2, number % 2 != 0, number * 127 + 31, &body);
        layouts(&mut cases, case(0, 0, canonical.clone()));
        let mut changed = canonical;
        changed.pop();
        layouts(&mut cases, case(0, 0, changed));
    }
    check(&cases);
}
#[test]
fn openssl_ed25519_certificate_der_anchors_use_real_borrowed_framing() {
    let key = common::TempArtifact::new("laniusc_der", "ed25519-key", None);
    // RFC8032 test1 is public test material. The certificate itself is always
    // produced and signed by OpenSSL, with a real explicit-version TBS/SPKI.
    let mut private = hex("302e020100300506032b657004220420");
    private.extend(hex(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
    ));
    key.write_bytes(private);
    let config = common::TempArtifact::new("laniusc_der", "openssl-config", None);
    config.write_bytes(
        b"[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=DER anchor\nO=Borrowed reader\n",
    );
    let result = common::process_output_with_timeout(
        "OpenSSL independent certificate anchor",
        Command::new("openssl")
            .args(["req", "-new", "-x509", "-keyform", "DER", "-key"])
            .arg(key.path())
            .arg("-config")
            .arg(config.path())
            .args([
                "-subj",
                "/CN=DER anchor/O=Borrowed reader",
                "-days",
                "1",
                "-set_serial",
                "128",
                "-addext",
                "basicConstraints=critical,CA:TRUE",
                "-outform",
                "DER",
            ]),
        Duration::from_secs(10),
    );
    assert!(result.status.success(), "{result:?}");
    let cert = result.stdout;
    assert!(cert.len() > 200 && cert.len() < 8192);
    let source = common::TempArtifact::new("laniusc_der", "certificate", None);
    source.write_bytes(&cert);
    let anchors = common::process_output_with_timeout(
        "OpenSSL certificate field oracle",
        Command::new("python3")
            .args(["-c", CERTIFICATE])
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(5),
    );
    assert!(anchors.status.success(), "{anchors:?}");
    assert!(anchors.stderr.is_empty(), "{anchors:?}");
    let bytes = anchors.stdout;
    let mut at = 0;
    let mut cases = vec![];
    while at < bytes.len() {
        let mode = u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap());
        let length = u64::from_le_bytes(bytes[at + 8..at + 16].try_into().unwrap()) as usize;
        at += 16;
        let data = bytes[at..at + length].to_vec();
        at += length;
        layouts(
            &mut cases,
            case(
                if mode == 255 { 0 } else { 1 },
                if mode == 255 { 0 } else { mode },
                data,
            ),
        );
    }
    assert_eq!(at, bytes.len());
    assert!(cases.len() >= 20);
    check(&cases);
}
// Separate structural decomposition, asserting concrete certificate anchors
// before passing each exact encoding to the ordinary DER fixture protocol.
const CERTIFICATE: &str = r#"
import struct,sys
b=sys.stdin.buffer.read()
def one(data,at=0):
 first=data[at]; p=at+1; n=data[p]; p+=1
 if n&128: width=n&127; n=int.from_bytes(data[p:p+width],'big'); p+=width
 assert p+n<=len(data)
 return first,data[p:p+n],data[at:p+n],p+n
def members(data):
 out=[]; p=0
 while p<len(data):
  tag,content,encoded,p=one(data,p); out.append((tag,content,encoded))
 assert p==len(data); return out
tag,root,encoded,end=one(b);assert tag==48 and end==len(b)
cert=members(root);assert len(cert)==3
tbs=members(cert[0][1]);assert tbs[0][0]==160 and members(tbs[0][1])[0][1]==b'\x02'
assert tbs[1][0]==2 and int.from_bytes(tbs[1][1],'big',signed=True)==128
assert members(cert[1][1])[0][1]==bytes.fromhex('2b6570')
assert cert[2][0]==3 and cert[2][1][0]==0 and len(cert[2][1])==65
spki=members(tbs[6][1]);assert members(spki[0][1])[0][1]==bytes.fromhex('2b6570')
assert spki[1][0]==3 and spki[1][1][0]==0 and len(spki[1][1])==33
assert spki[1][1][1:]==bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
assert b'DER anchor' in tbs[3][1] and b'DER anchor' in tbs[5][1]
def emit(mode,data):sys.stdout.buffer.write(struct.pack('<QQ',mode,len(data))+data)
emit(255,b)
def visit(data,depth=0):
 assert depth<16
 for tag,content,encoded in members(data):
  emit(255,encoded)
  mode={1:0,2:1,3:4,4:5,5:6,6:7,12:8,19:9,22:10,23:11,24:11,48:13,49:14}.get(tag)
  if mode is not None:emit(mode,encoded)
  if tag&32:visit(content,depth+1)
visit(root)
"#;
