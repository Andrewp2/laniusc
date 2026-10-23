#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_net", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(path: &str, input: &[u8], no_heap: bool) -> Vec<u8> {
    let exe = executable(path);
    let data = common::TempArtifact::new("laniusc_net", "input", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_net", "trace", None);
    let mut c = Command::new("strace");
    c.args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if no_heap {
        c.args(["-e", "inject=mmap:error=ENOMEM:when=1+"]);
    }
    c.arg(exe.path())
        .stdin(std::fs::File::open(data.path()).unwrap());
    let out = common::process_output_with_timeout(
        "network values native runtime",
        &mut c,
        Duration::from_secs(25),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    if no_heap {
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    }
    out.stdout
}
#[test]
fn network_values_contracts_execute_strides_bounds_atomicity_masks_full_width_and_no_allocation() {
    assert!(
        run(
            "tests/fixtures/stdlib_foundation/net_contracts.lani",
            b"",
            true
        )
        .is_empty()
    );
}
#[test]
fn network_values_are_real_generic_map_keys_and_sortable_full_width_values() {
    assert!(
        run(
            "tests/fixtures/stdlib_foundation/net_collections.lani",
            b"",
            false
        )
        .is_empty()
    );
}
#[test]
fn network_prefix_membership_overlap_every_width_and_ipv6_wire_views_execute_without_heap() {
    assert!(
        run(
            "tests/fixtures/stdlib_foundation/net_prefixes.lani",
            b"",
            true
        )
        .is_empty()
    );
}
fn number(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}
fn frame(mode: u32, source: &[u8], capacity: u32) -> Vec<u8> {
    let mut b = Vec::new();
    b.extend_from_slice(&mode.to_le_bytes());
    b.extend_from_slice(&(source.len() as u32).to_le_bytes());
    b.extend_from_slice(&capacity.to_le_bytes());
    b.extend_from_slice(source);
    b
}
fn records(bytes: &[u8], count: usize) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut p = 0;
    for _ in 0..count {
        let text = number(bytes, p + 4) as usize;
        let wire = number(bytes, p + 8) as usize;
        let parts = number(bytes, p + 32) as usize;
        let n = 40 + text + wire * parts;
        out.push(bytes[p..p + n].to_vec());
        p += n;
    }
    assert_eq!(p, bytes.len());
    out
}

