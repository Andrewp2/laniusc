//! Real bounded certificate path/identity/time verifier and owner/I/O contracts.
//! Shared multi-algorithm signature migration admission is pending.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
const MAX: usize = 1_048_576;
const CALLS: usize = 131_072;
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/verify_certificate.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("verify_certificate application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("verify_certificate: {error}"));
        let file = common::TempArtifact::new("laniusc_verify_certificate", "executable", None);
        file.write_bytes(bytes);
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
struct Case {
    name: String,
    anchor: Vec<u8>,
    chain: Vec<u8>,
    mode: String,
    identity: String,
    time: String,
    status: i32,
}
// OpenSSL signs every tested certificate's exact TBS DER. The separate verify
// invocation checks selected common-profile cases; ordering/duplicate and
// SAN-only policies deliberately have explicit expectations of their own.
const CORPUS: &str = r#"
import base64,hashlib,ipaddress,pathlib,struct,subprocess,sys,tempfile
MAX=1048576
def tlv(tag,body):
 n=len(body);w=max(1,(n.bit_length()+7)//8)
 return bytes([tag])+(bytes([n]) if n<128 else bytes([128+w])+n.to_bytes(w,'big'))+body
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
def bits(value,unused=0):return tlv(3,bytes([unused])+value)
def name(value):return seq(tlv(49,seq(oid(2,5,4,3),tlv(12,value.encode()))))
def extension(arcs,value,critical=False):return seq(oid(*arcs),*([b'\x01\x01\xff'] if critical else []),tlv(4,value))
ED=seq(oid(1,3,101,112));NOW='1704067200'
DEFAULT_SAN=seq(tlv(130,b'server.example'),tlv(135,ipaddress.ip_address('192.0.2.1').packed),tlv(135,ipaddress.ip_address('2001:db8::1').packed))
records=[]
with tempfile.TemporaryDirectory(prefix='verify_certificate_openssl_') as temporary:
 directory=pathlib.Path(temporary)
 def openssl(*args):
  result=subprocess.run(['openssl',*map(str,args)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
  assert result.returncode==0,(args,result.stderr);return result.stdout
 def key(label):
  path=directory/(label+'.key.der');path.write_bytes(bytes.fromhex('302e020100300506032b657004220420')+hashlib.sha256(('verify-certificate:'+label).encode()).digest())
  public=openssl('pkey','-inform','DER','-in',path,'-pubout','-outform','DER')
  assert public[:12]==bytes.fromhex('302a300506032b6570032100') and len(public)==44
  return path,public
 def certificate(subject,issuer,public,signer,ca=False,pathlen=8,usage=None,eku=None,san=DEFAULT_SAN,extra=(),validity=None):
  # Serial identity is independent of the certificate name; uniqueness is only
  # needed by the external diagnostic tool, never supplied as a trust signal.
  serial_number=int.from_bytes(hashlib.sha256((subject+'|'+issuer).encode()).digest()[:8],'big') or 1
  validity=validity or seq(tlv(23,b'200101000000Z'),tlv(23,b'400101000000Z'))
  bc=seq(b'\x01\x01\xff',integer(pathlen)) if ca else seq()
  usage=usage if usage is not None else bits(b'\x04',2) if ca else bits(b'\x80',7)
  extensions=[extension((2,5,29,19),bc,True),extension((2,5,29,15),usage,True)]
  if not ca:
   extensions.append(extension((2,5,29,37),seq(oid(1,3,6,1,5,5,7,3,1) if eku is None else eku)))
   if san is not None:extensions.append(extension((2,5,29,17),san))
  extensions.extend(extra)
  tbs=seq(tlv(160,integer(2)),integer(serial_number),ED,name(issuer),validity,name(subject),public,tlv(163,seq(*extensions)))
  source=directory/'sign-input.der';source.write_bytes(tbs)
  signature=openssl('pkeyutl','-sign','-rawin','-inkey',signer,'-keyform','DER','-in',source)
  assert len(signature)==64;return seq(tbs,ED,bits(signature))
 def pem(data):return b'-----BEGIN CERTIFICATE-----\n'+base64.encodebytes(data)+b'-----END CERTIFICATE-----\n'
 def oracle(anchor,chain,mode,identity,time):
  trusted=directory/'trusted.pem';trusted.write_bytes(pem(anchor));leaf=directory/'leaf.pem';leaf.write_bytes(pem(chain[0]))
  command=['openssl','verify','-trusted',str(trusted),'-no-CAfile','-no-CApath','-no-CAstore','-attime',str(time),'-purpose','sslserver']
  if len(chain)>1:
   untrusted=directory/'untrusted.pem';untrusted.write_bytes(b''.join(pem(cert) for cert in chain[1:]));command+=['-untrusted',str(untrusted)]
  command+=['-verify_hostname' if mode=='dns' else '-verify_ip',identity,str(leaf)]
  result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
  return result.returncode==0,result.stdout+result.stderr
 def add(label,anchor,chain,status=0,mode='dns',identity='server.example',time=NOW,external=None):
  if external is not None:
   accepted,detail=oracle(anchor,chain,mode,identity,time);assert accepted==external,(label,accepted,detail)
  records.append((label,anchor,b''.join(chain),mode,identity,str(time),status))
 root_key,root_public=key('root');root=certificate('Root','Root',root_public,root_key,True)
 other_key,other_public=key('other-root');other=certificate('Other root','Other root',other_public,other_key,True)
 intermediate_key,intermediate_public=key('intermediate');intermediate=certificate('Intermediate','Root',intermediate_public,root_key,True)
 leaf_key,leaf_public=key('leaf');leaf=certificate('Leaf','Intermediate',leaf_public,intermediate_key)
 direct=certificate('Direct leaf','Root',leaf_public,root_key)
 add('direct',root,[direct],external=True);add('intermediate',root,[leaf,intermediate],external=True)
 add('included-root',root,[leaf,intermediate,root],external=True)
 add('ip4',root,[leaf,intermediate],mode='ip',identity='192.0.2.1',external=True)
 add('ip6',root,[leaf,intermediate],mode='ip',identity='2001:db8::1',external=True)
 add('dns-case',root,[leaf,intermediate],identity='SERVER.EXAMPLE',external=True)
 add('wrong-dns',root,[leaf,intermediate],5,identity='other.example',external=False)
 add('wrong-ip',root,[leaf,intermediate],5,mode='ip',identity='192.0.2.2',external=False)
 add('numeric-dns-is-not-ip',root,[leaf,intermediate],5,identity='192.0.2.1',external=False)
 add('expired',root,[leaf,intermediate],5,time='2272147200',external=False)
 add('not-yet-valid',root,[leaf,intermediate],5,time='1546300800',external=False)
 add('time-minimum',root,[leaf,intermediate],5,time='-62135596800')
 add('time-maximum',root,[leaf,intermediate],5,time='253402300799')
 add('wrong-anchor',other,[leaf,intermediate],5,external=False)
 add('missing-intermediate',root,[leaf],5,external=False)
 add('tampered-leaf',root,[leaf[:-1]+bytes([leaf[-1]^1]),intermediate],5,external=False)
 add('tampered-intermediate',root,[leaf,intermediate[:-1]+bytes([intermediate[-1]^1])],5,external=False)
 wildcard=certificate('Wildcard','Root',leaf_public,root_key,san=seq(tlv(130,b'*.wild.example')))
 add('wildcard',root,[wildcard],identity='one.wild.example',external=True)
 add('wildcard-depth',root,[wildcard],5,identity='two.one.wild.example',external=False)
 no_san=certificate('server.example','Root',leaf_public,root_key,san=None)
 add('no-cn-fallback',root,[no_san],5)
 add('out-of-order',root,[intermediate,leaf],5)
 add('duplicate-chain',root,[leaf,intermediate,intermediate],5)
 ca_leaf=certificate('CA leaf','Root',leaf_public,root_key,True);add('ca-leaf-without-digital-signature',root,[ca_leaf],5)
 wrong_usage=certificate('Bad usage','Root',leaf_public,root_key,usage=bits(b'\x04',2));add('leaf-key-usage',root,[wrong_usage],5,external=False)
 wrong_eku=certificate('Bad EKU','Root',leaf_public,root_key,eku=oid(1,3,6,1,5,5,7,3,2));add('leaf-eku',root,[wrong_eku],5,external=False)
 unknown=certificate('Unknown critical','Root',leaf_public,root_key,extra=[extension((1,2,3,4),tlv(5,b''),True)]);add('unknown-critical',root,[unknown],5,external=False)
 chain=[];parent='Root';signer=root_key
 for index in range(7):
  child_key,child_public=key('long-'+str(index));subject='CA '+str(index)
  child=certificate(subject,parent,child_public,signer,True);chain.append(child);parent=subject;signer=child_key
 long_leaf=certificate('Long leaf',parent,leaf_public,signer);long_chain=[long_leaf,*reversed(chain)]
 add('eight-certificates',root,long_chain,external=True)
 add('ninth-certificate',root,[*long_chain,root],7)
 historic_validity=seq(tlv(23,b'500101000000Z'),tlv(23,b'600101000000Z'))
 historic_root=certificate('Historical root','Historical root',root_public,root_key,True,validity=historic_validity)
 historic_leaf=certificate('Historical leaf','Historical root',leaf_public,root_key,validity=historic_validity)
 add('pre-epoch',historic_root,[historic_leaf],time='-473385600',external=True)
 for label,anchor,data in [('empty-anchor',b'',[direct]),('anchor-trailing',root+b'\0',[direct]),('empty-chain',root,[]),('chain-truncated',root,[leaf[:-1]]),('chain-trailing',root,[leaf,intermediate,b'\0']),('pem-input',root,[pem(direct)])]:add(label,anchor,data,5)
 # No certificate parsing starts before actual EOF. The same exact-cap raw
 # input is malformed, while one extra byte reaches the byte limit first.
 filler=bytes(MAX-len(root));add('input-exact-cap',root,[filler],5);add('input-excess',root,[filler,b'!'],7)
 add('anchor-exact-cap',bytes(MAX),[],5);add('anchor-excess',bytes(MAX)+b'!',[],7)
out=sys.stdout.buffer
for label,anchor,chain,mode,identity,time,status in records:
 values=[label.encode(),anchor,chain,mode.encode(),identity.encode(),time.encode()]
 out.write(struct.pack('<7I',*(len(value) for value in values),status)+b''.join(values))
"#;
fn corpus() -> &'static Vec<Case> {
    static CASES: OnceLock<Vec<Case>> = OnceLock::new();
    CASES.get_or_init(|| {
        let output = common::process_output_with_timeout(
            "OpenSSL signed chains and path/identity/time oracle",
            Command::new("python3").arg("-c").arg(CORPUS),
            Duration::from_secs(25),
        );
        assert!(output.status.success(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let mixed = common::process_output_with_timeout(
            "OpenSSL mixed issuer and leaf algorithms for the real application",
            Command::new("python3")
                .arg(root.join("tests/fixtures/extended/x509_path/mixed.py"))
                .arg("app"),
            Duration::from_secs(40),
        );
        assert!(mixed.status.success(), "{mixed:?}");
        assert!(mixed.stderr.is_empty(), "{mixed:?}");
        let mut bytes = output.stdout;
        bytes.extend(mixed.stdout);
        let mut at = 0;
        let mut records = Vec::new();
        while at < bytes.len() {
            let header = &bytes[at..at + 28];
            let word = |i: usize| {
                u32::from_le_bytes(header[i * 4..i * 4 + 4].try_into().unwrap()) as usize
            };
            let lengths = (0..6).map(word).collect::<Vec<_>>();
            let status = word(6) as i32;
            at += 28;
            let values = lengths
                .into_iter()
                .map(|length| {
                    let value = bytes[at..at + length].to_vec();
                    at += length;
                    value
                })
                .collect::<Vec<_>>();
            records.push(Case {
                name: String::from_utf8(values[0].clone()).unwrap(),
                anchor: values[1].clone(),
                chain: values[2].clone(),
                mode: String::from_utf8(values[3].clone()).unwrap(),
                identity: String::from_utf8(values[4].clone()).unwrap(),
                time: String::from_utf8(values[5].clone()).unwrap(),
                status,
            });
        }
        assert_eq!(at, bytes.len());
        records
    })
}
fn case(name: &str) -> &'static Case {
    corpus().iter().find(|case| case.name == name).unwrap()
}
fn arguments(anchor: &Path, case: &Case) -> Vec<OsString> {
    vec![
        anchor.as_os_str().to_owned(),
        case.mode.clone().into(),
        case.identity.clone().into(),
        case.time.clone().into(),
    ]
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
    let (arguments, value) = body.rsplit_once(" = ").unwrap();
    (arguments.trim_end().strip_suffix(')').unwrap(), value)
}
fn result<'a>(line: &'a str, name: &str) -> &'a str {
    fields(line, name).1.split_whitespace().next().unwrap()
}
fn fd(line: &str, name: &str) -> i32 {
    fields(line, name)
        .0
        .split(',')
        .next()
        .unwrap()
        .trim()
        .parse()
        .unwrap()
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
    opened: usize,
    closed: usize,
    anchor_reads: Vec<String>,
}
fn run(
    anchor_data: &[u8],
    chain_data: &[u8],
    args: impl FnOnce(&Path) -> Vec<OsString>,
    inject: &[&str],
    closed: bool,
    seconds: &str,
) -> Run {
    let anchor = common::TempArtifact::new("laniusc_verify_certificate", "anchor", None);
    anchor.write_bytes(anchor_data);
    let input = common::TempArtifact::new("laniusc_verify_certificate", "stdin", None);
    input.write_bytes(chain_data);
    let trace = common::TempArtifact::new("laniusc_verify_certificate", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", seconds, "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,openat,close,read,write,mmap,munmap,mremap,brk",
            "-e",
            "signal=none",
        ]);
    for rule in inject {
        command.arg("-e").arg(format!("inject={rule}"));
    }
    command
        .arg(executable().path())
        .args(args(anchor.path()))
        .stdin(fs::File::open(input.path()).unwrap());
    if closed {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    let output = if closed {
        // Preserve the supplied no-reader pipe: common's capture helper would
        // replace it. The external timeout still bounds the native process.
        command
            .output()
            .expect("bounded verify_certificate EPIPE case")
    } else {
        common::process_output_with_timeout(
            "verify_certificate native case",
            &mut command,
            Duration::from_secs(30),
        )
    };
    assert_eq!(
        fs::read(anchor.path()).unwrap(),
        anchor_data,
        "anchor changed"
    );
    assert_eq!(
        fs::read(input.path()).unwrap(),
        chain_data,
        "stdin file changed"
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    for rule in inject {
        let name = rule.split(':').next().unwrap();
        let reached = calls(&events, name)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
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
            assert!(
                reached
                    .iter()
                    .all(|line| result(line, name) == value.split(':').next().unwrap()),
                "{events}"
            );
        }
    }
    if inject.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let mut live = BTreeMap::<u64, usize>::new();
    let mut maps = 0;
    let mut released = 0;
    let mut failures = Vec::new();
    let mut owner = None;
    let mut opened = 0;
    let mut closed_count = 0;
    let mut anchor_reads = Vec::new();
    let mut reading = false;
    let mut publishing = false;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            assert!(!reading && !publishing, "late allocation: {events}");
            maps += 1;
            let (args, value) = fields(line, "mmap");
            let size = args.split(',').nth(1).unwrap().trim().parse().unwrap();
            if let Some(address) = value.split_whitespace().next().unwrap().strip_prefix("0x") {
                assert!(
                    live.insert(u64::from_str_radix(address, 16).unwrap(), size)
                        .is_none(),
                    "{events}"
                );
            } else {
                assert!(
                    value.contains("ENOMEM") && value.contains("INJECTED"),
                    "{events}"
                );
                failures.push(maps);
            }
        } else if line.starts_with("munmap(") {
            let (args, value) = fields(line, "munmap");
            assert_eq!(value, "0");
            let (address, size) = args.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            assert_eq!(
                live.remove(&address),
                Some(size.trim().parse().unwrap()),
                "unknown/wrong/double release: {events}"
            );
            released += 1;
        } else if line.starts_with("openat(") {
            assert!(
                !reading && !publishing && owner.is_none(),
                "anchor must open before input: {events}"
            );
            for flag in ["O_RDONLY", "O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC"] {
                assert!(line.contains(flag), "{events}");
            }
            for flag in ["O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC"] {
                assert!(!line.contains(flag), "{events}");
            }
            let value = result(line, "openat").parse::<i32>().unwrap();
            if value >= 0 {
                assert_eq!(opened, 0);
                assert!(value > 2);
                owner = Some(value);
                opened += 1;
            }
        } else if line.starts_with("close(") {
            let (args, value) = fields(line, "close");
            assert_eq!(
                owner.take(),
                Some(args.parse::<i32>().unwrap()),
                "unknown/double close: {events}"
            );
            assert!(
                value == "0" || (value.starts_with("-1") && value.contains("INJECTED")),
                "{events}"
            );
            closed_count += 1;
        } else if line.starts_with("read(") {
            reading = true;
            let descriptor = fd(line, "read");
            if descriptor == 0 {
                assert!(
                    owner.is_none(),
                    "anchor owner must retire before stdin: {events}"
                );
            } else {
                assert_eq!(
                    owner,
                    Some(descriptor),
                    "unknown input descriptor: {events}"
                );
                anchor_reads.push(line.to_owned());
            }
        } else if line.starts_with("write(") {
            publishing = true;
            assert_eq!(fd(line, "write"), 1);
            assert!(
                owner.is_none() && live.is_empty(),
                "all owners must retire before publication: {events}"
            );
        }
        for forbidden in ["mremap(", "brk("] {
            assert!(
                !line.starts_with(forbidden),
                "unexpected native storage operation: {events}"
            );
        }
    }
    assert!(owner.is_none() && live.is_empty(), "leaked owner: {events}");
    assert_eq!(closed_count, opened);
    assert_eq!(released, maps - failures.len());
    Run {
        output,
        events,
        maps,
        failures,
        opened,
        closed: closed_count,
        anchor_reads,
    }
}
fn stdin_reads(run: &Run) -> Vec<&str> {
    calls(&run.events, "read")
        .into_iter()
        .filter(|line| fd(line, "read") == 0)
        .collect()
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
    let signals = calls(&run.events, "rt_sigaction");
    assert_eq!(signals.len(), usize::from(signal));
    if signal {
        assert!(signals[0].contains("SIGPIPE") && signals[0].contains("SIG_IGN"));
        if !signals[0].contains("INJECTED") {
            assert_eq!(result(signals[0], "rt_sigaction"), "0");
        }
    }
    let reads = calls(&run.events, "read");
    let writes = calls(&run.events, "write");
    assert!(reads.len() + writes.len() <= CALLS);
    for line in &reads {
        assert!((1..=1024).contains(&request(line, "read")));
    }
    for line in &writes {
        assert!((1..=9).contains(&request(line, "write")));
    }
    if eof || !writes.is_empty() {
        let input = stdin_reads(run);
        assert_eq!(
            result(input.last().expect("stdin EOF required"), "read"),
            "0"
        );
        assert_eq!(
            result(
                run.anchor_reads.last().expect("anchor EOF required"),
                "read"
            ),
            "0"
        );
    }
    if let Some(first_write) = run
        .events
        .lines()
        .position(|line| line.starts_with("write("))
    {
        let last_read = run
            .events
            .lines()
            .enumerate()
            .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
            .last()
            .unwrap();
        assert!(last_read < first_write, "{}", run.events);
    }
    if matches!(status, 2 | 4 | 5) {
        assert!(writes.is_empty());
    }
    if !signal {
        assert!(reads.is_empty() && writes.is_empty() && run.opened == 0);
    }
    assert!(run.maps <= 3);
    assert_eq!(run.closed, run.opened);
}
#[test]
fn verify_certificate_signed_paths_identity_time_and_cli() {
    let mut count = 0;
    for case in corpus()
        .iter()
        .filter(|case| !case.name.contains("cap") && !case.name.contains("excess"))
    {
        let observed = run(
            &case.anchor,
            &case.chain,
            |path| arguments(path, case),
            &[],
            false,
            "8s",
        );
        assert_eq!(
            observed.output.status.code(),
            Some(case.status),
            "case {}: {:?}\n{}",
            case.name,
            observed.output,
            observed.events
        );
        checked(
            &observed,
            case.status,
            if case.status == 0 { b"verified\n" } else { b"" },
            true,
            true,
        );
        assert_eq!(observed.opened, 1);
        assert_eq!(observed.maps, 3);
        count += 1;
    }
    let base = case("direct");
    let invalid = vec![
        vec![],
        vec!["anchor".into()],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "1704067200".into(),
            "extra".into(),
        ],
        vec![
            "".into(),
            "dns".into(),
            "server.example".into(),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "auto".into(),
            "server.example".into(),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "*.example".into(),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            OsString::from_vec(vec![255]),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "ip".into(),
            "192.00.2.1".into(),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "ip".into(),
            "fe80::1%1".into(),
            "1704067200".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "+1".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "-62135596801".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "253402300800".into(),
        ],
        vec![
            "anchor".into(),
            "dns".into(),
            "server.example".into(),
            "99999999999999999999".into(),
        ],
        vec![
            "x".repeat(4096).into(),
            "dns".into(),
            "server.example".into(),
            "1704067200".into(),
        ],
    ];
    for args in invalid {
        let observed = run(&base.anchor, &base.chain, |_| args, &[], false, "5s");
        checked(&observed, 2, b"", false, false);
        count += 1;
    }
    eprintln!(
        "verify_certificate ordinary: one shared strictELF,{count} native cases,OpenSSL signed direct/intermediate/eight-certificate paths,explicit DNS/IP and signed UTC,exact DER framing and CLI preflight"
    );
}
#[test]
fn verify_certificate_owners_descriptors_partial_io_and_faults() {
    let base = case("direct");
    let baseline = run(
        &base.anchor,
        &base.chain,
        |path| arguments(path, base),
        &[],
        false,
        "5s",
    );
    checked(&baseline, 0, b"verified\n", true, true);
    assert_eq!(baseline.maps, 3);
    assert_eq!(baseline.opened, 1);
    let mut count = 1;
    for ordinal in 1..=baseline.maps {
        let rule = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(
            &base.anchor,
            &base.chain,
            |path| arguments(path, base),
            &[&rule],
            false,
            "5s",
        );
        checked(&observed, 4, b"", ordinal == 3, false);
        assert_eq!(observed.failures, vec![ordinal]);
        assert_eq!(observed.opened, 0);
        assert!(calls(&observed.events, "read").is_empty());
        count += 1;
    }
    for (rule, status, wanted, eof) in [
        ("openat:error=EIO:when=1", 3, b"".as_slice(), false),
        ("openat:error=EINTR:when=1", 3, b"", false),
        ("read:error=EIO:when=1", 3, b"", false),
        ("read:error=EAGAIN:when=1", 3, b"", false),
        ("read:retval=1025:when=1", 3, b"", false),
        ("read:error=EINTR:when=1", 0, b"verified\n", true),
        ("read:error=EINTR:when=2", 0, b"verified\n", true),
        ("read:error=EIO:when=3", 3, b"", false),
        ("read:error=EINTR:when=3", 0, b"verified\n", true),
        ("close:error=EIO:when=1", 3, b"", false),
        ("close:error=EINTR:when=1", 3, b"", false),
        ("write:error=EIO:when=1", 3, b"", true),
        ("write:error=EAGAIN:when=1", 3, b"", true),
        ("write:retval=0:when=1", 3, b"", true),
        ("write:retval=10:when=1", 3, b"", true),
        ("write:error=EINTR:when=1", 0, b"verified\n", true),
        ("write:retval=1:when=1", 0, b"erified\n", true),
    ] {
        let observed = run(
            &base.anchor,
            &base.chain,
            |path| arguments(path, base),
            &[rule],
            false,
            "5s",
        );
        checked(&observed, status, wanted, true, eof);
        if rule.starts_with("close:") {
            assert!(stdin_reads(&observed).is_empty());
            assert_eq!(calls(&observed.events, "close").len(), 1);
        }
        if rule == "write:retval=1:when=1" {
            let writes = calls(&observed.events, "write");
            assert_eq!(writes.len(), 2);
            assert_eq!(request(writes[1], "write"), 8);
        }
        count += 1;
    }
    let rule = format!(
        "read:retval=1:poke_exit=@arg2={:02x}:when=1",
        base.anchor[0]
    );
    let observed = run(
        &base.anchor[1..],
        &base.chain,
        |path| arguments(path, base),
        &[&rule],
        false,
        "5s",
    );
    checked(&observed, 0, b"verified\n", true, true);
    count += 1;
    let observed = run(
        &base.anchor,
        &base.chain,
        |path| arguments(path, base),
        &[],
        true,
        "5s",
    );
    checked(&observed, 3, b"", true, true);
    let writes = calls(&observed.events, "write");
    assert!(writes[0].contains("EPIPE") && !writes[0].contains("INJECTED"));
    count += 1;
    let observed = run(
        &base.anchor,
        &base.chain,
        |path| arguments(path, base),
        &["rt_sigaction:error=EINTR:when=1"],
        false,
        "5s",
    );
    checked(&observed, 3, b"", true, false);
    assert_eq!(observed.maps, 2);
    assert_eq!(observed.opened, 0);
    count += 1;
    let observed = run(
        &base.anchor,
        &base.chain,
        |path| arguments(path, base),
        &["read:error=EIO:when=1", "close:error=EINTR:when=1"],
        false,
        "5s",
    );
    checked(&observed, 3, b"", true, false);
    assert!(stdin_reads(&observed).is_empty());
    count += 1;
    let missing = common::TempArtifact::new("laniusc_verify_certificate", "missing", None);
    let observed = run(
        &base.anchor,
        &base.chain,
        |_| arguments(missing.path(), base),
        &[],
        false,
        "5s",
    );
    checked(&observed, 3, b"", true, false);
    assert_eq!(observed.opened, 0);
    count += 1;
    let target = common::TempArtifact::new("laniusc_verify_certificate", "symlink_target", None);
    target.write_bytes(&base.anchor);
    let link = common::TempArtifact::new("laniusc_verify_certificate", "symlink", None);
    std::os::unix::fs::symlink(target.path(), link.path()).unwrap();
    let observed = run(
        &base.anchor,
        &base.chain,
        |_| arguments(link.path(), base),
        &[],
        false,
        "5s",
    );
    checked(&observed, 3, b"", true, false);
    assert_eq!(observed.opened, 0);
    assert_eq!(fs::read(target.path()).unwrap(), base.anchor);
    let opens = calls(&observed.events, "openat");
    assert!(opens[0].contains("ELOOP") && !opens[0].contains("INJECTED"));
    count += 1;
    eprintln!(
        "verify_certificate cleanup:{count} native cases,every reached allocation denial,exact owner/descriptor retirement,read/write retry and reported-progress controls,actual EPIPE and nofollow open"
    );
}
#[test]
fn verify_certificate_cumulative_caps_eof_and_shared_io_budget() {
    let mut count = 0;
    for name in [
        "input-exact-cap",
        "input-excess",
        "anchor-exact-cap",
        "anchor-excess",
    ] {
        let case = case(name);
        let observed = run(
            &case.anchor,
            &case.chain,
            |path| arguments(path, case),
            &[],
            false,
            "15s",
        );
        checked(
            &observed,
            case.status,
            b"",
            true,
            name != "input-excess" && name != "anchor-excess",
        );
        assert!(calls(&observed.events, "write").is_empty());
        let received: usize = calls(&observed.events, "read")
            .into_iter()
            .map(|line| result(line, "read").parse::<usize>().unwrap())
            .sum();
        assert_eq!(received, MAX + usize::from(name.ends_with("excess")));
        if name.starts_with("input-") {
            let reads = stdin_reads(&observed);
            assert_eq!(request(reads.last().unwrap(), "read"), 1);
            assert_eq!(
                result(reads.last().unwrap(), "read"),
                if name == "input-excess" { "1" } else { "0" }
            );
        } else {
            let reads = &observed.anchor_reads;
            assert_eq!(request(reads.last().unwrap(), "read"), 1);
            assert_eq!(
                result(reads.last().unwrap(), "read"),
                if name == "anchor-excess" { "1" } else { "0" }
            );
            assert_eq!(reads.len(), MAX / 1024 + 1);
            if name == "anchor-excess" {
                assert!(stdin_reads(&observed).is_empty());
            }
        }
        count += 1;
    }
    let base = case("direct");
    for rule in ["read:error=EINTR:when=1+", "write:error=EINTR:when=1+"] {
        let observed = run(
            &base.anchor,
            &base.chain,
            |path| arguments(path, base),
            &[rule],
            false,
            "20s",
        );
        checked(&observed, 7, b"", true, rule.starts_with("write:"));
        let reads = calls(&observed.events, "read").len();
        let writes = calls(&observed.events, "write").len();
        assert_eq!(reads + writes, CALLS);
        if rule.starts_with("read:") {
            assert_eq!(writes, 0);
            assert!(stdin_reads(&observed).is_empty());
            assert_eq!(observed.closed, 1);
        } else {
            assert!(reads > 0 && writes == CALLS - reads);
        }
        count += 1;
    }
    let observed = run(
        &base.anchor,
        &base.chain,
        |path| arguments(path, base),
        &["read:error=EINTR:when=1+", "close:error=EIO:when=1"],
        false,
        "20s",
    );
    checked(&observed, 3, b"", true, false);
    assert_eq!(calls(&observed.events, "read").len(), CALLS);
    assert!(stdin_reads(&observed).is_empty());
    count += 1;
    eprintln!(
        "verify_certificate limits:{count} native cases,cumulative1MiB anchor+peer cap and actual one-byte probes,shared131072 read/write attempts,close failure overrides exhausted budget"
    );
}
