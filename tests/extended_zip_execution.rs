#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
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
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_zip", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[derive(Clone, Debug, PartialEq)]
struct Source {
    method: u8,
    utf8: bool,
    name: Vec<u8>,
    data: Vec<u8>,
}
fn source(method: u8, name: &str, data: Vec<u8>) -> Source {
    Source {
        method,
        utf8: !name.is_ascii(),
        name: name.as_bytes().to_vec(),
        data,
    }
}
fn source_bytes(sources: &[Source], comment: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend((sources.len() as u32).to_le_bytes());
    out.extend((comment.len() as u32).to_le_bytes());
    out.extend(comment);
    for s in sources {
        out.extend([s.method, u8::from(s.utf8)]);
        out.extend((s.name.len() as u32).to_le_bytes());
        out.extend((s.data.len() as u32).to_le_bytes());
        out.extend(&s.name);
        out.extend(&s.data);
    }
    out
}
#[derive(Clone)]
struct Request {
    encode: bool,
    payload: Vec<u8>,
    max_archive: i32,
    max_entries: i32,
    max_entry: i32,
    max_total: u64,
    max_work: u64,
    max_output: i32,
}
fn request(encode: bool, payload: Vec<u8>) -> Request {
    Request {
        encode,
        payload,
        max_archive: 5_000_000,
        max_entries: 4096,
        max_entry: 2_000_000,
        max_total: 10_000_000,
        max_work: 16_777_216,
        max_output: 2_000_000,
    }
}
fn frames(requests: &[Request]) -> Vec<u8> {
    let mut bytes = Vec::new();
    for r in requests {
        bytes.push(u8::from(r.encode));
        bytes.extend(r.max_archive.to_le_bytes());
        bytes.extend(r.max_entries.to_le_bytes());
        bytes.extend(r.max_entry.to_le_bytes());
        bytes.extend(r.max_total.to_le_bytes());
        bytes.extend(r.max_work.to_le_bytes());
        bytes.extend(r.max_output.to_le_bytes());
        bytes.extend((r.payload.len() as u32).to_le_bytes());
        bytes.extend(&r.payload);
    }
    bytes
}
struct Bytes<'a> {
    data: &'a [u8],
    at: usize,
}
impl<'a> Bytes<'a> {
    fn word(&mut self) -> i32 {
        let b = self.take(4);
        i32::from_le_bytes(b.try_into().unwrap())
    }
    fn take(&mut self, n: usize) -> &'a [u8] {
        assert!(n <= self.data.len() - self.at);
        let b = &self.data[self.at..self.at + n];
        self.at += n;
        b
    }
}
#[derive(Debug)]
struct Item {
    name: Vec<u8>,
    comment: Vec<u8>,
    method: i32,
    utf8: bool,
    crc: u32,
    error: i32,
    data: Vec<u8>,
}
#[derive(Debug)]
struct Response {
    error: i32,
    comment: Vec<u8>,
    items: Vec<Item>,
    encoded: Vec<u8>,
}
fn responses(bytes: &[u8], requests: &[Request]) -> Vec<Response> {
    let mut reader = Bytes { data: bytes, at: 0 };
    let mut rows = Vec::new();
    for r in requests {
        let error = reader.word();
        let mut row = Response {
            error,
            comment: vec![],
            items: vec![],
            encoded: vec![],
        };
        if error == 0 {
            if r.encode {
                let n = reader.word() as usize;
                row.encoded = reader.take(n).to_vec();
            } else {
                let count = reader.word();
                let n = reader.word() as usize;
                row.comment = reader.take(n).to_vec();
                for _ in 0..count {
                    let names = reader.word() as usize;
                    let comments = reader.word() as usize;
                    let method = reader.word();
                    let utf8 = reader.word() != 0;
                    let crc = reader.word() as u32;
                    let error = reader.word();
                    let n = reader.word() as usize;
                    let name = reader.take(names).to_vec();
                    let comment = reader.take(comments).to_vec();
                    let data = reader.take(n).to_vec();
                    row.items.push(Item {
                        name,
                        comment,
                        method,
                        utf8,
                        crc,
                        error,
                        data,
                    });
                }
            }
        }
        rows.push(row);
    }
    assert_eq!(reader.at, bytes.len());
    rows
}
fn run(exe: &common::TempArtifact, requests: &[Request]) -> Vec<Response> {
    let mut rows = Vec::new();
    let mut start = 0;
    while start < requests.len() {
        let mut end = start;
        let mut size = 0;
        while end < requests.len() && size + 37 + requests[end].payload.len() < 480_000 {
            size += 37 + requests[end].payload.len();
            end += 1;
        }
        assert!(end > start);
        let input = common::TempArtifact::new("laniusc_zip", "input", None);
        input.write_bytes(frames(&requests[start..end]));
        let output = common::process_output_with_timeout(
            "ZIP runtime model",
            Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
            Duration::from_secs(15),
        );
        checked(&output);
        rows.extend(responses(&output.stdout, &requests[start..end]));
        start = end;
    }
    rows
}
fn python(script: &str, args: &[&str], input: &[u8]) -> Vec<u8> {
    let file = common::TempArtifact::new("laniusc_zip", "reference", None);
    file.write_bytes(input);
    let output = common::process_output_with_timeout(
        "Python zipfile reference",
        Command::new("python3")
            .args(["-c", script])
            .args(args)
            .stdin(std::fs::File::open(file.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&output);
    output.stdout
}
fn reference_encode(sources: &[Source], comment: &[u8], descriptor: bool) -> Vec<u8> {
    reference_encode_extra(
        sources,
        comment,
        descriptor,
        &[0xfe, 0xca, 3, 0, b'a', b'b', b'c'],
    )
}
fn reference_encode_extra(
    sources: &[Source],
    comment: &[u8],
    descriptor: bool,
    extra: &[u8],
) -> Vec<u8> {
    python(
        r#"import sys,io,zipfile,struct,warnings
warnings.filterwarnings('ignore',message='Duplicate name:.*',category=UserWarning)
b=sys.stdin.buffer.read();count,n=struct.unpack_from('<II',b);i=8;comment=b[i:i+n];i+=n
class Pipe(io.BytesIO):
 def seekable(self):return False
 def seek(self,*a):raise io.UnsupportedOperation('pipe')
out=Pipe() if sys.argv[1]=='descriptor' else io.BytesIO()
with zipfile.ZipFile(out,'w',allowZip64=False) as z:
 z.comment=comment
 for index in range(count):
  method,utf8,n,size=struct.unpack_from('<BBII',b,i);i+=10;name=b[i:i+n].decode('utf-8' if utf8 else 'cp437');i+=n;data=b[i:i+size];i+=size
  info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=method;info.extra=bytes.fromhex(sys.argv[2]);info.comment=b'entry-comment';z.writestr(info,data)
assert i==len(b);sys.stdout.buffer.write(out.getvalue())
"#,
        &[
            if descriptor { "descriptor" } else { "seekable" },
            &extra.iter().map(|b| format!("{b:02x}")).collect::<String>(),
        ],
        &source_bytes(sources, comment),
    )
}
fn reference_decode(bytes: &[u8]) -> (Vec<Source>, Vec<u8>) {
    let result = python(
        r#"import sys,io,zipfile,struct
with zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read())) as z:
 infos=z.infolist();sys.stdout.buffer.write(struct.pack('<II',len(infos),len(z.comment))+z.comment)
 for info in infos:
  utf8=bool(info.flag_bits&2048);name=info.filename.encode('utf-8' if utf8 else 'cp437');data=z.read(info)
  assert info.date_time==(1980,1,1,0,0,0)
  sys.stdout.buffer.write(struct.pack('<BBII',info.compress_type,utf8,len(name),len(data))+name+data)
"#,
        &[],
        bytes,
    );
    let mut r = Bytes {
        data: &result,
        at: 0,
    };
    let count = r.word();
    let n = r.word() as usize;
    let comment = r.take(n).to_vec();
    let mut sources = Vec::new();
    for _ in 0..count {
        let method = r.take(1)[0];
        let utf8 = r.take(1)[0] != 0;
        let n = r.word() as usize;
        let size = r.word() as usize;
        let name = r.take(n).to_vec();
        let data = r.take(size).to_vec();
        sources.push(Source {
            method,
            utf8,
            name,
            data,
        });
    }
    assert_eq!(r.at, result.len());
    (sources, comment)
}
fn check_archive(row: &Response, sources: &[Source], comment: &[u8], entry_comments: bool) {
    assert_eq!(row.error, 0, "{row:?}");
    assert_eq!(row.comment, comment);
    assert_eq!(row.items.len(), sources.len());
    for (actual, source) in row.items.iter().zip(sources) {
        assert_eq!(actual.error, 0, "{actual:?}");
        assert_eq!(actual.name, source.name);
        assert_eq!(actual.data, source.data);
        assert_eq!(actual.method, source.method as i32);
        assert_eq!(actual.utf8, source.utf8);
        assert_eq!(actual.crc, crc(&source.data));
        assert_eq!(
            actual.comment,
            if entry_comments {
                b"entry-comment".as_slice()
            } else {
                b""
            }
        );
    }
}
fn crc(data: &[u8]) -> u32 {
    let mut c = 0xffff_ffffu32;
    for b in data {
        c ^= *b as u32;
        for _ in 0..8 {
            c = if c & 1 == 0 {
                c >> 1
            } else {
                (c >> 1) ^ 0xedb8_8320
            };
        }
    }
    c ^ 0xffff_ffff
}
fn corpus() -> Vec<Source> {
    let mut seed = 0x153814fdu32;
    let mut random = Vec::new();
    for _ in 0..65_537 {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        random.push((seed >> 8) as u8);
    }
    vec![
        source(0, "empty", vec![]),
        source(8, "folder/", vec![]),
        source(0, "binary", (0..=255).collect()),
        source(8, "hello.txt", b"Hello, ZIP!\n".to_vec()),
        source(
            8,
            "unicode/π.txt",
            b"repeated text repeated text\0".repeat(2500),
        ),
        source(0, "random.bin", random),
    ]
}
#[test]
fn archive_contracts_execute_native_strides_borrowing_fused_cursors_and_owned_payloads() {
    let exe = executable("tests/fixtures/extended/zip_contracts.lani");
    let output =
        common::short_process_output_with_timeout("ZIP contracts", &mut Command::new(exe.path()));
    checked(&output);
    assert!(output.stdout.is_empty());
}
#[test]
fn python_zipfile_archives_decode_multiple_methods_unicode_extras_and_signed_descriptors() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    let sources = corpus();
    let comment = b"archive\0comment\xff";
    let archives = [
        reference_encode(&sources, comment, false),
        reference_encode(&sources, comment, true),
        reference_encode(&[], b"", false),
    ];
    let rows = run(
        &exe,
        &archives
            .into_iter()
            .map(|b| request(false, b))
            .collect::<Vec<_>>(),
    );
    check_archive(&rows[0], &sources, comment, true);
    check_archive(&rows[1], &sources, comment, true);
    check_archive(&rows[2], &[], b"", false);
}
#[test]
fn deterministic_multi_entry_writer_interoperates_and_respects_exact_archive_limits() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    let sources = corpus();
    let requests = [
        request(true, source_bytes(&sources, b"archive comment")),
        request(true, source_bytes(&[], b"")),
    ];
    let rows = run(&exe, &requests);
    let repeat = run(&exe, &requests);
    for ((row, again), sources) in rows.iter().zip(&repeat).zip([sources.clone(), vec![]]) {
        assert_eq!(row.error, 0, "{row:?}");
        assert_eq!(row.encoded, again.encoded);
        let (actual, comment) = reference_decode(&row.encoded);
        assert_eq!(actual, sources);
        assert_eq!(
            comment,
            if sources.is_empty() {
                b"".as_slice()
            } else {
                b"archive comment"
            }
        );
    }
    let mut yes = requests[0].clone();
    yes.max_archive = rows[0].encoded.len() as i32;
    let mut no = yes.clone();
    no.max_archive -= 1;
    let responses = run(&exe, &[yes, no]);
    assert_eq!(responses[0].error, 0);
    assert_eq!(responses[1].error, 2);
    let self_read = run(&exe, &[request(false, rows[0].encoded.clone())]);
    check_archive(&self_read[0], &sources, b"archive comment", false);
}
fn u16(bytes: &[u8], at: usize) -> usize {
    u16::from_le_bytes(bytes[at..at + 2].try_into().unwrap()) as usize
}
fn u32(bytes: &[u8], at: usize) -> usize {
    u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize
}
fn put16(bytes: &mut [u8], at: usize, value: u16) {
    bytes[at..at + 2].copy_from_slice(&value.to_le_bytes());
}
fn put32(bytes: &mut [u8], at: usize, value: u32) {
    bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
}
#[test]
fn malformed_headers_unsupported_features_truncations_crc_and_payload_sizes_fail_explicitly() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    let base = reference_encode(&[source(8, "abc", b"data data data".to_vec())], b"", false);
    let eocd = base.len() - 22;
    let center = u32(&base, eocd + 16);
    let data = 30 + u16(&base, 26) + u16(&base, 28);
    let mut requests = Vec::new();
    let mut expected = Vec::new();
    for length in 0..base.len() {
        requests.push(request(false, base[..length].to_vec()));
        expected.push((None, None));
    }
    for (offset, value, error) in [
        (center + 8, 1u16, 14),
        (center + 10, 99, 15),
        (center + 8, 16, 16),
        (center + 6, 45, 17),
        (center + 34, 1, 13),
        (eocd + 4, 1, 13),
        (center + 8, 2048, 9),
        (center + 28, 99, 7),
    ] {
        let mut b = base.clone();
        put16(&mut b, offset, value);
        requests.push(request(false, b));
        expected.push((Some(error), None));
    }
    for offset in [center + 20, center + 24, center + 42, eocd + 12, eocd + 16] {
        let mut b = base.clone();
        put32(&mut b, offset, 0xffff_ffff);
        requests.push(request(false, b));
        expected.push((Some(12), None));
    }
    let mut b = base.clone();
    b[30] ^= 1;
    requests.push(request(false, b));
    expected.push((Some(9), None));
    let mut b = base.clone();
    b[data] ^= 0xff;
    requests.push(request(false, b));
    expected.push((Some(0), Some(None)));
    let mut b = base.clone();
    put32(&mut b, 14, 123);
    put32(&mut b, center + 16, 123);
    requests.push(request(false, b));
    expected.push((Some(0), Some(Some(21))));
    for delta in [-1i32, 1] {
        let mut b = base.clone();
        let n = (u32(&b, 22) as i32 + delta) as u32;
        put32(&mut b, 22, n);
        put32(&mut b, center + 24, n);
        requests.push(request(false, b));
        expected.push((Some(0), Some(Some(22))));
    }
    let mut b = base.clone();
    b.extend([0]);
    requests.push(request(false, b));
    expected.push((None, None));
    for (row, (parse_error, extract_error)) in run(&exe, &requests).into_iter().zip(expected) {
        if let Some(code) = parse_error {
            assert_eq!(row.error, code, "{row:?}");
            if let Some(expected) = extract_error {
                let actual = row.items[0].error;
                if let Some(code) = expected {
                    assert_eq!(actual, code, "{row:?}");
                } else {
                    assert_ne!(actual, 0, "{row:?}");
                }
                assert!(row.items[0].data.is_empty());
            }
        } else {
            assert_ne!(row.error, 0, "{row:?}");
        }
    }
}
#[test]
fn unsigned_descriptors_reordered_directories_prefixes_unicode_extras_and_overlap_contracts() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    let sources = vec![
        source(0, "a", b"stored bytes".to_vec()),
        source(8, "second", b"deflated deflated bytes".to_vec()),
    ];
    let mut archive = reference_encode(&sources, b"", false);
    let eocd = archive.len() - 22;
    let center = u32(&archive, eocd + 16);
    let first =
        46 + u16(&archive, center + 28) + u16(&archive, center + 30) + u16(&archive, center + 32);
    let mut reversed = archive[..center].to_vec();
    reversed.extend(&archive[center + first..eocd]);
    reversed.extend(&archive[center..center + first]);
    reversed.extend(&archive[eocd..]);
    check_archive(
        &run(&exe, &[request(false, reversed)]).remove(0),
        &sources.iter().cloned().rev().collect::<Vec<_>>(),
        b"",
        true,
    );
    // A byte prefix is permitted when absolute local and directory offsets agree.
    let prefix = b"unreferenced prefix\0";
    let mut prefixed = prefix.to_vec();
    prefixed.extend(&archive);
    let mut p = center + prefix.len();
    while p < eocd + prefix.len() {
        let old = u32(&prefixed, p + 42);
        put32(&mut prefixed, p + 42, (old + prefix.len()) as u32);
        p += 46 + u16(&prefixed, p + 28) + u16(&prefixed, p + 30) + u16(&prefixed, p + 32);
    }
    put32(
        &mut prefixed,
        eocd + prefix.len() + 16,
        (center + prefix.len()) as u32,
    );
    check_archive(
        &run(&exe, &[request(false, prefixed)]).remove(0),
        &sources,
        b"",
        true,
    );
    // Valid EOCD-shaped bytes in a comment must not hide the real directory.
    let mut comment = b"start".to_vec();
    comment.extend([0x50, 0x4b, 5, 6]);
    comment.extend([0; 18]);
    let bytes = reference_encode(&sources, &comment, false);
    check_archive(
        &run(&exe, &[request(false, bytes)]).remove(0),
        &sources,
        &comment,
        true,
    );
    // No Unicode-name override is applied: expose the original raw name.
    let mut extra = vec![0x75, 0x70, 12, 0, 1];
    extra.extend(crc(b"a").to_le_bytes());
    extra.extend(b"renamed");
    let bytes = reference_encode_extra(&sources[..1], b"", false, &extra);
    check_archive(
        &run(&exe, &[request(false, bytes)]).remove(0),
        &sources[..1],
        b"",
        true,
    );
    // The reader preserves legacy bytes. It does not decode them to Unicode.
    archive = reference_encode(&sources[..1], b"", false);
    let eocd = archive.len() - 22;
    let center = u32(&archive, eocd + 16);
    archive[30] = 0x82;
    archive[center + 46] = 0x82;
    let mut cp = sources[..1].to_vec();
    cp[0].name = vec![0x82];
    check_archive(
        &run(&exe, &[request(false, archive)]).remove(0),
        &cp,
        b"",
        true,
    );
    // Remove the optional signature, keeping ordinary classic descriptor fields.
    for method in [0, 8] {
        let src = vec![source(method, "one", b"descriptor payload".to_vec())];
        let signed = reference_encode(&src, b"", true);
        let old_end = signed.len() - 22;
        let old_center = u32(&signed, old_end + 16);
        let descriptor = old_center - 16;
        assert_eq!(&signed[descriptor..descriptor + 4], b"PK\x07\x08");
        let mut unsigned = signed[..descriptor].to_vec();
        unsigned.extend(&signed[descriptor + 4..]);
        let end = unsigned.len() - 22;
        put32(&mut unsigned, end + 16, (old_center - 4) as u32);
        check_archive(
            &run(&exe, &[request(false, unsigned)]).remove(0),
            &src,
            b"",
            true,
        );
    }
    // Two directory records cannot claim the same local bytes.
    let duplicates = vec![
        source(0, "same", b"x".to_vec()),
        source(0, "same", b"x".to_vec()),
    ];
    let mut bytes = reference_encode(&duplicates, b"", false);
    let end = bytes.len() - 22;
    let center = u32(&bytes, end + 16);
    let second = center
        + 46
        + u16(&bytes, center + 28)
        + u16(&bytes, center + 30)
        + u16(&bytes, center + 32);
    put32(&mut bytes, second + 42, 0);
    assert_eq!(run(&exe, &[request(false, bytes)]).remove(0).error, 11);
}
#[test]
fn entry_archive_total_work_and_extraction_limits_are_checked_at_exact_boundaries() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    let sources = vec![source(0, "a", vec![1; 100]), source(8, "b", vec![2; 200])];
    let archive = reference_encode(&sources, b"", false);
    let mut base = request(false, archive.clone());
    base.max_archive = archive.len() as i32;
    base.max_entries = 2;
    base.max_entry = 200;
    base.max_total = 300;
    base.max_output = 200;
    let mut requests = vec![base.clone()];
    let mut expected = vec![0];
    for (field, value, code) in [
        (0, base.max_archive - 1, 2),
        (1, 1, 3),
        (2, 199, 3),
        (3, -1, 1),
    ] {
        let mut c = base.clone();
        match field {
            0 => c.max_archive = value,
            1 => c.max_entries = value,
            2 => c.max_entry = value,
            _ => c.max_archive = value,
        };
        requests.push(c);
        expected.push(code);
    }
    let mut c = base.clone();
    c.max_total = 299;
    requests.push(c);
    expected.push(4);
    let mut c = base.clone();
    c.max_work = 0;
    requests.push(c);
    expected.push(5);
    let rows = run(&exe, &requests);
    for (r, code) in rows.iter().zip(expected) {
        assert_eq!(r.error, code, "{r:?}");
    }
    let mut c = base;
    c.max_output = 199;
    let row = run(&exe, &[c]).remove(0);
    assert_eq!(row.error, 0);
    assert_eq!(row.items[0].error, 0);
    assert_eq!(row.items[1].error, 24);
    assert!(row.items[1].data.is_empty());
    let writer = request(true, source_bytes(&sources, b""));
    let mut cases = vec![writer.clone()];
    let mut codes = vec![0];
    for index in 0..4 {
        let mut c = writer.clone();
        match index {
            0 => c.max_entries = 1,
            1 => c.max_entry = 199,
            2 => c.max_total = 299,
            _ => c.max_work = 0,
        };
        cases.push(c);
        codes.push([3, 3, 4, 5][index]);
    }
    for (row, code) in run(&exe, &cases).iter().zip(codes) {
        assert_eq!(row.error, code, "{row:?}");
    }
    let names = [
        b"/absolute".as_slice(),
        b"C:drive",
        b"back\\slash",
        b"nul\0name",
        b"dir/",
    ];
    let mut cases = Vec::new();
    for name in names {
        let mut s = source(0, "a", vec![1]);
        s.name = name.to_vec();
        cases.push(request(true, source_bytes(&[s], b"")));
    }
    for row in run(&exe, &cases) {
        assert_eq!(row.error, 20, "{row:?}");
    }
    let empty = source(0, "", vec![]);
    let row = run(
        &exe,
        &[request(
            true,
            source_bytes(std::slice::from_ref(&empty), b""),
        )],
    )
    .remove(0);
    assert_eq!(row.error, 0);
    check_archive(
        &run(&exe, &[request(false, row.encoded)]).remove(0),
        &[empty],
        b"",
        false,
    );
    // The bounded overlap audit permits useful large directories and stops when
    // its explicit budget is exhausted instead of doing unbounded pair work.
    let many: Vec<_> = (0..1024)
        .map(|i| source(0, &format!("f{i}"), vec![]))
        .collect();
    let archive = reference_encode(&many, b"", false);
    let mut limited = request(false, archive.clone());
    limited.max_work = 100_000;
    let rows = run(&exe, &[request(false, archive), limited]);
    check_archive(&rows[0], &many, b"", true);
    assert_eq!(rows[1].error, 5);
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    count
}
#[test]
fn every_observed_writer_and_extractor_allocation_failure_releases_partial_owners() {
    let exe = executable("tests/fixtures/extended/zip_failure.lani");
    let trace = common::TempArtifact::new("laniusc_zip", "trace", None);
    let invoke = |mode: &str, fail: Option<usize>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = fail {
            c.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
        }
        let output = common::process_output_with_timeout(
            "ZIP allocation failure",
            c.arg(exe.path()).arg(mode),
            Duration::from_secs(10),
        );
        checked(&output);
        let code = std::str::from_utf8(&output.stdout)
            .unwrap()
            .parse::<i32>()
            .unwrap();
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let count = freed(&events);
        (code, count, events)
    };
    for (mode, expected) in [("0", 0), ("1", 0), ("2", 21)] {
        let (code, n, _) = invoke(mode, None);
        assert_eq!(code, expected);
        assert!(n > 0);
        for fail in 1..=n {
            let (code, _, events) = invoke(mode, Some(fail));
            assert_eq!(code, 25, "mode={mode} fail={fail}/{n}: {events}");
        }
    }
    let (code, count, events) = invoke("3", Some(1));
    assert_eq!(code, 0);
    assert_eq!(count, 0);
    assert!(events.is_empty(), "borrowed ZIP parse allocated: {events}");
}
#[test]
fn descriptor_signature_crc_ambiguity_extra_features_encoding_and_trailing_deflate_are_explicit() {
    let exe = executable("tests/fixtures/extended/zip_model.lani");
    // Solve the four-byte CRC linear map, producing real data whose CRC equals
    // the descriptor's optional signature. Both descriptor shapes must work.
    let zero = crc(&[0; 4]);
    let mut basis = [None; 32];
    for bit in 0..32 {
        let mut vector = crc(&(1u32 << bit).to_le_bytes()) ^ zero;
        let mut mask = 1u32 << bit;
        while vector != 0 {
            let pivot = 31 - vector.leading_zeros() as usize;
            if let Some((v, m)) = basis[pivot] {
                vector ^= v;
                mask ^= m;
            } else {
                basis[pivot] = Some((vector, mask));
                break;
            }
        }
    }
    let mut desired = 0x08074b50 ^ zero;
    let mut mask = 0u32;
    for pivot in (0..32).rev() {
        if desired & (1u32 << pivot) != 0 {
            let (v, m) = basis[pivot].unwrap();
            desired ^= v;
            mask ^= m;
        }
    }
    assert_eq!(desired, 0);
    let patch = mask.to_le_bytes().to_vec();
    assert_eq!(crc(&patch), 0x08074b50);
    let collision_source = source(0, "crc", patch);
    let signed = reference_encode(std::slice::from_ref(&collision_source), b"", true);
    let old_center = u32(&signed, signed.len() - 22 + 16);
    let descriptor = old_center - 16;
    let mut unsigned = signed[..descriptor].to_vec();
    unsigned.extend(&signed[descriptor + 4..]);
    let eocd = unsigned.len() - 22;
    put32(&mut unsigned, eocd + 16, (old_center - 4) as u32);
    for bytes in [signed.clone(), unsigned] {
        check_archive(
            &run(&exe, &[request(false, bytes.clone())]).remove(0),
            std::slice::from_ref(&collision_source),
            b"",
            true,
        );
        assert_eq!(reference_decode(&bytes).0, vec![collision_source.clone()]);
    }
    let mut invalid = signed;
    invalid[descriptor + 8] ^= 1;
    assert_eq!(run(&exe, &[request(false, invalid)]).remove(0).error, 10);
    let src = source(8, "abc", b"data data data".to_vec());
    let mut requests = Vec::new();
    let mut codes = Vec::new();
    for (extra, code) in [
        (vec![1, 0, 0, 0], 12),
        (vec![1, 0x99, 0, 0], 14),
        (vec![23, 0, 0, 0], 14),
        (vec![15, 0, 0, 0], 18),
        (vec![0xfe, 0xca, 4, 0, 1], 7),
    ] {
        requests.push(request(
            false,
            reference_encode_extra(std::slice::from_ref(&src), b"", false, &extra),
        ));
        codes.push(code);
    }
    let base = reference_encode(std::slice::from_ref(&src), b"", false);
    let eocd = base.len() - 22;
    let center = u32(&base, eocd + 16);
    for name in [true, false] {
        let mut bytes = base.clone();
        put16(&mut bytes, 6, 2048);
        put16(&mut bytes, center + 8, 2048);
        if name {
            bytes[30] = 0xff;
            bytes[center + 46] = 0xff;
        } else {
            let comments = center + 46 + u16(&bytes, center + 28) + u16(&bytes, center + 30);
            bytes[comments] = 0xff;
        }
        requests.push(request(false, bytes));
        codes.push(19);
    }
    for (row, code) in run(&exe, &requests).into_iter().zip(codes) {
        assert_eq!(row.error, code, "{row:?}");
    }
    let mut invalid_source = src;
    invalid_source.utf8 = true;
    invalid_source.name = vec![255];
    assert_eq!(
        run(&exe, &[request(true, source_bytes(&[invalid_source], b""))])
            .remove(0)
            .error,
        19
    );
    let mut bytes = base[..center].to_vec();
    bytes.push(0);
    bytes.extend(&base[center..]);
    let new_center = center + 1;
    let compressed = u32(&base, 18) + 1;
    put32(&mut bytes, 18, compressed as u32);
    put32(&mut bytes, new_center + 20, compressed as u32);
    let new_end = bytes.len() - 22;
    put32(&mut bytes, new_end + 16, new_center as u32);
    let row = run(&exe, &[request(false, bytes)]).remove(0);
    assert_eq!(row.error, 0);
    assert_eq!(row.items[0].error, 23);
    assert!(row.items[0].data.is_empty());
}
