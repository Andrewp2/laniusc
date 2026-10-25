#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::Duration,
};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/compress_bytes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("compress-bytes", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("compress-bytes: {e}"));
    let exe = common::TempArtifact::new("laniusc_compress_bytes", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("compress-bytes", command, Duration::from_secs(15))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_compress_bytes", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let file = input(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(
            output.stderr.starts_with(b"compress-bytes: ")
                && output.stderr.ends_with(b"\n")
                && !output.stderr.contains(&0),
            "{output:?}"
        );
    }
}
fn reference(bytes: &[u8], format: &str, decode: bool) -> Vec<u8> {
    let file = input(bytes);
    let script = "import sys,zlib; data=sys.stdin.buffer.read(); bits={'raw':-15,'zlib':15,'gzip':31}[sys.argv[1]]\nif sys.argv[2]=='1':\n d=zlib.decompressobj(bits); out=d.decompress(data)+d.flush(); assert d.eof and not d.unused_data and not d.unconsumed_tail\nelse:\n c=zlib.compressobj(wbits=bits); out=c.compress(data)+c.flush()\nsys.stdout.buffer.write(out)";
    let output = run(Command::new("python3")
        .args(["-c", script, format, if decode { "1" } else { "0" }])
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&output, 0);
    output.stdout
}
#[test]
fn binary_program_interoperates_with_zlib_across_formats_boundaries_and_large_data() {
    let exe = executable();
    for format in ["raw", "zlib", "gzip"] {
        for length in [0, 1, 255, 1023, 1024, 1025, 65536] {
            let bytes: Vec<u8> = (0..length).map(|i| ((i * 37) ^ (i / 256)) as u8).collect();
            let encoded = invoke(&exe, &["-f", format], &bytes);
            checked(&encoded, 0);
            assert_eq!(
                reference(&encoded.stdout, format, true),
                bytes,
                "{format} length={length}"
            );
            let compressed = reference(&bytes, format, false);
            let decoded = invoke(&exe, &["-d", "-f", format], &compressed);
            checked(&decoded, 0);
            assert_eq!(decoded.stdout, bytes);
        }
        let bytes = b"binary\0\xff repeatable input\n".repeat(10923);
        let encoded = invoke(&exe, &["--format", format], &bytes);
        checked(&encoded, 0);
        assert!(encoded.stdout.len() < bytes.len() / 10);
        let decoded = invoke(&exe, &["-d", "--format", format], &encoded.stdout);
        checked(&decoded, 0);
        assert_eq!(decoded.stdout, bytes);
    }
    let first = invoke(&exe, &[], b"deterministic");
    let second = invoke(&exe, &[], b"deterministic");
    checked(&first, 0);
    checked(&second, 0);
    assert_eq!(first.stdout, second.stdout);
    assert_eq!(&first.stdout[..3], [31, 139, 8]);
    let grouped = invoke(&exe, &["-dfgzip"], &first.stdout);
    checked(&grouped, 0);
    assert_eq!(grouped.stdout, b"deterministic");
}
fn error(exe: &common::TempArtifact, args: &[&str], bytes: &[u8], word: &str) {
    let output = invoke(exe, args, bytes);
    checked(&output, 2);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains(word),
        "{output:?}"
    );
}
#[test]
fn binary_program_validates_arguments_limits_members_and_checksums_before_output() {
    let exe = executable();
    for args in [
        vec!["file"],
        vec!["--format=unknown"],
        vec!["--format"],
        vec!["--decompress=yes"],
        vec!["--max-input=-1"],
        vec!["--max-output=2147483648"],
        vec!["--max-members=+1"],
        vec!["--help", "--unknown"],
    ] {
        error(&exe, &args, b"unread", "arguments");
    }
    let help = invoke(&exe, &["--help"], b"unread");
    checked(&help, 0);
    assert_eq!(help.stdout,b"Usage: compress-bytes [-d] [--format raw|zlib|gzip] [--max-input N] [--max-output N] [--max-members N]\n");
    let bytes = b"abc".repeat(100);
    let compressed = invoke(&exe, &[], &bytes);
    checked(&compressed, 0);
    let exact = invoke(
        &exe,
        &[
            &format!("--max-input={}", bytes.len()),
            &format!("--max-output={}", compressed.stdout.len()),
        ],
        &bytes,
    );
    checked(&exact, 0);
    assert_eq!(exact.stdout, compressed.stdout);
    error(
        &exe,
        &[&format!("--max-input={}", bytes.len() - 1)],
        &bytes,
        "input limit",
    );
    error(
        &exe,
        &[&format!("--max-output={}", compressed.stdout.len() - 1)],
        &bytes,
        "output limit",
    );
    let exact = invoke(
        &exe,
        &["-d", &format!("--max-output={}", bytes.len())],
        &compressed.stdout,
    );
    checked(&exact, 0);
    assert_eq!(exact.stdout, bytes);
    error(
        &exe,
        &["-d", &format!("--max-output={}", bytes.len() - 1)],
        &compressed.stdout,
        "output limit",
    );
    let mut corrupted = compressed.stdout.clone();
    let index = corrupted.len() - 8;
    corrupted[index] ^= 1;
    error(&exe, &["-d"], &corrupted, "checksum");
    error(
        &exe,
        &["-d"],
        &compressed.stdout[..compressed.stdout.len() - 1],
        "truncated",
    );
    let mut trailing = compressed.stdout.clone();
    trailing.push(255);
    error(&exe, &["-d"], &trailing, "trailing");
    let concatenated = [
        compressed.stdout.clone(),
        compressed.stdout.clone(),
        reference(b"", "gzip", false),
    ]
    .concat();
    let joined = invoke(&exe, &["-d", "--max-members=3"], &concatenated);
    checked(&joined, 0);
    assert_eq!(joined.stdout, bytes.repeat(2));
    error(
        &exe,
        &["-d", "--max-members=2"],
        &concatenated,
        "member limit",
    );
    error(
        &exe,
        &["-d", "--max-members=0"],
        &compressed.stdout,
        "member limit",
    );
    error(&exe, &["-dfraw"], &[7], "DEFLATE");
    error(&exe, &["-dfzlib"], &[120, 0], "header");
    let empty = invoke(&exe, &["--max-input=0"], b"");
    checked(&empty, 0);
    let empty_decoded = invoke(&exe, &["-d", "--max-output=0"], &empty.stdout);
    checked(&empty_decoded, 0);
    assert!(empty_decoded.stdout.is_empty());
    error(&exe, &["--max-input=0"], b"x", "input limit");
    let too_many = vec!["-d"; 33];
    error(&exe, &too_many, b"", "arguments");
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
fn binary_program_releases_all_buffers_under_allocation_read_write_and_diagnostic_failures() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_compress_bytes", "trace", None);
    let mut seed = 0xc0dec0deu32;
    let data: Vec<u8> = (0..2500)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            (seed >> 24) as u8
        })
        .collect();
    let encoded = invoke(&exe, &[], &data);
    checked(&encoded, 0);
    for decode in [false, true] {
        let file = input(if decode { &encoded.stdout } else { &data });
        let expected = if decode { &data } else { &encoded.stdout };
        let execute = |injection: Option<&str>, status| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,read,write"]);
            if let Some(injection) = injection {
                command.arg("-e").arg(format!("inject={injection}"));
            }
            command.arg(exe.path());
            if decode {
                command.arg("-d");
            }
            let output = run(command.stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
            if injection.is_some_and(|s| s == "write:error=EIO:when=1+") {
                assert_eq!(output.status.code(), Some(status));
                assert!(output.stderr.is_empty());
            } else {
                checked(&output, status);
            }
            assert!(expected.starts_with(&output.stdout), "{output:?}");
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
            execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
        }
        let reads = events.lines().filter(|s| s.starts_with("read(")).count();
        let writes = events.lines().filter(|s| s.starts_with("write(")).count();
        assert!(reads > 2 && writes > 2, "{events}");
        for when in 1..=reads {
            let (output, _, _) = execute(Some(&format!("read:error=EIO:when={when}")), 3);
            assert!(output.stdout.is_empty());
        }
        for when in 1..=writes {
            execute(Some(&format!("write:error=EIO:when={when}")), 3);
        }
        for injection in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
            let (output, _, _) = execute(Some(injection), 0);
            assert_eq!(&output.stdout, expected);
        }
        for injection in [
            "read:error=EAGAIN:when=1",
            "write:error=EAGAIN:when=1",
            "write:retval=0:when=1",
            "write:error=EIO:when=1+",
        ] {
            execute(Some(injection), 3);
        }
    }
}
