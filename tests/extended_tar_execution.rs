#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_tar", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(path: &str, input: &[u8]) -> Vec<u8> {
    let exe = executable(path);
    let data = common::TempArtifact::new("laniusc_tar", "input", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tar", "trace", None);
    let out = common::process_output_with_timeout(
        "tar native execution",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::fs::File::open(data.path()).unwrap()),
        Duration::from_secs(25),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    out.stdout
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Member {
    path: Vec<u8>,
    link: Vec<u8>,
    uname: Vec<u8>,
    gname: Vec<u8>,
    data: Vec<u8>,
    kind: u32,
    mode: u32,
    uid: u64,
    gid: u64,
    mtime: u64,
    major: u64,
    minor: u64,
}
fn regular(path: &[u8], data: &[u8]) -> Member {
    Member {
        path: path.to_vec(),
        link: vec![],
        uname: vec![],
        gname: vec![],
        data: data.to_vec(),
        kind: 0,
        mode: 0o644,
        uid: 0,
        gid: 0,
        mtime: 0,
        major: 0,
        minor: 0,
    }
}
fn member_protocol(m: &Member, out: &mut Vec<u8>) {
    out.extend_from_slice(&m.kind.to_le_bytes());
    out.extend_from_slice(&m.mode.to_le_bytes());
    for n in [m.uid, m.gid, m.mtime, m.major, m.minor] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    for n in [
        m.path.len(),
        m.link.len(),
        m.uname.len(),
        m.gname.len(),
        m.data.len(),
    ] {
        out.extend_from_slice(&(n as u32).to_le_bytes());
    }
    for b in [&m.path, &m.link, &m.uname, &m.gname, &m.data] {
        out.extend_from_slice(b);
    }
}
fn protocol(members: &[Member]) -> Vec<u8> {
    let mut out = Vec::new();
    for m in members {
        member_protocol(m, &mut out);
    }
    out
}
fn checksum(header: &mut [u8]) {
    header[148..156].fill(b' ');
    let sum = header.iter().map(|&n| n as u32).sum::<u32>();
    header[148..154].copy_from_slice(format!("{sum:06o}").as_bytes());
    header[154] = 0;
    header[155] = 32;
}
fn octal(header: &mut [u8], start: usize, width: usize, value: u64) {
    let s = format!("{value:0digits$o}", digits = width - 1);
    assert_eq!(s.len(), width - 1);
    header[start..start + width - 1].copy_from_slice(s.as_bytes());
}
fn canonical_member(m: &Member) -> Vec<u8> {
    let mut h = vec![0; 512];
    if m.path.len() <= 100 {
        h[..m.path.len()].copy_from_slice(&m.path);
    } else {
        let split = (1..m.path.len())
            .rev()
            .find(|&i| m.path[i] == b'/' && i <= 155 && m.path.len() - i - 1 <= 100)
            .unwrap();
        h[..m.path.len() - split - 1].copy_from_slice(&m.path[split + 1..]);
        h[345..345 + split].copy_from_slice(&m.path[..split]);
    }
    octal(&mut h, 100, 8, m.mode as u64);
    octal(&mut h, 108, 8, m.uid);
    octal(&mut h, 116, 8, m.gid);
    octal(&mut h, 124, 12, m.data.len() as u64);
    octal(&mut h, 136, 12, m.mtime);
    h[156] = b'0' + m.kind as u8;
    h[157..157 + m.link.len()].copy_from_slice(&m.link);
    h[257..263].copy_from_slice(b"ustar\0");
    h[263..265].copy_from_slice(b"00");
    h[265..265 + m.uname.len()].copy_from_slice(&m.uname);
    h[297..297 + m.gname.len()].copy_from_slice(&m.gname);
    octal(&mut h, 329, 8, m.major);
    octal(&mut h, 337, 8, m.minor);
    checksum(&mut h);
    h.extend_from_slice(&m.data);
    h.resize(h.len().div_ceil(512) * 512, 0);
    h
}
fn archive(members: &[Member]) -> Vec<u8> {
    let mut b = Vec::new();
    for m in members {
        b.extend(canonical_member(m));
    }
    b.resize(b.len() + 1024, 0);
    b
}
fn python(script: &str, input: &[u8]) -> Vec<u8> {
    let data = common::TempArtifact::new("laniusc_tar", "python-input", None);
    data.write_bytes(input);
    let out = common::process_output_with_timeout(
        "Python tarfile interoperability",
        Command::new("python3")
            .args(["-c", script])
            .stdin(std::fs::File::open(data.path()).unwrap()),
        Duration::from_secs(15),
    );
    assert!(out.status.success(), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    out.stdout
}
fn python_archive(members: &[Member]) -> Vec<u8> {
    python(
        r#"
import io,struct,sys,tarfile
b=sys.stdin.buffer.read();p=0;out=io.BytesIO()
with tarfile.open(fileobj=out,mode='w',format=tarfile.USTAR_FORMAT,encoding='utf-8',errors='surrogateescape') as t:
 while p<len(b):
  kind,mode,uid,gid,mtime,major,minor,*sizes=struct.unpack_from('<IIQQQQQIIIII',b,p);p+=68
  chunks=[]
  for n in sizes:chunks.append(b[p:p+n]);p+=n
  path,link,uname,gname,data=chunks
  i=tarfile.TarInfo(path.decode('utf-8','surrogateescape'));i.type=bytes([48+kind]);i.mode=mode;i.uid=uid;i.gid=gid;i.mtime=mtime;i.devmajor=major;i.devminor=minor;i.linkname=link.decode('utf-8','surrogateescape');i.uname=uname.decode('utf-8','surrogateescape');i.gname=gname.decode('utf-8','surrogateescape');i.size=len(data);t.addfile(i,io.BytesIO(data))
sys.stdout.buffer.write(out.getvalue())
"#,
        &protocol(members),
    )
}

#[derive(Debug)]
struct ReadResult {
    members: Vec<Member>,
    sizes: Vec<u64>,
    offsets: Vec<usize>,
    code: i32,
    position: usize,
    finished: bool,
}
fn integer(bytes: &[u8], p: usize) -> u32 {
    u32::from_le_bytes(bytes[p..p + 4].try_into().unwrap())
}
fn wide(bytes: &[u8], p: usize) -> u64 {
    u64::from_le_bytes(bytes[p..p + 8].try_into().unwrap())
}
fn read_archives(archives: &[Vec<u8>]) -> Vec<ReadResult> {
    let mut input = Vec::new();
    for b in archives {
        assert!(b.len() <= 262144);
        input.extend_from_slice(&(b.len() as u32).to_le_bytes());
        input.extend_from_slice(b);
    }
    let bytes = run("tests/fixtures/extended/tar_read.lani", &input);
    let mut p = 0;
    let mut out = Vec::new();
    for _ in archives {
        let mut result = ReadResult {
            members: vec![],
            sizes: vec![],
            offsets: vec![],
            code: 0,
            position: 0,
            finished: false,
        };
        loop {
            let tag = integer(&bytes, p);
            if tag == 0 {
                result.code = integer(&bytes, p + 4) as i32;
                result.position = integer(&bytes, p + 8) as usize;
                result.finished = integer(&bytes, p + 12) != 0;
                p += 16;
                break;
            }
            assert_eq!(tag, 1);
            let mut m = regular(b"", b"");
            m.kind = integer(&bytes, p + 4);
            m.mode = integer(&bytes, p + 8);
            m.uid = wide(&bytes, p + 12);
            m.gid = wide(&bytes, p + 20);
            result.sizes.push(wide(&bytes, p + 28));
            m.mtime = wide(&bytes, p + 36);
            m.major = wide(&bytes, p + 44);
            m.minor = wide(&bytes, p + 52);
            result.offsets.push(integer(&bytes, p + 60) as usize);
            let lens = [64, 68, 72, 76, 80].map(|n| integer(&bytes, p + n) as usize);
            p += 84;
            let mut chunks = Vec::new();
            for n in lens {
                chunks.push(bytes[p..p + n].to_vec());
                p += n;
            }
            m.path = chunks.remove(0);
            m.link = chunks.remove(0);
            m.uname = chunks.remove(0);
            m.gname = chunks.remove(0);
            m.data = chunks.remove(0);
            result.members.push(m);
        }
        out.push(result);
    }
    assert_eq!(p, bytes.len());
    out
}
#[test]
fn tar_contracts_execute_offsets_strides_wide_metadata_retryable_finish_bounds_and_atomic_failures_without_heap()
 {
    assert!(run("tests/fixtures/extended/tar_contracts.lani", b"").is_empty());
    assert!(run("tests/fixtures/extended/tar_strides.lani", b"").is_empty());
}

#[test]
fn tar_reads_python_ustar_every_kind_byte_paths_boundary_prefixes_numeric_limits_and_large_members()
{
    let mut members = vec![regular(b"a", b"\0\xffhello")];
    members[0].uid = 2097151;
    members[0].gid = 2097151;
    members[0].mtime = 8589934591;
    members[0].mode = 4095;
    members[0].uname = vec![b'u'; 31];
    members[0].gname = vec![b'g'; 31];
    for kind in 1..=7 {
        let mut m = regular(
            format!("kind-{kind}{}", if kind == 5 { "/" } else { "" }).as_bytes(),
            b"",
        );
        m.kind = kind;
        if kind == 1 {
            m.link = b"a".to_vec();
        }
        if kind == 2 {
            m.link = b"../outside/\xff".to_vec();
        }
        if kind == 3 || kind == 4 {
            m.major = 2097151;
            m.minor = 123;
        }
        if kind == 7 {
            m.data = b"contiguous".to_vec();
        }
        members.push(m);
    }
    for length in [99, 100] {
        members.push(regular(&vec![b'n'; length], b"x"));
    }
    let mut long = vec![b'p'; 155];
    long.push(b'/');
    long.extend_from_slice(&[b'n'; 100]);
    members.push(regular(&long, b"max"));
    members.push(regular(b"raw/\xff\x80\n.././file", &[0, 255, 128, 0]));
    members.push(regular(
        b"large",
        &(0..131073)
            .map(|i| ((i * 31 + i / 11) % 256) as u8)
            .collect::<Vec<_>>(),
    ));
    let bytes = python_archive(&members);
    let result = read_archives(&[bytes.clone()]).remove(0);
    assert_eq!(result.code, 0, "{result:?}");
    assert_eq!(result.members, members);
    assert_eq!(result.position, bytes.len());
    assert!(result.finished);
    let mut offset = 0;
    for (i, m) in members.iter().enumerate() {
        assert_eq!(result.sizes[i], m.data.len() as u64);
        assert_eq!(result.offsets[i], offset);
        offset += 512 + m.data.len().div_ceil(512) * 512;
    }
}

#[test]
fn tar_reader_rejects_corruption_extensions_bad_fields_data_padding_and_every_truncated_prefix() {
    let m = regular(b"a", b"\0\xff");
    let good = archive(&[m.clone()]);
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for n in 0..good.len() {
        cases.push(good[..n].to_vec());
        expected.push(None);
    }
    let mut add = |mut b: Vec<u8>, offset: usize, value: u8, error: i32, rechecksum: bool| {
        b[offset] = value;
        if rechecksum {
            checksum(&mut b[..512]);
        }
        cases.push(b);
        expected.push(Some(error));
    };
    add(good.clone(), 0, b'b', 4, false);
    add(good.clone(), 257, b'X', 5, true);
    add(good.clone(), 263, b'1', 5, true);
    add(good.clone(), 500, 1, 5, true);
    for flag in [b'x', b'g', b'L', b'K', b'S', b'Z', b'9'] {
        add(good.clone(), 156, flag, 9, true);
    }
    add(good.clone(), 100, b'8', 6, true);
    add(good.clone(), 108, 128, 5, true);
    add(good.clone(), 2, b'X', 8, true);
    add(good.clone(), 0, 0, 8, true);
    add(good.clone(), 514, 1, 11, false);
    for kind in [b'1', b'2'] {
        let mut b = good.clone();
        b[156] = kind;
        octal(&mut b, 124, 12, 0);
        checksum(&mut b[..512]);
        cases.push(b);
        expected.push(Some(8));
        let mut b = good.clone();
        b[156] = kind;
        b[157] = b'a';
        checksum(&mut b[..512]);
        cases.push(b);
        expected.push(Some(10));
    }
    for (offset, width, value, code) in [(100, 8, 4096, 7), (124, 12, 2147483648, 16)] {
        let mut b = good.clone();
        octal(&mut b, offset, width, value);
        checksum(&mut b[..512]);
        cases.push(b);
        expected.push(Some(code));
    }
    let mut b = good.clone();
    b[108..116].copy_from_slice(b"10000000");
    checksum(&mut b[..512]);
    cases.push(b);
    expected.push(Some(7));
    let mut b = good.clone();
    b[108..116].fill(b'0');
    checksum(&mut b[..512]);
    cases.push(b);
    expected.push(Some(6));
    let mut b = good.clone();
    b[265..297].fill(b'u');
    checksum(&mut b[..512]);
    cases.push(b);
    expected.push(Some(8));
    let mut b = good.clone();
    b[1024 + 512] = 1;
    cases.push(b);
    expected.push(Some(3));
    let mut b = good.clone();
    b.extend_from_slice(&[1; 512]);
    cases.push(b);
    expected.push(Some(12));
    let mut b = good.clone();
    b.push(0);
    cases.push(b);
    expected.push(Some(2));
    for (index, (result, error)) in read_archives(&cases).iter().zip(expected).enumerate() {
        if let Some(code) = error {
            assert_eq!(result.code, code, "case{index}: {result:?}");
        } else {
            assert_ne!(result.code, 0, "prefix{index}");
            if index >= 1024 {
                assert_eq!(result.members, [m.clone()]);
            } else {
                assert!(result.members.is_empty());
            }
        }
        assert!(!result.finished);
    }
}

#[derive(Debug)]
struct WriteCase {
    members: Vec<Member>,
    capacity: usize,
    errors: Vec<i32>,
    finish_error: i32,
}
fn write_cases(cases: &[WriteCase]) -> Vec<Vec<u8>> {
    let mut input = Vec::new();
    for c in cases {
        let mut body = Vec::new();
        body.extend_from_slice(&(c.capacity as u32).to_le_bytes());
        body.extend_from_slice(&(c.members.len() as u32).to_le_bytes());
        body.extend(protocol(&c.members));
        input.extend_from_slice(&(body.len() as u32).to_le_bytes());
        input.extend(body);
    }
    let bytes = run("tests/fixtures/extended/tar_write.lani", &input);
    let mut p = 0;
    let mut archives = Vec::new();
    for (index, c) in cases.iter().enumerate() {
        let mut expected = Vec::new();
        for (m, &code) in c.members.iter().zip(&c.errors) {
            assert_eq!(integer(&bytes, p) as i32, code, "case{index} {m:?}");
            if code == 0 {
                expected.extend(canonical_member(m));
            }
            assert_eq!(
                integer(&bytes, p + 4) as usize,
                expected.len(),
                "case{index}"
            );
            p += 8;
        }
        assert_eq!(
            integer(&bytes, p) as i32,
            c.finish_error,
            "case{index} finish"
        );
        if c.finish_error == 0 {
            expected.resize(expected.len() + 1024, 0);
        }
        assert_eq!(integer(&bytes, p + 4) as usize, expected.len());
        p += 8;
        let written = bytes[p..p + c.capacity].to_vec();
        p += c.capacity;
        let length = expected.len();
        expected.resize(c.capacity, 77);
        assert_eq!(
            written, expected,
            "case{index}: failed operation must preserve all bytes and successful output must be deterministic"
        );
        archives.push(written[..length].to_vec());
    }
    assert_eq!(p, bytes.len());
    archives
}

#[test]
fn tar_writer_is_deterministic_atomic_across_metadata_capacity_errors_and_interoperable_with_python()
 {
    let mut valid = vec![
        regular(b"first", b"\0\xffa"),
        regular(&vec![b'n'; 100], b""),
    ];
    let mut long = vec![b'p'; 155];
    long.push(b'/');
    long.extend_from_slice(&[b'n'; 100]);
    valid.push(regular(&long, b"last"));
    let mut trailing_directory = regular(&[vec![b'd'; 155], vec![b'/']].concat(), b"");
    trailing_directory.kind = 5;
    valid.push(trailing_directory);
    for kind in 1..=7 {
        let mut m = regular(
            format!("kind-{kind}{}", if kind == 5 { "/" } else { "" }).as_bytes(),
            b"",
        );
        m.kind = kind;
        if kind == 1 || kind == 2 {
            m.link = if kind == 1 {
                b"first".to_vec()
            } else {
                vec![0xff; 100]
            };
        }
        if kind == 3 || kind == 4 {
            m.major = 2097151;
            m.minor = 2097151;
        }
        if kind == 7 {
            m.data = b"contiguous".to_vec();
        }
        valid.push(m);
    }
    valid[0].mode = 4095;
    valid[0].uid = 2097151;
    valid[0].gid = 2097151;
    valid[0].mtime = 8589934591;
    valid[0].uname = vec![b'u'; 31];
    valid[0].gname = vec![b'g'; 31];
    let length = archive(&valid).len();
    let mut cases = vec![WriteCase {
        members: valid.clone(),
        capacity: length + 19,
        errors: vec![0; valid.len()],
        finish_error: 0,
    }];
    let good = regular(b"good", b"x");
    let mut bad = Vec::new();
    let mut m = good.clone();
    m.path = vec![];
    bad.push((m, 8));
    let mut m = good.clone();
    m.path = b"a\0b".to_vec();
    bad.push((m, 8));
    let mut m = good.clone();
    m.path = vec![b'n'; 101];
    bad.push((m, 13));
    let mut m = good.clone();
    m.path = vec![b'n'; 257];
    bad.push((m, 13));
    let mut m = good.clone();
    m.link = vec![b'l'; 101];
    bad.push((m, 14));
    let mut m = good.clone();
    m.uname = vec![b'u'; 32];
    bad.push((m, 15));
    let mut m = good.clone();
    m.gname = vec![b'g'; 32];
    bad.push((m, 15));
    for field in 0..6 {
        let mut m = good.clone();
        match field {
            0 => m.mode = 4096,
            1 => m.uid = 2097152,
            2 => m.gid = 2097152,
            3 => m.mtime = 8589934592,
            4 => m.major = 2097152,
            _ => m.minor = 2097152,
        }
        bad.push((m, 7));
    }
    let mut m = good.clone();
    m.kind = 5;
    bad.push((m, 10));
    let mut m = good.clone();
    m.kind = 2;
    m.data.clear();
    bad.push((m, 8));
    let mut m = good.clone();
    m.link = b"unused".to_vec();
    bad.push((m, 8));
    for (m, error) in bad {
        cases.push(WriteCase {
            members: vec![good.clone(), m, good.clone()],
            capacity: 4096,
            errors: vec![0, error, 0],
            finish_error: 0,
        });
    }
    for capacity in [0, 511, 512, 1023, 1024, 2047, 2048] {
        let add = if capacity >= 1024 { 0 } else { 17 };
        let size = if add == 0 { 1024 } else { 0 };
        cases.push(WriteCase {
            members: vec![good.clone()],
            capacity,
            errors: vec![add],
            finish_error: if capacity - size >= 1024 { 0 } else { 17 },
        });
    }
    let results = write_cases(&cases);
    let bytes = python(
        r#"
import io,sys,tarfile
b=sys.stdin.buffer.read()
with tarfile.open(fileobj=io.BytesIO(b),mode='r:',encoding='utf-8',errors='surrogateescape') as t:
 for i in t:
  data=t.extractfile(i).read() if i.type in [b'0',b'7'] else b''
  assert i.size==len(data)
  sys.stdout.buffer.write(i.name.encode('utf-8','surrogateescape')+b'\0'+data)
"#,
        &results[0],
    );
    let mut expected = Vec::new();
    for m in &valid {
        let path = if m.kind == 5 {
            m.path.strip_suffix(b"/").unwrap()
        } else {
            m.path.as_slice()
        };
        expected.extend_from_slice(path);
        expected.push(0);
        expected.extend_from_slice(&m.data);
    }
    assert_eq!(bytes, expected);
}

#[test]
fn tar_reader_accepts_record_padding_nul_regular_blank_fields_and_nondatatype_size_hints() {
    let mut cases = vec![vec![0; 1024], vec![0; 10240]];
    let mut b = archive(&[regular(b"a", b"x")]);
    b.resize(b.len() + 512, 0);
    cases.push(b);
    let mut b = archive(&[regular(b"a", b"")]);
    b[156] = 0;
    b[108..116].fill(b' ');
    b[116..124].fill(0);
    checksum(&mut b[..512]);
    cases.push(b);
    for kind in [3, 4, 5, 6] {
        let mut m = regular(b"node", b"");
        m.kind = kind;
        let mut b = archive(&[m]);
        octal(&mut b, 124, 12, 8589934591);
        checksum(&mut b[..512]);
        cases.push(b);
    }
    let mut b = archive(&[regular(b"name", b"")]);
    b[..100].fill(0);
    b[345..500].fill(b'p');
    checksum(&mut b[..512]);
    cases.push(b);
    for (index, result) in read_archives(&cases).iter().enumerate() {
        assert_eq!(result.code, 0, "case{index}: {result:?}");
        assert!(result.finished);
        assert_eq!(result.position, cases[index].len());
        if (4..=7).contains(&index) {
            assert_eq!(result.sizes, [8589934591]);
            assert!(result.members[0].data.is_empty());
        }
        if index == 8 {
            assert_eq!(
                result.members[0].path,
                [vec![b'p'; 155], vec![b'/']].concat()
            );
        }
    }
}

#[test]
fn tar_writer_reader_generated_archives_cover_padding_boundaries_raw_names_and_large_data() {
    let mut cases = Vec::new();
    for count in [
        0, 1, 2, 510, 511, 512, 513, 1023, 1024, 1025, 65535, 65536, 131073,
    ] {
        let data: Vec<u8> = (0..count).map(|i| ((i * 29 + i / 7) % 256) as u8).collect();
        let m = regular(b"raw/\xff\x80\n", &data);
        let length = archive(&[m.clone()]).len();
        cases.push(WriteCase {
            members: vec![m],
            capacity: length + 7,
            errors: vec![0],
            finish_error: 0,
        });
    }
    let mut state = 0x1951_7573_7461_72u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (state >> 32) as u32
    };
    for _ in 0..96 {
        let mut members = Vec::new();
        for _ in 0..1 + next() % 5 {
            let prefix = (next() % 156) as usize;
            let suffix = 1 + (next() % 100) as usize;
            let mut path: Vec<u8> = (0..prefix).map(|_| 1 + (next() % 255) as u8).collect();
            if prefix != 0 {
                path.push(b'/');
            }
            path.extend((0..suffix).map(|_| 1 + (next() % 255) as u8));
            let data: Vec<u8> = (0..next() % 2049).map(|_| next() as u8).collect();
            let mut m = regular(&path, &data);
            m.mode = next() % 4096;
            m.uid = (next() % 2097152) as u64;
            m.gid = (next() % 2097152) as u64;
            m.mtime = ((next() as u64) << 1) | (next() as u64 & 1);
            members.push(m);
        }
        let length = archive(&members).len();
        let count = members.len();
        cases.push(WriteCase {
            members,
            capacity: length + 31,
            errors: vec![0; count],
            finish_error: 0,
        });
    }
    let archives = write_cases(&cases);
    let results = read_archives(&archives);
    for (index, (case, result)) in cases.iter().zip(results).enumerate() {
        assert_eq!(result.code, 0, "case{index}");
        assert!(result.finished);
        assert_eq!(result.members, case.members, "case{index}");
        assert_eq!(result.position, archives[index].len());
    }
}
