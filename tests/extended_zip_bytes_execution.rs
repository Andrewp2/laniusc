#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::{OsStr, OsString},
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/zip_bytes.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("zip-bytes", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("zip-bytes: {error}"));
        let exe = common::TempArtifact::new("laniusc_zip_bytes", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("zip-bytes", command, Duration::from_secs(15))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_zip_bytes", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke<T: AsRef<OsStr>>(args: &[T], bytes: &[u8]) -> Output {
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
            output.stderr.starts_with(b"zip-bytes: ")
                && output.stderr.ends_with(b"\n")
                && !output.stderr.contains(&0),
            "{output:?}"
        );
    }
}
fn error(args: &[&str], bytes: &[u8], word: &str) {
    let output = invoke(args, bytes);
    checked(&output, 2);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains(word),
        "{output:?}"
    );
}
fn archive(entries: &[(&str, Vec<u8>, bool)], descriptor: bool) -> Vec<u8> {
    let mut packet = Vec::new();
    for (name, bytes, compressed) in entries {
        packet.extend_from_slice(&(name.len() as u32).to_le_bytes());
        packet.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
        packet.push(*compressed as u8);
        packet.extend_from_slice(name.as_bytes());
        packet.extend_from_slice(bytes);
    }
    let file = input(&packet);
    let script = r#"import sys,io,struct,zipfile,warnings
warnings.simplefilter('ignore',UserWarning)
class Pipe(io.BytesIO):
 def seekable(self): return False
 def seek(self,*args): raise OSError('not seekable')
raw=sys.stdin.buffer.read(); at=0; out=Pipe() if sys.argv[1]=='1' else io.BytesIO()
with zipfile.ZipFile(out,'w') as archive:
 while at<len(raw):
  n,m,method=struct.unpack_from('<IIB',raw,at); at+=9
  name=raw[at:at+n].decode('utf-8');at+=n;data=raw[at:at+m];at+=m
  info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED if method else zipfile.ZIP_STORED
  archive.writestr(info,data)
sys.stdout.buffer.write(out.getvalue())"#;
    let result = run(Command::new("python3")
        .args(["-c", script, if descriptor { "1" } else { "0" }])
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(result.stderr.is_empty(), "{result:?}");
    result.stdout
}
fn reference_read(bytes: &[u8], method: u8) -> Vec<u8> {
    let file = input(bytes);
    let script = "import sys,io,zipfile\nwith zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read())) as z:\n assert len(z.infolist())==1; i=z.infolist()[0]; assert i.compress_type==int(sys.argv[1]); assert i.date_time==(1980,1,1,0,0,0); sys.stdout.buffer.write(z.read(i))";
    let output = run(Command::new("python3")
        .args(["-c", script, &method.to_string()])
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}
fn u16(bytes: &[u8], at: usize) -> usize {
    u16::from_le_bytes(bytes[at..at + 2].try_into().unwrap()) as usize
}
fn u32(bytes: &[u8], at: usize) -> usize {
    u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize
}
fn directory(bytes: &[u8]) -> Vec<usize> {
    let end = bytes.len() - 22;
    assert_eq!(&bytes[end..end + 4], b"PK\x05\x06");
    let mut at = u32(bytes, end + 16);
    let mut positions = Vec::new();
    for _ in 0..u16(bytes, end + 10) {
        positions.push(at);
        at += 46 + u16(bytes, at + 28) + u16(bytes, at + 30) + u16(bytes, at + 32);
    }
    assert_eq!(at, end);
    positions
}
fn patch_name(bytes: &mut [u8], index: usize, name: &[u8]) {
    let central = directory(bytes)[index];
    let local = u32(bytes, central + 42);
    assert_eq!(u16(bytes, central + 28), name.len());
    bytes[central + 46..central + 46 + name.len()].copy_from_slice(name);
    bytes[local + 30..local + 30 + name.len()].copy_from_slice(name);
    for at in [central + 8, local + 6] {
        let flags = (u16(bytes, at) & !2048) as u16;
        bytes[at..at + 2].copy_from_slice(&flags.to_le_bytes());
    }
}

#[test]
fn creates_deterministic_stored_and_compressed_zip_archives_readable_by_python() {
    for stored in [false, true] {
        for length in [0, 1, 255, 1023, 1024, 1025, 65536] {
            let bytes: Vec<u8> = (0..length).map(|i| ((i * 37) ^ (i / 256)) as u8).collect();
            let mut args = vec!["--create", "nested/name.bin"];
            if stored {
                args.push("--store");
            }
            let created = invoke(&args, &bytes);
            checked(&created, 0);
            assert_eq!(
                reference_read(&created.stdout, if stored { 0 } else { 8 }),
                bytes
            );
            let listed = invoke::<&str>(&[], &created.stdout);
            checked(&listed, 0);
            assert_eq!(listed.stdout, b"nested/name.bin\0");
            let read = invoke(&["--get", "nested/name.bin"], &created.stdout);
            checked(&read, 0);
            assert_eq!(read.stdout, bytes);
            let verified = invoke(&["--verify"], &created.stdout);
            checked(&verified, 0);
            assert!(verified.stdout.is_empty());
        }
    }
    let bytes = b"binary\0\xff repeated payload\n".repeat(10923);
    let first = invoke(&["--create=records"], &bytes);
    checked(&first, 0);
    assert!(first.stdout.len() < bytes.len() / 20);
    let second = invoke(&["-crecords"], &bytes);
    checked(&second, 0);
    assert_eq!(first.stdout, second.stdout);
    assert_eq!(reference_read(&first.stdout, 8), bytes);
    let utf8 = invoke(&["--create", "café/λ", "--utf8"], b"unicode filename");
    checked(&utf8, 0);
    let position = directory(&utf8.stdout)[0];
    assert_ne!(u16(&utf8.stdout, position + 8) & 2048, 0);
    let listed = invoke(&["-t"], &utf8.stdout);
    checked(&listed, 0);
    assert_eq!(listed.stdout, "café/λ\0".as_bytes());
}

#[test]
fn reads_python_multi_entry_and_descriptor_archives_and_preserves_raw_names() {
    let entries = vec![
        ("empty", vec![], false),
        ("directory/", vec![], false),
        ("../odd\n\t", b"content\0\xff".to_vec(), true),
        ("unicode/é", (0..=255).cycle().take(65536).collect(), true),
    ];
    for descriptor in [false, true] {
        let source = archive(&entries, descriptor);
        let listed = invoke::<&str>(&[], &source);
        checked(&listed, 0);
        let expected: Vec<u8> = entries
            .iter()
            .flat_map(|(name, _, _)| name.as_bytes().iter().copied().chain([0]))
            .collect();
        assert_eq!(listed.stdout, expected);
        for (name, bytes, _) in &entries {
            let output = invoke(&["--get", name], &source);
            checked(&output, 0);
            assert_eq!(&output.stdout, bytes);
        }
        let verified = invoke(&["-v"], &source);
        checked(&verified, 0);
        assert!(verified.stdout.is_empty());
    }
    let empty = archive(&[], false);
    let output = invoke::<&str>(&[], &empty);
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    let mut raw = archive(&[("plain", b"raw payload".to_vec(), true)], false);
    let name = b"r\xff/\\x";
    patch_name(&mut raw, 0, name);
    let listed = invoke::<&str>(&[], &raw);
    checked(&listed, 0);
    assert_eq!(listed.stdout, [name.as_slice(), b"\0"].concat());
    let args = vec![OsString::from("--get"), OsString::from_vec(name.to_vec())];
    let got = invoke(&args, &raw);
    checked(&got, 0);
    assert_eq!(got.stdout, b"raw payload");
    let args = vec![
        OsString::from("--create"),
        OsString::from_vec(b"r\xff.bin".to_vec()),
    ];
    let created = invoke(&args, b"raw creation");
    checked(&created, 0);
    let central = directory(&created.stdout)[0];
    assert_eq!(&created.stdout[central + 46..central + 52], b"r\xff.bin");
    assert_eq!(reference_read(&created.stdout, 8), b"raw creation");
    let mut invalid = args;
    invalid.push(OsString::from("--utf8"));
    let rejected = invoke(&invalid, b"raw creation");
    checked(&rejected, 2);
    assert!(rejected.stdout.is_empty());
    assert!(rejected.stderr.windows(5).any(|p| p == b"UTF-8"));
}

#[test]
fn enforces_arguments_and_exact_input_archive_output_entry_total_and_work_limits() {
    for args in [
        vec!["file"],
        vec!["--get"],
        vec!["--create="],
        vec!["--list", "--list"],
        vec!["--list", "--get", "a"],
        vec!["--verify", "--create", "a"],
        vec!["--max-input=-1"],
        vec!["--max-output=2147483648"],
        vec!["--max-total=18446744073709551616"],
        vec!["--max-work=+1"],
        vec!["--help", "--unknown"],
    ] {
        error(&args, b"unread", "arguments");
    }
    for args in [
        vec!["--store"],
        vec!["--utf8"],
        vec!["--verify", "--store"],
        vec!["--get", "a", "--utf8"],
    ] {
        error(&args, b"unread", "requires --create");
    }
    let help = invoke(&["--help"], b"unread");
    checked(&help, 0);
    assert!(
        help.stdout.starts_with(b"Usage: zip-bytes ")
            && help.stdout.ends_with(b"\n")
            && !help.stdout.contains(&0)
    );
    for name in ["/root", "C:drive", "back\\slash"] {
        error(&["--create", name], b"payload", "name");
    }
    let bytes = b"abc".repeat(100);
    let created = invoke(&["--create", "a"], &bytes);
    checked(&created, 0);
    let archive_size = created.stdout.len().to_string();
    let exact_data = bytes.len().to_string();
    let exact = invoke(
        &[
            "--create",
            "a",
            "--max-input",
            &exact_data,
            "--max-output",
            &archive_size,
            "--max-archive",
            &archive_size,
            "--max-entry",
            &exact_data,
            "--max-total",
            &exact_data,
            "--max-entries",
            "1",
        ],
        &bytes,
    );
    checked(&exact, 0);
    assert_eq!(exact.stdout, created.stdout);
    for (args, word) in [
        (vec!["--create", "a", "--max-input", "299"], "input limit"),
        (vec!["--create", "a", "--max-entry", "299"], "entry limit"),
        (
            vec!["--create", "a", "--max-total", "299"],
            "total size limit",
        ),
        (vec!["--create", "a", "--max-entries", "0"], "entry limit"),
        (vec!["--create", "a", "--max-work", "0"], "work limit"),
    ] {
        error(&args, &bytes, word);
    }
    let short_archive = (created.stdout.len() - 1).to_string();
    error(
        &["--create", "a", "--max-output", &short_archive],
        &bytes,
        "output limit",
    );
    error(
        &["--create", "a", "--max-archive", &short_archive],
        &bytes,
        "archive limit",
    );
    let exact = invoke(
        &[
            "--get",
            "a",
            "--max-input",
            &archive_size,
            "--max-archive",
            &archive_size,
            "--max-output",
            &exact_data,
        ],
        &created.stdout,
    );
    checked(&exact, 0);
    assert_eq!(exact.stdout, bytes);
    error(
        &["--get", "a", "--max-input", &short_archive],
        &created.stdout,
        "input limit",
    );
    error(
        &["--get", "a", "--max-archive", &short_archive],
        &created.stdout,
        "archive limit",
    );
    error(
        &["--get", "a", "--max-output", "299"],
        &created.stdout,
        "output limit",
    );
    error(&["--max-output", "1"], &created.stdout, "output limit");
    let listed = invoke(&["--max-output", "2"], &created.stdout);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"a\0");
    for (flag, number, word) in [
        ("--max-entry", "299", "entry limit"),
        ("--max-total", "299", "total size limit"),
        ("--max-entries", "0", "entry limit"),
        ("--max-work", "0", "work limit"),
    ] {
        error(&[flag, number], &created.stdout, word);
    }
    let verified = invoke(&["--verify", "--max-output", "0"], &created.stdout);
    checked(&verified, 0);
    assert!(verified.stdout.is_empty());
    error(&["--get", "missing"], &created.stdout, "not found");
    let empty = invoke(
        &[
            "--create",
            "empty",
            "--max-input",
            "0",
            "--max-entry",
            "0",
            "--max-total",
            "0",
        ],
        b"",
    );
    checked(&empty, 0);
    error(&["--create", "a", "--max-input", "0"], b"x", "input limit");
    error(&["--list"], b"", "archive");
    let too_many = vec!["--help"; 65];
    error(&too_many, b"", "arguments");
}

#[test]
fn validates_late_metadata_before_output_and_distinguishes_listing_from_payload_verification() {
    let source = archive(
        &[
            ("first", b"first payload".to_vec(), true),
            ("other", b"second payload".to_vec(), false),
        ],
        false,
    );
    let mut malformed = source.clone();
    let second = directory(&malformed)[1];
    malformed[second + 46] ^= 1;
    for args in [vec![], vec!["--get", "first"], vec!["--verify"]] {
        error(&args, &malformed, "archive");
    }
    let mut corrupt = source.clone();
    let central = directory(&corrupt)[1];
    let local = u32(&corrupt, central + 42);
    for at in [central + 16, local + 14] {
        corrupt[at] ^= 1;
    }
    let listed = invoke::<&str>(&[], &corrupt);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"first\0other\0");
    let first = invoke(&["--get", "first"], &corrupt);
    checked(&first, 0);
    assert_eq!(first.stdout, b"first payload");
    error(&["--get", "other"], &corrupt, "checksum");
    error(&["--verify"], &corrupt, "checksum");
    let duplicate = archive(
        &[
            ("same", b"one".to_vec(), true),
            ("same", b"two".to_vec(), false),
        ],
        false,
    );
    let listed = invoke::<&str>(&[], &duplicate);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"same\0same\0");
    error(&["--get", "same"], &duplicate, "duplicate");
    let verify = invoke(&["--verify"], &duplicate);
    checked(&verify, 0);
    let mut nul = source.clone();
    patch_name(&mut nul, 1, b"nu\0ll");
    error(&[], &nul, "NUL");
    let first = invoke(&["--get", "first"], &nul);
    checked(&first, 0);
    assert_eq!(first.stdout, b"first payload");
    let mut encrypted = source.clone();
    let central = directory(&encrypted)[0];
    let local = u32(&encrypted, central + 42);
    encrypted[central + 8] |= 1;
    encrypted[local + 6] |= 1;
    error(&[], &encrypted, "encrypted");
    let mut unsupported = source.clone();
    unsupported[central + 10] = 99;
    unsupported[local + 8] = 99;
    error(&[], &unsupported, "compression method");
    let mut trailing = source.clone();
    trailing.push(0);
    error(&[], &trailing, "archive");
    for end in [0, 1, 21, source.len() - 1] {
        error(&[], &source[..end], "archive");
    }
}

