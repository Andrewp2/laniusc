#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/zip_manifest.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("zip-manifest", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("zip-manifest: {error}"));
        let exe = common::TempArtifact::new("laniusc_zip_manifest", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("zip-manifest", command, Duration::from_secs(15))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_zip_manifest", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke(args: &[&str], bytes: &[u8]) -> Output {
    let file = input(bytes);
    run(Command::new(executable().path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(
            output.stderr.starts_with(b"zip-manifest: ") && output.stderr.ends_with(b"\n"),
            "{output:?}"
        );
    }
}
fn archive(entries: &[(&str, Vec<u8>, bool)], descriptors: bool) -> Vec<u8> {
    let mut packet = Vec::new();
    for (name, data, compressed) in entries {
        packet.extend_from_slice(&(name.len() as u32).to_le_bytes());
        packet.extend_from_slice(&(data.len() as u32).to_le_bytes());
        packet.push(*compressed as u8);
        packet.extend_from_slice(name.as_bytes());
        packet.extend_from_slice(data);
    }
    let file = input(&packet);
    let script = r#"import io,sys,struct,zipfile,warnings
warnings.simplefilter('ignore',UserWarning)
class Pipe(io.BytesIO):
 def seekable(self):return False
 def seek(self,*a):raise OSError('not seekable')
raw=sys.stdin.buffer.read();at=0;out=Pipe() if sys.argv[1]=='1' else io.BytesIO()
with zipfile.ZipFile(out,'w') as z:
 while at<len(raw):
  n,m,c=struct.unpack_from('<IIB',raw,at);at+=9;name=raw[at:at+n].decode('utf-8');at+=n;data=raw[at:at+m];at+=m
  i=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));i.compress_type=zipfile.ZIP_DEFLATED if c else zipfile.ZIP_STORED;z.writestr(i,data)
sys.stdout.buffer.write(out.getvalue())"#;
    let out = run(Command::new("python3")
        .args(["-c", script, if descriptors { "1" } else { "0" }])
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&out, 0);
    out.stdout
}
#[derive(Debug, PartialEq)]
enum Value {
    Unsigned(u64),
    Bytes(Vec<u8>),
    Text(String),
    Array(Vec<Value>),
    Map(BTreeMap<String, Value>),
    Boolean(bool),
}
// Independent, definite-length decoder for the manifest schema. The library's
// complete CBOR wire codec is tested separately against RFC 8949 vectors.
fn decode(bytes: &[u8], at: &mut usize, depth: usize) -> Value {
    assert!(depth <= 8);
    let initial = bytes[*at];
    *at += 1;
    let major = initial >> 5;
    let additional = initial & 31;
    let value = match additional {
        0..=23 => additional as u64,
        24 => {
            let n = bytes[*at] as u64;
            *at += 1;
            assert!(n >= 24);
            n
        }
        25 => {
            let n = u16::from_be_bytes(bytes[*at..*at + 2].try_into().unwrap()) as u64;
            *at += 2;
            assert!(n > 255);
            n
        }
        26 => {
            let n = u32::from_be_bytes(bytes[*at..*at + 4].try_into().unwrap()) as u64;
            *at += 4;
            assert!(n > 65535);
            n
        }
        27 => {
            let n = u64::from_be_bytes(bytes[*at..*at + 8].try_into().unwrap());
            *at += 8;
            assert!(n > u32::MAX as u64);
            n
        }
        _ => panic!("unexpected CBOR head {initial:#x}"),
    };
    match major {
        0 => Value::Unsigned(value),
        2 | 3 => {
            let end = *at + usize::try_from(value).unwrap();
            let data = bytes[*at..end].to_vec();
            *at = end;
            if major == 2 {
                Value::Bytes(data)
            } else {
                Value::Text(String::from_utf8(data).unwrap())
            }
        }
        4 => Value::Array((0..value).map(|_| decode(bytes, at, depth + 1)).collect()),
        5 => {
            let mut map = BTreeMap::new();
            for _ in 0..value {
                let Value::Text(key) = decode(bytes, at, depth + 1) else {
                    panic!("non-text manifest key")
                };
                assert!(map.insert(key, decode(bytes, at, depth + 1)).is_none());
            }
            Value::Map(map)
        }
        7 if value == 20 || value == 21 => Value::Boolean(value == 21),
        _ => panic!("unexpected manifest major {major}"),
    }
}
fn u16(bytes: &[u8], at: usize) -> usize {
    u16::from_le_bytes(bytes[at..at + 2].try_into().unwrap()) as usize
}
fn u32(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap())
}
fn directories(bytes: &[u8]) -> Vec<usize> {
    let end = bytes.len() - 22;
    assert_eq!(&bytes[end..end + 4], b"PK\x05\x06");
    let mut at = u32(bytes, end + 16) as usize;
    let mut items = Vec::new();
    for _ in 0..u16(bytes, end + 10) {
        assert_eq!(&bytes[at..at + 4], b"PK\x01\x02");
        items.push(at);
        at += 46 + u16(bytes, at + 28) + u16(bytes, at + 30) + u16(bytes, at + 32);
    }
    assert_eq!(at, end);
    items
}
fn check_manifest(bytes: &[u8], zip: &[u8]) {
    let mut at = 0;
    let Value::Map(mut root) = decode(bytes, &mut at, 0) else {
        panic!("root is not map")
    };
    assert_eq!(at, bytes.len());
    assert_eq!(root.len(), 2);
    assert_eq!(root.remove("format"), Some(Value::Text("zip".into())));
    let Some(Value::Array(entries)) = root.remove("entries") else {
        panic!("entries is not array")
    };
    let records = directories(zip);
    assert_eq!(entries.len(), records.len());
    for (entry, central) in entries.into_iter().zip(records) {
        let Value::Map(mut fields) = entry else {
            panic!("entry is not map")
        };
        assert_eq!(fields.len(), 6);
        assert_eq!(
            fields.remove("name"),
            Some(Value::Bytes(
                zip[central + 46..central + 46 + u16(zip, central + 28)].to_vec()
            ))
        );
        for (name, offset) in [("compressed_size", 20), ("size", 24), ("crc32", 16)] {
            assert_eq!(
                fields.remove(name),
                Some(Value::Unsigned(u32(zip, central + offset) as u64))
            );
        }
        assert_eq!(
            fields.remove("method"),
            Some(Value::Unsigned(u16(zip, central + 10) as u64))
        );
        assert_eq!(
            fields.remove("utf8"),
            Some(Value::Boolean(u16(zip, central + 8) & 2048 != 0))
        );
    }
}
fn error(args: &[&str], zip: &[u8], message: &str) {
    let out = invoke(args, zip);
    checked(&out, 2);
    assert!(out.stdout.is_empty(), "{out:?}");
    assert!(
        String::from_utf8_lossy(&out.stderr).contains(message),
        "{out:?}"
    );
}

