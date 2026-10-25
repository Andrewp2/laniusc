//! Bounded real certificate inspector: OpenSSL metadata, schema and I/O/owner contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    path::PathBuf,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};
const MAX: usize = 1_048_576;
const CALLS: usize = 131_072;
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/certificate_info.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("certificate_info application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|e| panic!("certificate_info: {e}"));
        let file = common::TempArtifact::new("laniusc_certificate_info", "executable", None);
        file.write_bytes(bytes);
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
struct Case {
    name: String,
    data: Vec<u8>,
    status: i32,
    report: Vec<u8>,
}
const CORPUS: &str = r#"
import datetime,hashlib,pathlib,struct,subprocess,sys,tempfile
MAX=1048576

def tlv(tag,body):
 n=len(body); w=max(1,(n.bit_length()+7)//8)
 return bytes([tag])+ (bytes([n]) if n<128 else bytes([128+w])+n.to_bytes(w,'big'))+body
def seq(*parts):return tlv(48,b''.join(parts))
def integer(n):
 b=n.to_bytes(max(1,(n.bit_length()+8)//8),'big',signed=True)
 while len(b)>1 and int.from_bytes(b[1:],'big',signed=True)==n:b=b[1:]
 return tlv(2,b)
def base(n):
 out=[n&127];n>>=7
 while n:out.append((n&127)|128);n>>=7
 return bytes(reversed(out))
def oid(*arcs):return tlv(6,base(40*arcs[0]+arcs[1])+b''.join(base(n) for n in arcs[2:]))
def bits(data,unused=0):return tlv(3,bytes([unused])+data)
ED=seq(oid(1,3,101,112))
# The RFC8032 key spelling below is checked by length; these synthetic key/signature
# bytes are schema data, never a claim of cryptographic authentication.
KEY=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
def name(count=1):return seq(*(tlv(49,seq(oid(2,5,4,3),tlv(12,b'inspection'))) for _ in range(count)))
NAME=name()
def extension(index,value,critical=False):return seq(oid(1,2,3,index),*( [b'\x01\x01\xff'] if critical else []),tlv(4,value))
def build(**kw):
 c=dict(version=2,serial=integer(128),inner=ED,outer=ED,issuer=NAME,subject=NAME,
 validity=seq(tlv(23,b'240101000000Z'),tlv(24,b'20500101000000Z')),
 spki=seq(ED,bits(KEY)),signature=bits(bytes(64)),extensions=None)
 c.update(kw); fields=[] if c['version'] is None else [tlv(160,integer(c['version']))]
 fields += [c[k] for k in ('serial','inner','issuer','validity','subject','spki')]
 if c['extensions'] is not None:fields.append(tlv(163,seq(*c['extensions'])))
 return seq(seq(*fields),c['outer'],c['signature'])
class Node:
 def __init__(self,tag,body):self.tag,self.body=tag,body
def nodes(data):
 out=[]; at=0
 while at<len(data):
  tag,lead=data[at:at+2];at+=2
  if lead&128:
   w=lead&127;assert 1<=w<=4 and data[at]!=0;n=int.from_bytes(data[at:at+w],'big');at+=w;assert n>=128
  else:n=lead
  assert at+n<=len(data);out.append(Node(tag,data[at:at+n]));at+=n
 assert at==len(data);return out
def one(data):
 out=nodes(data);assert len(out)==1;return out[0]
def timestamp(node):
 b=node.body;w=2 if node.tag==23 else 4;y=int(b[:w]);y=y+(1900 if y>=50 else 2000) if w==2 else y
 fields=[y]+[int(b[i:i+2]) for i in range(w,w+10,2)];datetime.datetime(*fields)
 return f'{fields[0]:04d}-{fields[1]:02d}-{fields[2]:02d}T{fields[3]:02d}:{fields[4]:02d}:{fields[5]:02d}Z'
def report(data):
 outer=nodes(one(data).body);fields=nodes(outer[0].body);version=1
 if fields[0].tag==160:version=int.from_bytes(one(fields.pop(0).body).body,'big')+1
 serial,inner,issuer,validity,subject,spki=fields[:6];dates=nodes(validity.body);sig=nodes(outer[1].body)[0].body;key=nodes(nodes(spki.body)[0].body)[0].body
 serial=serial.body[1:] if len(serial.body)>1 and serial.body[0]==0 else serial.body
 extensions=[]
 for item in fields[6:]:
  if item.tag==163:extensions=nodes(one(item.body).body)
 unknown=0
 for item in extensions:
  e=nodes(item.body);critical=len(e)==3 and e[1].body==b'\xff'
  unknown += critical and e[0].body not in (b'\x55\x1d\x11',b'\x55\x1d\x13',b'\x55\x1d\x0f',b'\x55\x1d\x25')
 result=(f'inspection=parse-schema-only\ncertificate_sha256={hashlib.sha256(data).hexdigest()}\nversion={version}\nserial_hex={serial.hex()}\n'
 +f'not_before_utc={timestamp(dates[0])}\nnot_after_utc={timestamp(dates[1])}\n'
 +f'signature_oid_encoded_content_hex={sig.hex()}\nspki_oid_encoded_content_hex={key.hex()}\n'
 +f'issuer_rdns={len(nodes(issuer.body))}\nsubject_rdns={len(nodes(subject.body))}\nextensions={len(extensions)}\nunknown_critical_extensions={unknown}\n').encode()
 return result
records=[]
def good(label,data):
 out=report(data);records.append((label,data,0 if len(out)<=8192 else 7,out if len(out)<=8192 else b''))
def bad(label,data,status=5):records.append((label,data,status,b''))
with tempfile.TemporaryDirectory(prefix='certificate_info_openssl_') as d:
 d=pathlib.Path(d);config=d/'req.cnf';config.write_text('[req]\ndistinguished_name=dn\n[dn]\n')
 for alg,key_args in [('ed25519',['-newkey','ed25519']),('rsa',['-newkey','rsa:2048']),('ecdsa',['-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256'])]:
  key=d/(alg+'.key');cert=d/(alg+'.der')
  command=['openssl','req','-new','-x509',*key_args,'-nodes','-keyout',str(key),'-config',str(config),'-subj','/C=US/O=Certificate inspector/OU=A+CN=inspection.example','-days','2','-set_serial','128','-outform','DER','-out',str(cert),'-addext','basicConstraints=critical,CA:TRUE,pathlen:1','-addext','keyUsage=critical,digitalSignature,keyCertSign','-addext','extendedKeyUsage=serverAuth','-addext','subjectAltName=DNS:inspection.example']
  if alg=='ed25519':command+=['-addext','1.2.3.4=critical,DER:05:00']
  run=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=12);assert run.returncode==0,run.stderr
  data=cert.read_bytes();expected=report(data)
  # OpenSSL independently checks digest, unsigned serial and parsed UTC dates.
  metadata=subprocess.run(['openssl','x509','-inform','DER','-in',str(cert),'-noout','-serial','-dates','-fingerprint','-sha256'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5);assert metadata.returncode==0,metadata.stderr
  values=dict(line.split('=',1) for line in metadata.stdout.decode().splitlines());lines=dict(line.split('=',1) for line in expected.decode().splitlines())
  assert values['serial'].lower()==lines['serial_hex']
  for src,dst in [('notBefore','not_before_utc'),('notAfter','not_after_utc')]:assert datetime.datetime.strptime(values[src],'%b %d %H:%M:%S %Y %Z').strftime('%Y-%m-%dT%H:%M:%SZ')==lines[dst]
  fingerprint=next(v for k,v in values.items() if k.lower()=='sha256 fingerprint');assert fingerprint.replace(':','').lower()==lines['certificate_sha256']
  good('openssl-'+alg,data)
  if alg=='ed25519':
   tampered=data[:-1]+bytes([data[-1]^1]);good('signature-tamper-inspection-only',tampered)
base_cert=build();good('synthetic-base',base_cert);good('synthetic-v1',build(version=None));good('synthetic-v2',build(version=1))
good('past-reversed-dates-inspection-only',build(validity=seq(tlv(23,b'100101000000Z'),tlv(23,b'010101000000Z'))))
good('unknown-critical-inspection-only',build(extensions=[extension(9,tlv(5,b''),True)]))
for label,data in [('empty',b''),('pem-is-not-der',b'-----BEGIN CERTIFICATE-----\n'),('outer-set',bytes([49])+base_cert[1:]),('truncated',base_cert[:-1]),('trailing',base_cert+b'\0'),('zero-serial',build(serial=integer(0))),('negative-serial',build(serial=integer(-1))),('mismatched-algorithm',build(outer=seq(oid(1,3,101,113)))),('invalid-month',build(validity=seq(tlv(23,b'241301000000Z'),tlv(24,b'20500101000000Z')))),('duplicate-extension',build(extensions=[extension(9,tlv(5,b'')),extension(9,tlv(5,b''))])),('unsupported-version',build(version=3)),('wrong-ed-key-length',build(spki=seq(ED,bits(bytes(31))))),('signature-unused-bit',build(signature=bits(bytes(64),1)))]:bad(label,data)
# Exact output cap uses a legal long positive serial. Toggle a count's decimal
# width if needed to make the fixed report overhead even, then solve 2*n.
for count in (1,10):
 overhead=len(report(build(serial=tlv(2,b'\x01'),issuer=name(count))))-2
 if (8192-overhead)%2==0:
  n=(8192-overhead)//2; exact=build(serial=tlv(2,b'\x01'+bytes(n-1)),issuer=name(count));assert len(report(exact))==8192
  good('output-exact-cap',exact);good('output-excess',build(serial=tlv(2,b'\x01'+bytes(n)),issuer=name(count)));break
else:raise AssertionError('output-cap parity')
long_oid=seq(tlv(6,b'\x2a'+b'\x01'*4200));good('long-oid-output-limit',build(inner=long_oid,outer=long_oid))
# A single opaque extension can fill the input without inflating the report.
payload=MAX-len(build(extensions=[extension(9,tlv(4,b''))]))
for _ in range(8):
 large=build(extensions=[extension(9,tlv(4,bytes(payload)))]);difference=MAX-len(large)
 if difference==0:break
 payload+=difference
assert len(large)==MAX;good('input-exact-cap',large);bad('input-excess',large+b'!',7)
# Charged duplicate scans re-decode each prior long extension. This reaches
# default shared work before the 100000-item budget, with <1MiB actual input.
work=build(extensions=[extension(1000+i,tlv(4,bytes(1024))) for i in range(150)]);assert len(work)<MAX;bad('work-limit',work,7)
out=sys.stdout.buffer
for name,data,status,expected in records:
 label=name.encode();out.write(struct.pack('<IIII',len(label),len(data),status,len(expected))+label+data+expected)
"#;
fn corpus() -> &'static Vec<Case> {
    static CASES: OnceLock<Vec<Case>> = OnceLock::new();
    CASES.get_or_init(|| {
        let output = common::process_output_with_timeout(
            "OpenSSL certificates and independent metadata oracle",
            Command::new("python3").arg("-c").arg(CORPUS),
            Duration::from_secs(25),
        );
        assert!(output.status.success(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        let mut at = 0;
        let mut out = Vec::new();
        while at < output.stdout.len() {
            let header = &output.stdout[at..at + 16];
            let word = |i| u32::from_le_bytes(header[i..i + 4].try_into().unwrap()) as usize;
            let (n, d, s, r) = (word(0), word(4), word(8), word(12));
            at += 16;
            let name = String::from_utf8(output.stdout[at..at + n].to_vec()).unwrap();
            at += n;
            let data = output.stdout[at..at + d].to_vec();
            at += d;
            let report = output.stdout[at..at + r].to_vec();
            at += r;
            out.push(Case {
                name,
                data,
                status: s as i32,
                report,
            });
        }
        assert_eq!(at, output.stdout.len());
        out
    })
}
fn case(name: &str) -> &'static Case {
    corpus().iter().find(|case| case.name == name).unwrap()
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn fields<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (a, v) = body.rsplit_once(" = ").unwrap();
    (a.trim_end().strip_suffix(')').unwrap(), v)
}
fn result<'a>(line: &'a str, name: &str) -> &'a str {
    fields(line, name).1.split_whitespace().next().unwrap()
}
fn request(line: &str, name: &str) -> usize {
    fields(line, name)
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}
struct Run {
    output: Output,
    events: String,
    maps: usize,
    failures: Vec<usize>,
}
fn run(data: &[u8], args: &[OsString], inject: &[&str], closed: bool, seconds: &str) -> Run {
    let input = common::TempArtifact::new("laniusc_certificate_info", "stdin", None);
    input.write_bytes(data);
    let trace = common::TempArtifact::new("laniusc_certificate_info", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", seconds, "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,munmap,mremap,brk,openat,close",
            "-e",
            "signal=none",
        ]);
    for rule in inject {
        command.arg("-e").arg(format!("inject={rule}"));
    }
    command
        .arg(executable().path())
        .args(args)
        .stdin(fs::File::open(input.path()).unwrap());
    if closed {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(Stdio::from(writer));
    }
    let output = if closed {
        // The common capture helper replaces stdout with a pipe. Preserve
        // this explicitly supplied closed-reader pipe; timeout still bounds
        // the traced native process.
        command
            .output()
            .expect("bounded certificate_info EPIPE case")
    } else {
        common::process_output_with_timeout(
            "certificate_info native process",
            &mut command,
            Duration::from_secs(30),
        )
    };
    assert_eq!(fs::read(input.path()).unwrap(), data);
    let events = fs::read_to_string(trace.path()).unwrap();
    for rule in inject {
        let name = rule.split(':').next().unwrap();
        let reached: Vec<_> = calls(&events, name)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect();
        if rule.ends_with('+') {
            assert!(!reached.is_empty() && reached.len() <= CALLS, "{events}");
        } else {
            assert_eq!(reached.len(), 1, "unreached/repeated {rule}: {events}");
        }
        if let Some(error) = rule.split("error=").nth(1) {
            assert!(
                reached
                    .iter()
                    .all(|line| line.contains(error.split(':').next().unwrap())),
                "{events}"
            );
        }
        if let Some(value) = rule.split("retval=").nth(1) {
            let expected = value.split(':').next().unwrap();
            assert!(
                reached.iter().all(|line| result(line, name) == expected),
                "wrong injected return for {rule}: {events}"
            );
        }
    }
    let mut live = BTreeMap::<u64, usize>::new();
    let mut maps = 0;
    let mut released = 0;
    let mut failures = Vec::new();
    let mut reading = false;
    let mut publishing = false;
    for line in events.lines() {
        if line.starts_with("read(") {
            reading = true;
            assert!(line.starts_with("read(0,"), "{events}");
        }
        if line.starts_with("write(") {
            publishing = true;
            assert!(
                live.is_empty(),
                "all input owners must retire before publication: {events}"
            );
            assert!(line.starts_with("write(1,"), "{events}");
        }
        if line.starts_with("mmap(") {
            assert!(!reading && !publishing, "late allocation: {events}");
            maps += 1;
            let (a, v) = fields(line, "mmap");
            let length = a
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            if let Some(address) = v.split_whitespace().next().unwrap().strip_prefix("0x") {
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(live.insert(address, length).is_none(), "{events}");
            } else {
                assert!(v.contains("ENOMEM") && v.contains("INJECTED"), "{events}");
                failures.push(maps);
            }
        }
        if line.starts_with("munmap(") {
            let (a, v) = fields(line, "munmap");
            assert_eq!(v, "0");
            let (address, length) = a.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            assert_eq!(
                live.remove(&address),
                Some(length.trim().parse().unwrap()),
                "unknown/wrong/double release: {events}"
            );
            released += 1;
        }
        for forbidden in ["mremap(", "brk(", "openat(", "close("] {
            assert!(
                !line.starts_with(forbidden),
                "unexpected native storage/file operation: {events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked input: {live:?}\n{events}");
    assert_eq!(released, maps - failures.len());
    Run {
        output,
        events,
        maps,
        failures,
    }
}
fn checked(run: &Run, status: i32, expected: &[u8], signal: bool, eof: bool) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, expected, "{}", run.events);
    assert!(run.output.stderr.is_empty(), "{:?}", run.output);
    let actions = calls(&run.events, "rt_sigaction");
    assert_eq!(actions.len(), usize::from(signal));
    if signal {
        assert!(actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"));
        if !actions[0].contains("INJECTED") {
            assert_eq!(result(actions[0], "rt_sigaction"), "0");
        }
    }
    let reads = calls(&run.events, "read");
    let writes = calls(&run.events, "write");
    assert!(reads.len() + writes.len() <= CALLS);
    for line in &reads {
        assert!((1..=1024).contains(&request(line, "read")));
    }
    for line in &writes {
        assert!((1..=1024).contains(&request(line, "write")));
    }
    if eof || !writes.is_empty() {
        assert_eq!(
            result(reads.last().expect("EOF required"), "read"),
            "0",
            "{events}",
            events = run.events
        );
    }
    if let Some(first) = run
        .events
        .lines()
        .position(|line| line.starts_with("write("))
    {
        let last = run
            .events
            .lines()
            .enumerate()
            .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
            .last()
            .unwrap();
        assert!(last < first, "{events}", events = run.events);
    }
    if matches!(status, 2 | 4 | 5) {
        assert!(writes.is_empty());
    }
    if !signal {
        assert!(reads.is_empty() && writes.is_empty() && run.maps == 0);
    } else {
        assert!(run.maps <= 1);
    }
}
#[test]
fn certificate_info_real_metadata_schema_and_usage() {
    let mut count = 0;
    for case in corpus().iter().filter(|case| {
        !case.name.contains("cap") && !case.name.contains("excess") && !case.name.contains("limit")
    }) {
        let observed = run(&case.data, &[], &[], false, "8s");
        checked(&observed, case.status, &case.report, true, true);
        assert_eq!(observed.maps, 1);
        count += 1;
    }
    for args in [
        vec![OsString::from("--help")],
        vec![OsString::from("extra"), OsString::from("argument")],
        vec![OsString::from_vec(vec![255])],
    ] {
        let observed = run(&case("synthetic-base").data, &args, &[], false, "5s");
        checked(&observed, 2, b"", false, false);
        count += 1;
    }
    eprintln!(
        "certificate_info ordinary: one shared strictELF,{count} native cases,OpenSSL Ed25519/RSA/P256 plus independent DER metadata/schema and usage"
    );
}
#[test]
fn certificate_info_owner_cleanup_partial_io_and_faults() {
    let base = case("synthetic-base");
    let observed = run(&base.data, &[], &[], false, "5s");
    checked(&observed, 0, &base.report, true, true);
    assert_eq!(observed.maps, 1);
    let mut count = 1;
    for ordinal in 1..=observed.maps {
        let rule = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(&base.data, &[], &[&rule], false, "5s");
        checked(&observed, 4, b"", true, false);
        assert_eq!(observed.failures, vec![ordinal]);
        assert!(calls(&observed.events, "read").is_empty());
        count += 1;
    }
    for (rule, status, wanted) in [
        ("read:error=EIO:when=1", 3, b"".as_slice()),
        ("read:error=EAGAIN:when=1", 3, b""),
        ("read:retval=1025:when=1", 3, b""),
        ("read:error=EINTR:when=1", 0, base.report.as_slice()),
        ("read:error=EINTR:when=2", 0, base.report.as_slice()),
        ("write:error=EIO:when=1", 3, b""),
        ("write:error=EAGAIN:when=1", 3, b""),
        ("write:retval=0:when=1", 3, b""),
        ("write:retval=1025:when=1", 3, b""),
        ("write:error=EINTR:when=1", 0, base.report.as_slice()),
        ("write:retval=1:when=1", 0, &base.report[1..]),
    ] {
        let observed = run(&base.data, &[], &[rule], false, "5s");
        checked(
            &observed,
            status,
            wanted,
            true,
            rule.starts_with("write:") || status == 0,
        );
        if rule == "write:retval=1:when=1" {
            let writes = calls(&observed.events, "write");
            assert_eq!(writes.len(), 2);
            assert_eq!(request(writes[1], "write"), base.report.len() - 1);
        }
        count += 1;
    }
    // strace supplies the first DER byte while reporting a genuine one-byte
    // API result; the file begins at byte1 because the injected call skips read.
    let rule = format!("read:retval=1:poke_exit=@arg2={:02x}:when=1", base.data[0]);
    let observed = run(&base.data[1..], &[], &[&rule], false, "5s");
    checked(&observed, 0, &base.report, true, true);
    count += 1;
    let observed = run(&base.data, &[], &[], true, "5s");
    checked(&observed, 3, b"", true, true);
    assert!(calls(&observed.events, "write")[0].contains("EPIPE"));
    count += 1;
    let observed = run(
        &base.data,
        &[],
        &["rt_sigaction:error=EINTR:when=1"],
        false,
        "5s",
    );
    checked(&observed, 3, b"", true, false);
    assert_eq!(observed.maps, 0);
    assert!(calls(&observed.events, "read").is_empty());
    count += 1;
    let full = case("output-exact-cap");
    let observed = run(&full.data, &[], &["write:error=EIO:when=2"], false, "5s");
    checked(&observed, 3, &full.report[..1024], true, true);
    assert_eq!(calls(&observed.events, "write").len(), 2);
    count += 1;
    eprintln!(
        "certificate_info cleanup:{count} native cases,every reached allocation denied,exact owner ledger and partial/retry/error I/O; injected short writes verify reported progress,not actual first-byte delivery"
    );
}
#[test]
fn certificate_info_caps_eof_work_and_shared_call_budget() {
    let mut count = 0;
    for name in [
        "input-exact-cap",
        "input-excess",
        "output-exact-cap",
        "output-excess",
        "long-oid-output-limit",
        "work-limit",
    ] {
        let case = case(name);
        let observed = run(&case.data, &[], &[], false, "15s");
        checked(
            &observed,
            case.status,
            &case.report,
            true,
            name != "input-excess",
        );
        let reads = calls(&observed.events, "read");
        if name.starts_with("input-") {
            assert_eq!(request(reads.last().unwrap(), "read"), 1);
            assert_eq!(
                result(reads.last().unwrap(), "read"),
                if name == "input-excess" { "1" } else { "0" }
            );
            assert_eq!(reads.len(), MAX / 1024 + 1);
        }
        if name == "output-exact-cap" {
            assert_eq!(case.report.len(), 8192);
            assert_eq!(calls(&observed.events, "write").len(), 8);
        }
        if case.status == 7 {
            assert!(calls(&observed.events, "write").is_empty());
        }
        count += 1;
    }
    let base = case("synthetic-base");
    for rule in ["read:error=EINTR:when=1+", "write:error=EINTR:when=1+"] {
        let observed = run(&base.data, &[], &[rule], false, "20s");
        checked(&observed, 7, b"", true, rule.starts_with("write:"));
        let reads = calls(&observed.events, "read").len();
        let writes = calls(&observed.events, "write").len();
        assert_eq!(reads + writes, CALLS);
        if rule.starts_with("read:") {
            assert_eq!(writes, 0);
        } else {
            assert!(reads > 0 && writes == CALLS - reads);
        }
        count += 1;
    }
    eprintln!(
        "certificate_info limits:{count} native cases,actual1MiB+1probe,8192report boundary,default shared X509 work and131072 read/write attempts including interruptions"
    );
}