#[test]
fn network_addresses_sockets_and_every_cidr_width_match_python_ipaddress_and_wire_models() {
    let script = r#"
import ipaddress as ip,random,struct,sys,socket
r=random.Random(0x5952)
def canon(a):return '::ffff:'+str(a.ipv4_mapped) if a.version==6 and a.ipv4_mapped is not None else str(a)
def fnv(b):
 h=2166136261
 for n in b:h=((h^n)*16777619)&0xffffffff
 return h
def word(n):return struct.pack('>I',n)
def emit(mode,s,capacity=80):
 scope=port=0;prefix=0xffffffff;parts=1
 if mode<=2:a=ip.ip_address(s);assert mode==0 or a.version==[0,4,6][mode];text=canon(a);data=a.packed;h=fnv(bytes([a.version])+data)
 elif mode==3:
  base,_,zone=s.partition('%');a=ip.IPv6Address(base);scope=int(zone) if zone else 0;text=canon(a)+('%'+str(scope) if scope else '');data=a.packed;h=fnv(data+word(scope))
 elif mode==4:
  if s.startswith('['):base,rest=s[1:].split(']');base,_,zone=base.partition('%');a=ip.IPv6Address(base);scope=int(zone) if zone else 0;port=int(rest[1:]);text='['+canon(a)+('%'+str(scope) if scope else '')+']:'+str(port)
  else:base,p=s.split(':');a=ip.IPv4Address(base);port=int(p);text=canon(a)+':'+str(port)
  data=a.packed;h=fnv(data+word(port)+(word(scope) if a.version==6 else b'')+bytes([a.version]))
 else:
  net=ip.ip_network(s,strict=mode==5);a=net.network_address;prefix=net.prefixlen;text=canon(a)+'/'+str(prefix);parts=4;data=a.packed+net.broadcast_address.packed+net.netmask.packed+net.hostmask.packed;h=fnv(a.packed+bytes([prefix,a.version]))
 n=int(a);v=a.version
 flags=(1 if n==0 else 0)|(2 if (n>>24==127 if v==4 else n==1) else 0)|(4 if (n>>28==14 if v==4 else n>>120==255) else 0)|(8 if (n>>16==0xa9fe if v==4 else n>>118==0x3fa) else 0)|(16 if ((n>>24==10 or n>>20==0xac1 or n>>16==0xc0a8) if v==4 else n>>121==0x7e) else 0)|(32 if v==4 and n==0xffffffff else 0)
 encoded=text.encode();error=0
 if len(encoded)>capacity:error=10;encoded=b''
 expected=struct.pack('<10I',error,len(encoded),4 if v==4 else 16,v,prefix,scope,port,h,parts,flags)+encoded+data
 source=s.encode();request=struct.pack('<III',mode,len(source),capacity)+source
 sys.stdout.buffer.write(struct.pack('<II',len(request),len(expected))+request+expected)
for s in ['0.0.0.0','255.255.255.255','127.255.0.1','169.254.0.1','172.16.0.1','172.31.255.255','172.32.0.0','192.168.0.1','::','::1','::ffff:0.0.0.0','::ffff:255.255.255.255','1:0:0:2:0:0:3:4','0:0:1:0:0:2:3:4','1:2:3:4:5:6:0:8','ff02::1','fe80::1','fc00::1','2001:DB8:0000:0000:0000:0000:0000:0001']:
 for mode in [0,1 if ':' not in s else 2]:
  emit(mode,s)
  for cap in [0,len(canon(ip.ip_address(s)))-1,len(canon(ip.ip_address(s)))]:emit(mode,s,cap)
for i in range(3072):
 v=4 if i%3==0 else 6;a=ip.ip_address(r.getrandbits(32)) if v==4 else ip.IPv6Address(r.getrandbits(128))
 if v==6 and i%4==0:
  seg=[r.randrange(65536) for _ in range(8)];start=r.randrange(8);end=r.randrange(start+1,9);seg[start:end]=[0]*(end-start);a=ip.IPv6Address(':'.join(format(n,'x') for n in seg))
 forms=[str(a)] if v==4 else [str(a),a.exploded,a.exploded.upper()]
 for text in forms:emit(0,text)
 if v==6 and i%5==0:emit(3,str(a)+'%'+str(r.getrandbits(32)))
 if i%4==0:
  port=r.randrange(65536);zone=r.getrandbits(32) if v==6 and i%8==0 else 0
  emit(4,(str(a)+':'+str(port)) if v==4 else '['+str(a)+('%'+str(zone) if zone else '')+']:'+str(port))
for v in [4,6]:
 width=32 if v==4 else 128
 for prefix in range(width+1):
  for j in range(12):
   a=ip.IPv4Address(r.getrandbits(32)) if v==4 else ip.IPv6Address(r.getrandbits(128));net=ip.ip_network(str(a)+'/'+str(prefix),strict=False)
   emit(5,str(net));emit(6,str(a)+'/'+str(prefix))
for base in ['::','::ffff:','2001:db8::']:
 for last in ['0.0.0.0','192.0.2.1','255.255.255.255']:
  s=base+last;emit(2,s);a=ip.IPv6Address(s);assert socket.inet_pton(socket.AF_INET6,s)==a.packed
for s in ['[::%0]:0','[fe80::1%00042]:00080','[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff%4294967295]:65535','1.2.3.4:00080']:emit(4,s)
"#;
    let py = common::process_output_with_timeout(
        "Python network value reference corpus",
        Command::new("python3").args(["-c", script]),
        Duration::from_secs(15),
    );
    assert!(py.status.success(), "{py:?}");
    let mut p = 0;
    let mut input = Vec::new();
    let mut expected = Vec::new();
    while p < py.stdout.len() {
        let request = number(&py.stdout, p) as usize;
        let result = number(&py.stdout, p + 4) as usize;
        p += 8;
        input.extend_from_slice(&py.stdout[p..p + request]);
        p += request;
        expected.push(py.stdout[p..p + result].to_vec());
        p += result;
    }
    assert!(expected.len() > 10000);
    let actual = records(
        &run(
            "tests/fixtures/stdlib_foundation/net_model.lani",
            &input,
            true,
        ),
        expected.len(),
    );
    for (index, (actual, expected)) in actual.iter().zip(expected).enumerate() {
        assert_eq!(*actual, expected, "case {index}");
    }
}