#[test]
fn manifests_are_valid_cbor_with_exact_metadata_for_independent_zip_archives() {
    let empty = archive(&[], false);
    let out = invoke(&[], &empty);
    checked(&out, 0);
    check_manifest(&out.stdout, &empty);
    assert_eq!(out.stdout, b"\xa2\x66format\x63zip\x67entries\x80");
    for descriptors in [false, true] {
        let mut entries = vec![
            ("empty", vec![], false),
            ("folder/", vec![], true),
            ("unicode/é😀", b"scalar".to_vec(), true),
            ("duplicate", b"one".to_vec(), false),
            ("duplicate", b"two".to_vec(), true),
        ];
        for (i, size) in [1, 255, 256, 1023, 1024, 1025, 65536]
            .into_iter()
            .enumerate()
        {
            entries.push((
                Box::leak(format!("entry-{i}").into_boxed_str()),
                (0..size).map(|n| ((n * 71) ^ (n / 256)) as u8).collect(),
                i % 2 == 0,
            ));
        }
        let zip = archive(&entries, descriptors);
        let out = invoke(&[], &zip);
        checked(&out, 0);
        check_manifest(&out.stdout, &zip);
        let again = invoke(&[], &zip);
        checked(&again, 0);
        assert_eq!(again.stdout, out.stdout);
    }
    // Binary names, including NUL, are represented by CBOR byte strings.
    let mut zip = archive(&[("raw-name", b"payload".to_vec(), false)], false);
    let central = directories(&zip)[0];
    let local = u32(&zip, central + 42) as usize;
    for offset in [local + 30, central + 46] {
        zip[offset] = 255;
        zip[offset + 3] = 0;
    }
    let out = invoke(&[], &zip);
    checked(&out, 0);
    check_manifest(&out.stdout, &zip);
    let zip = archive(
        &[("large", b"binary\0records\xff\n".repeat(65536), true)],
        false,
    );
    let out = invoke(&[], &zip);
    checked(&out, 0);
    check_manifest(&out.stdout, &zip);
}