fn allocations_without_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
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
fn releases_all_owners_under_every_observed_allocation_and_io_failure() {
    let trace = common::TempArtifact::new("laniusc_zip_bytes", "trace", None);
    let mut state = 0xc0dec0deu32;
    let data: Vec<u8> = (0..2500)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            (state >> 24) as u8
        })
        .collect();
    let archive = invoke(&["--create", "payload"], &data);
    checked(&archive, 0);
    for args in [
        vec!["--create", "payload"],
        vec!["--create", "payload", "--store"],
        vec!["--list"],
        vec!["--get", "payload"],
        vec!["--verify"],
    ] {
        let create = args.contains(&"--create");
        let source = if create { &data } else { &archive.stdout };
        let file = input(source);
        let baseline = invoke(&args, source);
        checked(&baseline, 0);
        let expected = &baseline.stdout;
        let execute = |injection: Option<&str>, status| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,read,write"]);
            if let Some(injection) = injection {
                command.arg("-e").arg(format!("inject={injection}"));
            }
            command.arg(executable().path()).args(&args);
            let output = run(command.stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
            if injection == Some("write:error=EIO:when=1+") {
                assert_eq!(output.status.code(), Some(status));
                assert!(output.stderr.is_empty());
            } else {
                checked(&output, status);
            }
            assert!(expected.starts_with(&output.stdout), "{args:?} {output:?}");
            let events = std::fs::read_to_string(trace.path()).unwrap();
            if injection.is_some() {
                assert!(events.contains("INJECTED"), "{events}");
            }
            let count = allocations_without_leaks(&events);
            (output, count, events)
        };
        let (output, count, events) = execute(None, 0);
        assert_eq!(&output.stdout, expected);
        assert!(count >= 3, "{events}");
        for when in 1..=count {
            let (out, _, _) = execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
            assert!(out.stdout.is_empty());
        }
        let reads = events
            .lines()
            .filter(|line| line.starts_with("read("))
            .count();
        let writes = events
            .lines()
            .filter(|line| line.starts_with("write("))
            .count();
        assert!(reads > 2, "{events}");
        for when in 1..=reads {
            let (output, _, _) = execute(Some(&format!("read:error=EIO:when={when}")), 3);
            assert!(output.stdout.is_empty());
        }
        for when in 1..=writes {
            execute(Some(&format!("write:error=EIO:when={when}")), 3);
        }
        let (output, _, _) = execute(Some("read:error=EINTR:when=1"), 0);
        assert_eq!(&output.stdout, expected);
        execute(Some("read:error=EAGAIN:when=1"), 3);
        if writes > 0 {
            let (output, _, _) = execute(Some("write:error=EINTR:when=1"), 0);
            assert_eq!(&output.stdout, expected);
            for injection in [
                "write:error=EAGAIN:when=1",
                "write:retval=0:when=1",
                "write:error=EIO:when=1+",
            ] {
                execute(Some(injection), 3);
            }
        }
    }
    // Even a failed best-effort diagnostic preserves the original format status.
    let file = input(b"malformed archive");
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1+",
        ])
        .arg(executable().path())
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    allocations_without_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