#[test]
fn network_parsers_reject_legacy_ipv4_malformed_ipv6_ports_named_zones_cidr_host_bits_and_binary_junk()
 {
    let mut cases = Vec::new();
    let mut add = |mode: u32, s: &[u8]| cases.push(frame(mode, s, 80));
    for s in [
        b"".as_slice(),
        b"1",
        b"127.1",
        b"1.2.3",
        b"1.2.3.4.5",
        b"256.1.1.1",
        b"01.2.3.4",
        b"1.02.3.4",
        b"0x7f.0.0.1",
        b"0177.0.0.1",
        b"+1.2.3.4",
        b"1.2.3.-1",
        b" 1.2.3.4",
        b"1.2.3.4\n",
        b"1.2.3.4/24",
    ] {
        add(1, s);
    }
    for s in [
        b"".as_slice(),
        b":",
        b":::1",
        b"1:::2",
        b"1::2::3",
        b"1:2:3:4:5:6:7",
        b"1:2:3:4:5:6:7:8:9",
        b"1:2:3:4:5:6:7:8::",
        b"12345::",
        b"gggg::",
        b"::ffff:192.0.02.1",
        b"::ffff:1.2.3",
        b"[::1]",
        b"fe80::1%1",
        b"::1\0",
        b"::1 ",
    ] {
        add(2, s);
    }
    for s in [
        b"1.2.3.4".as_slice(),
        b"localhost:80",
        b"::1:80",
        b"[::1]",
        b"[::1]:",
        b"[::1]:65536",
        b"1.2.3.4:65536",
        b"1.2.3.4:-1",
        b"1.2.3.4:+1",
        b"[fe80::1%eth0]:80",
        b"[fe80::1%4294967296]:80",
        b"[fe80::1%]:80",
        b"[::1]x:80",
        b"[1.2.3.4]:80",
        b"[v1.foo]:80",
    ] {
        add(4, s);
    }
    for s in [
        b"fe80::1%".as_slice(),
        b"fe80::1%eth0",
        b"fe80::1%1%2",
        b"fe80::1%-1",
        b"fe80::1%4294967296",
        b"1.2.3.4%1",
    ] {
        add(3, s);
    }
    for s in [
        b"1.2.3.4/24".as_slice(),
        b"2001:db8::1/64",
        b"1.2.3.4/33",
        b"::/129",
        b"1.2.3.4/",
        b"::/-1",
        b"::/+1",
        b"::/32/64",
        b"1.2.3.4",
        b"::/0.0.0.0",
        b"fe80::%1/64",
    ] {
        add(5, s);
    }
    for octet in 0..=255u8 {
        let mut v = b"1.2.3.255".to_vec();
        v.push(octet);
        add(1, &v);
        let mut v = b"ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff".to_vec();
        v.push(octet);
        add(2, &v);
    }
    for n in 0..256u32 {
        let v = format!("{:03}.2.3.4", n);
        if n < 100 {
            add(1, v.as_bytes());
        }
    }
    let mut input = Vec::new();
    for c in &cases {
        input.extend_from_slice(c);
    }
    let out = records(
        &run(
            "tests/fixtures/stdlib_foundation/net_model.lani",
            &input,
            true,
        ),
        cases.len(),
    );
    for (index, result) in out.iter().enumerate() {
        assert_ne!(number(result, 0), 0, "case{index}: {:?}", cases[index]);
        assert_eq!(number(result, 4), 0);
        assert_eq!(number(result, 8), 0);
    }
}