#[test]
fn manifest_limits_and_late_integrity_failures_precede_all_output() {
    for args in [
        vec!["operand"],
        vec!["--max-input=-1"],
        vec!["--max-output=2147483648"],
        vec!["--max-total=18446744073709551616"],
        vec!["--max-work=+1"],
        vec!["--help", "--unknown"],
    ] {
        error(&args, b"unread", "arguments");
    }
    let help = invoke(&["--help"], b"unread");
    checked(&help, 0);
    assert!(help.stdout.starts_with(b"Usage: zip-manifest "));
    let zip = archive(
        &[
            ("first", b"abc".to_vec(), false),
            ("last", b"defgh".to_vec(), false),
        ],
        false,
    );
    let out = invoke(&[], &zip);
    checked(&out, 0);
    let exact = invoke(
        &[
            &format!("--max-input={}", zip.len()),
            &format!("--max-output={}", out.stdout.len()),
            "--max-entries=2",
            "--max-entry=5",
            "--max-total=8",
        ],
        &zip,
    );
    checked(&exact, 0);
    assert_eq!(exact.stdout, out.stdout);
    error(
        &[&format!("--max-input={}", zip.len() - 1)],
        &zip,
        "input limit",
    );
    error(
        &[&format!("--max-output={}", out.stdout.len() - 1)],
        &zip,
        "output limit",
    );
    error(&["--max-entries=1"], &zip, "entry limit");
    error(&["--max-entry=4"], &zip, "entry limit");
    error(&["--max-total=7"], &zip, "total size limit");
    error(&["--max-work=0"], &zip, "work limit");
    let mut corrupt = zip.clone();
    let records = directories(&corrupt);
    let second = records[1];
    let local = u32(&corrupt, second + 42) as usize;
    let start = local + 30 + u16(&corrupt, local + 26) + u16(&corrupt, local + 28);
    corrupt[start] ^= 1;
    error(&[], &corrupt, "checksum");
    let mut metadata = zip.clone();
    metadata[second + 10] = 99;
    error(&[], &metadata, "ZIP archive");
    for n in [0, 1, 21, zip.len() - 1] {
        error(&[], &zip[..n], "ZIP archive");
    }
    let empty = archive(&[], false);
    let ok = invoke(
        &["--max-entries=0", "--max-entry=0", "--max-total=0"],
        &empty,
    );
    checked(&ok, 0);
    check_manifest(&ok.stdout, &empty);
    error(&["--max-output=0"], &empty, "output limit");
}

fn allocation_count(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_string()),
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
    assert!(live.is_empty(), "{events}");
    count
}
#[test]
fn manifest_frees_every_owner_under_all_observed_allocation_and_io_failures() {
    let names: Vec<_> = (0..20).map(|i| format!("{i}-{}", "n".repeat(80))).collect();
    let entries: Vec<_> = names
        .iter()
        .enumerate()
        .map(|(i, name)| {
            (
                name.as_str(),
                (0..128).map(|n| ((n * 79) ^ (n / 256)) as u8).collect(),
                i % 2 == 0,
            )
        })
        .collect();
    let zip = archive(&entries, false);
    let expected = invoke(&[], &zip);
    checked(&expected, 0);
    let file = input(&zip);
    let trace = common::TempArtifact::new("laniusc_zip_manifest", "trace", None);
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(i) = injection {
            command.arg("-e").arg(format!("inject={i}"));
        }
        let out = run(command
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
        if injection == Some("write:error=EIO:when=1+") {
            assert_eq!(out.status.code(), Some(status));
            assert!(out.stderr.is_empty());
        } else {
            checked(&out, status);
        }
        assert!(expected.stdout.starts_with(&out.stdout), "{out:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let count = allocation_count(&events);
        (out, count, events)
    };
    let (out, count, events) = execute(None, 0);
    assert_eq!(out.stdout, expected.stdout);
    assert!(count >= 25, "{events}");
    for when in 1..=count {
        execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
    }
    let reads = events.lines().filter(|s| s.starts_with("read(")).count();
    let writes = events.lines().filter(|s| s.starts_with("write(")).count();
    assert!(reads > 2 && writes > 2, "{events}");
    for when in 1..=reads {
        let (out, _, _) = execute(Some(&format!("read:error=EIO:when={when}")), 3);
        assert!(out.stdout.is_empty());
    }
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 3);
    }
    for injection in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        let (out, _, _) = execute(Some(injection), 0);
        assert_eq!(out.stdout, expected.stdout);
    }
    for injection in [
        "read:error=EAGAIN:when=1",
        "write:error=EAGAIN:when=1",
        "write:retval=0:when=1",
        "write:error=EIO:when=1+",
    ] {
        execute(Some(injection), 3);
    }
    // A late bad CRC releases earlier payloads and the event owner too.
    let mut corrupt = zip;
    let last = *directories(&corrupt).last().unwrap();
    let local = u32(&corrupt, last + 42) as usize;
    let at = local + 30 + u16(&corrupt, local + 26) + u16(&corrupt, local + 28);
    corrupt[at] ^= 1;
    let file = input(&corrupt);
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(executable().path())
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&out, 2);
    assert!(out.stdout.is_empty());
    allocation_count(&std::fs::read_to_string(trace.path()).unwrap());
}
