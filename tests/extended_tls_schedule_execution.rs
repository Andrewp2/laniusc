//! Independent SHA256 TLS key schedule/transcript peer; RFC8448 §3 anchors.
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
    let entry = root.join(format!("tests/fixtures/extended/tls_schedule/{stem}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TLS schedule fixture", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{stem}: {e}"));
    let exe = common::TempArtifact::new("tls_schedule", stem, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol"))
}
#[derive(Clone, Debug)]
struct Case {
    op: u64,
    layout: u64,
    a: Vec<u8>,
    b: Vec<u8>,
    c: Vec<u8>,
    length: usize,
    mode: u64,
}
fn case(op: u64) -> Case {
    Case {
        op,
        layout: 0,
        a: vec![3; 32],
        b: b"key".to_vec(),
        c: vec![],
        length: 32,
        mode: 0,
    }
}
fn layouts(value: Case, cases: &mut Vec<Case>) {
    for layout in [0, 1] {
        let mut value = value.clone();
        value.layout = layout;
        cases.push(value);
    }
}
fn input(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for c in cases {
        for n in [
            c.op,
            c.layout,
            c.a.len() as u64,
            c.b.len() as u64,
            c.c.len() as u64,
            c.length as u64,
            c.mode,
        ] {
            bytes.extend(n.to_le_bytes());
        }
        bytes.extend(&c.a);
        bytes.extend(&c.b);
        bytes.extend(&c.c);
    }
    bytes
}
const PEER: &str = r#"
import hashlib,hmac,struct,sys
source=sys.stdin.buffer.read();at=0
def words(n):
 global at
 v=struct.unpack_from('<'+'Q'*n,source,at);at+=8*n;return v
def take(n):
 global at
 v=source[at:at+n];assert len(v)==n;at+=n;return v
def H(b):return hashlib.sha256(b).digest()
def mac(k,b):return hmac.new(k,b,hashlib.sha256).digest()
def expand(k,label,ctx,n):
 label=b'tls13 '+label;info=struct.pack('>H',n)+bytes([len(label)])+label+bytes([len(ctx)])+ctx;out=b'';prev=b''
 for i in range(1,(n+31)//32+1):prev=mac(k,prev+info+bytes([i]));out+=prev
 return out[:n]
def derive(k,label,th):return expand(k,label,th,32)
def finished(k,th):return mac(expand(k,b'finished',b'',32),th)
def q(*a):return struct.pack('<'+'Q'*len(a),*a)
magic=bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
count,=words(1)
for _ in range(count):
 op,layout,alen,blen,clen,n,mode=words(7);a,b,c=take(alen),take(blen),take(clen);status=0;out=b''
 if op==0:
  if mode:status=1
  elif len(a)!=32:status=2
  elif not 1<=len(b)<=249:status=4
  elif len(c)>255:status=5
  elif n>8160:status=6
  else:out=expand(a,b,c,n)
 elif op in (1,3):
  ch,sh,sf,cf,before=[c[i:i+32] for i in range(0,160,32)];empty=H(b'');early=mac(bytes(32),bytes(32) if mode&1 else a);hs=mac(derive(early,b'derived',empty),bytes(32) if mode&2 else b);master=mac(derive(hs,b'derived',empty),bytes(32))
  client=derive(hs,b'c hs traffic',sh);server=derive(hs,b's hs traffic',sh);ex=derive(master,b'exp master',sf);res=derive(master,b'res master',cf);ee=derive(early,b'e exp master',ch)
  values=[early,derive(early,b'ext binder',empty),derive(early,b'res binder',empty),derive(early,b'c e traffic',ch),ee,hs,client,server,master,derive(master,b'c ap traffic',sf),derive(master,b's ap traffic',sf),ex,res,expand(res,b'resumption',bytes({0:0,1:1,33:255}.get(n,2)),32),finished(server,before),finished(client,sf),expand(client,b'traffic upd',b'',32)]
  out=b''.join(values)+expand(derive(ex,b'test export',empty),b'exporter',H(a),n)+expand(derive(ee,b'test export',empty),b'exporter',H(a),n)
 elif op==2:
  state=(b'',0,0,False);fork=state;pos=0
  while pos<len(a):
   action=a[pos];size=int.from_bytes(a[pos+1:pos+3],'little');frame=a[pos+3:pos+3+size];pos+=3+size;raw,count,first,hrr=state;error=0
   if action in (0,1,5,6,7):
    if action==5:error=1
    elif len(frame)<4 or len(frame)!=int.from_bytes(frame[1:4],'big')+4:error=2
    elif action==1:
     if len(frame)<38 or frame[0]!=2 or frame[6:38]!=magic:error=2
     elif hrr or count!=1 or first!=1:error=4
     else:state=(b'\xfe\0\0\x20'+H(raw)+frame,2,first,True)
    elif frame[0]==254:error=3
    elif action in (6,7):error=5
    else:state=(raw+frame,count+1,frame[0] if count==0 else first,hrr)
   if action==3:fork=state
   if action==4:state,fork=fork,state
   raw,count,first,hrr=state;out+=q(error,count,int(hrr))+H(raw)
 else:raise AssertionError(op)
 sys.stdout.buffer.write(q(status,len(out))+out)
assert at==len(source)
"#;
fn checked(out: &std::process::Output) {
    assert_eq!(
        out.status.code(),
        Some(0),
        "stdout={} prefix={:?} stderr={:?}",
        out.stdout.len(),
        &out.stdout[..out.stdout.len().min(32)],
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.stderr.is_empty(), "{out:?}");
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    let end = *at + 8;
    let n = u64::from_le_bytes(bytes[*at..end].try_into().unwrap());
    *at = end;
    n
}
fn compare(cases: Vec<Case>) -> Vec<Vec<u8>> {
    let file = common::TempArtifact::new("tls_schedule", "input", None);
    file.write_bytes(input(&cases));
    let expected = common::process_output_with_timeout(
        "Python TLS schedule peer",
        Command::new("python3")
            .args(["-c", PEER])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(15),
    );
    checked(&expected);
    let trace = common::TempArtifact::new("tls_schedule", "memory", None);
    let native = common::process_output_with_timeout(
        "native TLS schedule protocol",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(protocol().path())
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let mut a = 0;
    let mut b = 0;
    let mut results = vec![];
    for (i, c) in cases.iter().enumerate() {
        let x = word(&native.stdout, &mut a) as i64;
        let y = word(&native.stdout, &mut a) as i64;
        if c.layout == 0 {
            assert!(x < 0 && y < 0);
        } else {
            assert_eq!((x, y), (1, 1));
        }
        let status = word(&native.stdout, &mut a);
        let n = word(&native.stdout, &mut a) as usize;
        assert_eq!(
            (status, n),
            (
                word(&expected.stdout, &mut b),
                word(&expected.stdout, &mut b) as usize
            ),
            "case{i}: {c:?}"
        );
        assert_eq!(
            &native.stdout[a..a + n],
            &expected.stdout[b..b + n],
            "case{i}: {c:?}"
        );
        results.push(native.stdout[a..a + n].to_vec());
        a += n;
        b += n;
    }
    assert_eq!(a, native.stdout.len());
    assert_eq!(b, expected.stdout.len());
    eprintln!("TLS schedule protocol commands={}", cases.len());
    results
}
fn pattern(n: usize, seed: usize) -> Vec<u8> {
    (0..n).map(|i| (i * 73 + seed) as u8).collect()
}
fn hex(s: &str) -> Vec<u8> {
    assert_eq!(s.len() % 2, 0, "hexadecimal vectors must contain full bytes");
    s.as_bytes()
        .chunks_exact(2)
        .map(|p| u8::from_str_radix(std::str::from_utf8(p).unwrap(), 16).unwrap())
        .collect()
}
#[test]
fn ordinary_imported_schedule_and_transcript_consumer_has_no_error_projection() {
    let exe = compile("plain");
    let trace = common::TempArtifact::new("tls_schedule", "plain_memory", None);
    let output = common::process_output_with_timeout(
        "ordinary schedule consumer",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn labels_phases_finished_exporters_and_rfc8448_anchors_match_independent_peer() {
    let mut cases = vec![];
    let mut rfc = case(1);
    rfc.a = vec![];
    rfc.b = hex("8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d");
    rfc.c = include_bytes!("fixtures/extended/tls_schedule/rfc8448-1rtt-hashes.bin").to_vec();
    rfc.mode = 1;
    layouts(rfc, &mut cases);
    for seed in 0..20 {
        let mut c = case(if seed == 0 { 3 } else { 1 });
        c.a = pattern([0, 1, 31, 32, 257][seed % 5], seed);
        c.b = pattern([0, 1, 32, 128][seed % 4], seed + 2);
        c.c = pattern(160, seed + 4);
        c.mode = (seed % 4) as u64;
        c.length = [0, 1, 32, 33, 257][seed % 5];
        layouts(c, &mut cases);
    }
    let values = compare(cases);
    for value in &values[..2] {
        for (index, anchor) in [
            (
                0,
                "33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a",
            ),
            (
                5,
                "1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac",
            ),
            (
                6,
                "b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21",
            ),
            (
                7,
                "b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38",
            ),
            (
                8,
                "18df06843d13a08bf2a449844c5f8a478001bc4d4c627984d5a41da8d0402919",
            ),
            (
                9,
                "9e40646ce79a7f9dc05af8889bce6552875afa0b06df0087f792ebb7c17504a5",
            ),
            (
                10,
                "a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643",
            ),
            (
                11,
                "fe22f881176eda18eb8f44529e6792c50c9a3f89452f68d8ae311b4309d3cf50",
            ),
            (
                12,
                "7df235f2031d2a051287d02b0241b0bfdaf86cc856231f2d5aba46c434ec196c",
            ),
            (
                13,
                "4ecd0eb6ec3b4d87f5d6028f922ca4c5851a277fd41311c9e62d2c9492e1c4f3",
            ),
            (
                14,
                "9b9b141d906337fbd2cbdce71df4deda4ab42c309572cb7fffee5454b78f0718",
            ),
            (
                15,
                "a8ec436d677634ae525ac1fcebe11a039ec17694fac6e98527b642f2edd5ce61",
            ),
        ] {
            assert_eq!(
                &value[index * 32..index * 32 + 32],
                hex(anchor),
                "RFC8448§3 secret{index}"
            );
        }
    }
}
#[test]
fn checked_label_lengths_bounds_and_output_limits_preserve_all_output() {
    let mut cases = vec![];
    for (key, label, ctx, n) in [
        (32, 1, 0, 0),
        (32, 249, 255, 8160),
        (32, 250, 0, 32),
        (32, 0, 0, 0),
        (31, 3, 0, 32),
        (33, 3, 0, 32),
        (0, 3, 0, 0),
        (32, 3, 256, 32),
        (32, 3, 0, 8161),
        (32, 249, 255, 33),
        (32, 3, 0, 1),
    ] {
        let mut c = case(0);
        c.a = pattern(key, 1);
        c.b = pattern(label, 2);
        c.c = pattern(ctx, 3);
        c.length = n;
        layouts(c, &mut cases);
    }
    for mode in 1..=12 {
        let mut c = case(0);
        c.mode = mode;
        layouts(c, &mut cases);
    }
    compare(cases);
}
fn frame(kind: u8, body: &[u8]) -> Vec<u8> {
    let mut v = vec![
        kind,
        (body.len() >> 16) as u8,
        (body.len() >> 8) as u8,
        body.len() as u8,
    ];
    v.extend(body);
    v
}
fn command(out: &mut Vec<u8>, action: u8, message: &[u8]) {
    out.push(action);
    out.extend((message.len() as u16).to_le_bytes());
    out.extend(message);
}
#[test]
fn complete_transcripts_snapshots_copies_hrr_and_error_atomicity_match_hashlib() {
    let mut cases = vec![];
    let trace = include_bytes!("fixtures/extended/tls_schedule/rfc8448-1rtt-handshakes.bin");
    let mut commands = vec![];
    let mut at = 0;
    while at < trace.len() {
        let n = ((trace[at + 1] as usize) << 16)
            | ((trace[at + 2] as usize) << 8)
            | trace[at + 3] as usize;
        command(&mut commands, 0, &trace[at..at + n + 4]);
        command(&mut commands, 2, &[]);
        at += n + 4;
    }
    let mut c = case(2);
    c.a = commands;
    layouts(c, &mut cases);
    let mut hrr = frame(2, &vec![0; 34]);
    hrr[4] = 3;
    hrr[5] = 3;
    hrr[6..38].copy_from_slice(&hex(
        "cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c",
    ));
    for seed in 0..12 {
        let mut commands = vec![];
        command(&mut commands, 1, &hrr);
        command(&mut commands, 0, &frame(1, &pattern(seed + 1, seed)));
        command(&mut commands, 3, &[]);
        let mut wrong = hrr.clone();
        wrong[6 + (seed * 7) % 32] ^= 1;
        command(&mut commands, 1, &wrong);
        command(&mut commands, 1, &hrr);
        command(&mut commands, 1, &hrr);
        command(&mut commands, 0, &frame(1, &pattern(seed + 2, seed + 7)));
        command(&mut commands, 4, &[]);
        command(&mut commands, 0, &frame(8, &pattern(seed + 3, seed + 9)));
        for broken in [
            vec![],
            vec![1, 0, 0],
            vec![1, 0, 0, 1],
            vec![1, 0, 0, 0, 1],
            frame(254, &[0; 32]),
        ] {
            command(&mut commands, 0, &broken);
        }
        for action in [5, 6, 7] {
            command(&mut commands, action, &frame(20, &[7; 32]));
        }
        command(&mut commands, 0, &frame(20, &pattern(32, seed)));
        let mut c = case(2);
        c.a = commands;
        layouts(c, &mut cases);
    }
    compare(cases);
}
