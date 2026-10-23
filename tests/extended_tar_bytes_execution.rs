#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsStr,
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    time::Duration,
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/tar_bytes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("tar-bytes", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("tar-bytes: {e}"));
    let exe = common::TempArtifact::new("laniusc_tar_bytes", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("tar-bytes", command, Duration::from_secs(15))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_tar_bytes", "input", None);
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
            output.stderr.starts_with(b"tar-bytes: ") && output.stderr.ends_with(b"\n"),
            "{output:?}"
        );
    }
}
fn reference_single(name: &OsStr, data: &[u8], gzip: bool) -> Vec<u8> {
    let file = input(data);
    let script = "import io,sys,tarfile; data=sys.stdin.buffer.read(); out=io.BytesIO()\nwith tarfile.open(fileobj=out,mode='w:gz' if sys.argv[2]=='1' else 'w',format=tarfile.USTAR_FORMAT) as t:\n i=tarfile.TarInfo(sys.argv[1]); i.size=len(data); t.addfile(i,io.BytesIO(data))\nsys.stdout.buffer.write(out.getvalue())";
    let output = run(Command::new("python3")
        .args(["-c", script])
        .arg(name)
        .arg(if gzip { "1" } else { "0" })
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&output, 0);
    output.stdout
}
fn reference_extract(archive: &[u8], name: &OsStr, gzip: bool) -> Vec<u8> {
    let file = input(archive);
    let script = "import io,sys,tarfile\nwith tarfile.open(fileobj=io.BytesIO(sys.stdin.buffer.read()),mode='r:gz' if sys.argv[2]=='1' else 'r:') as t:\n a=t.getmembers(); assert len(a)==1 and a[0].name==sys.argv[1]; assert a[0].isreg(); assert a[0].mtime==0 and a[0].uid==0 and a[0].gid==0; sys.stdout.buffer.write(t.extractfile(a[0]).read())";
    let output = run(Command::new("python3")
        .args(["-c", script])
        .arg(name)
        .arg(if gzip { "1" } else { "0" })
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&output, 0);
    output.stdout
}
fn reference_multi(duplicate: bool) -> Vec<u8> {
    let script = "import io,sys,tarfile; out=io.BytesIO()\nwith tarfile.open(fileobj=out,mode='w',format=tarfile.USTAR_FORMAT) as t:\n for name,data in [('first',b'first\\0payload'),('folder/last',bytes(range(256))*4)]:\n  i=tarfile.TarInfo(name); i.size=len(data); t.addfile(i,io.BytesIO(data))\n i=tarfile.TarInfo('folder'); i.type=tarfile.DIRTYPE; t.addfile(i)\n i=tarfile.TarInfo('link'); i.type=tarfile.SYMTYPE; i.linkname='first'; t.addfile(i)\n if sys.argv[1]=='1':\n  i=tarfile.TarInfo('first'); i.size=1; t.addfile(i,io.BytesIO(b'x'))\nsys.stdout.buffer.write(out.getvalue())";
    let output =
        run(Command::new("python3").args(["-c", script, if duplicate { "1" } else { "0" }]));
    checked(&output, 0);
    output.stdout
}
fn error(exe: &common::TempArtifact, args: &[&str], data: &[u8], word: &str) {
    let output = invoke(exe, args, data);
    checked(&output, 2);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains(word),
        "{output:?}"
    );
}

#[test]
fn tar_program_round_trips_binary_members_and_lists_independent_multi_entry_archives() {
    let exe = executable();
    for gzip in [false, true] {
        for size in [0, 1, 511, 512, 513, 65536] {
            let data: Vec<u8> = (0..size).map(|i| ((i * 71) ^ (i / 256)) as u8).collect();
            let mut args = vec!["--create", "folder/member"];
            if gzip {
                args.push("--gzip");
            }
            let created = invoke(&exe, &args, &data);
            checked(&created, 0);
            assert_eq!(
                reference_extract(&created.stdout, OsStr::new("folder/member"), gzip),
                data
            );
            let same = invoke(&exe, &args, &data);
            checked(&same, 0);
            assert_eq!(same.stdout, created.stdout);
            let mut args = vec!["--get", "folder/member"];
            if gzip {
                args.push("--gzip");
            }
            let got = invoke(
                &exe,
                &args,
                &reference_single(OsStr::new("folder/member"), &data, gzip),
            );
            checked(&got, 0);
            assert_eq!(got.stdout, data);
        }
    }
    let multi = reference_multi(false);
    let listed = invoke(&exe, &[], &multi);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"first\0folder/last\0folder/\0link\0");
    let got = invoke(&exe, &["--get=first"], &multi);
    checked(&got, 0);
    assert_eq!(got.stdout, b"first\0payload");
    let got = invoke(&exe, &["--get", "folder/last"], &multi);
    checked(&got, 0);
    assert_eq!(
        got.stdout,
        (0..256).map(|i| i as u8).collect::<Vec<_>>().repeat(4)
    );
    let long_name = format!("{}/{}", "p".repeat(155), "n".repeat(100));
    let created = invoke(&exe, &["--create", &long_name], b"prefix");
    checked(&created, 0);
    let listed = invoke(&exe, &["--list"], &created.stdout);
    checked(&listed, 0);
    assert_eq!(listed.stdout, [long_name.as_bytes(), &[0]].concat());
    let got = invoke(&exe, &["--get", &long_name], &created.stdout);
    checked(&got, 0);
    assert_eq!(got.stdout, b"prefix");

    let raw_name = OsStr::from_bytes(b"raw-\xff\nname");
    let file = input(b"raw\0bytes");
    let created = run(Command::new(exe.path())
        .arg("--create")
        .arg(raw_name)
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&created, 0);
    assert_eq!(
        reference_extract(&created.stdout, raw_name, false),
        b"raw\0bytes"
    );
    let listed = invoke(&exe, &[], &created.stdout);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"raw-\xff\nname\0");
    let archive = input(&created.stdout);
    let got = run(Command::new(exe.path())
        .arg("--get")
        .arg(raw_name)
        .stdin(Stdio::from(std::fs::File::open(archive.path()).unwrap())));
    checked(&got, 0);
    assert_eq!(got.stdout, b"raw\0bytes");
}

#[test]
fn tar_program_checks_whole_archives_before_output_and_enforces_exact_resource_limits() {
    let exe = executable();
    for args in [
        vec!["operand"],
        vec!["--get"],
        vec!["--create="],
        vec!["--list", "--get=x"],
        vec!["--create=x", "--get=x"],
        vec!["--max-input=-1"],
        vec!["--max-archive=2147483648"],
        vec!["--max-entries=+1"],
        vec!["--help", "--unknown"],
    ] {
        error(&exe, &args, b"unread", "arguments");
    }
    let help = invoke(&exe, &["--help"], b"unread");
    checked(&help, 0);
    assert!(help.stdout.starts_with(b"Usage: tar-bytes "));
    let created = invoke(
        &exe,
        &[
            "--create=one",
            "--max-input=3",
            "--max-archive=2048",
            "--max-output=2048",
            "--max-entries=1",
        ],
        b"abc",
    );
    checked(&created, 0);
    assert_eq!(created.stdout.len(), 2048);
    error(
        &exe,
        &["--create=one", "--max-input=2"],
        b"abc",
        "input limit",
    );
    error(
        &exe,
        &["--create=one", "--max-archive=2047"],
        b"abc",
        "archive limit",
    );
    error(
        &exe,
        &["--create=one", "--max-output=2047"],
        b"abc",
        "output limit",
    );
    error(
        &exe,
        &["--create=one", "--max-entries=0"],
        b"abc",
        "entry limit",
    );
    let got = invoke(&exe, &["--get=one", "--max-output=3"], &created.stdout);
    checked(&got, 0);
    assert_eq!(got.stdout, b"abc");
    error(
        &exe,
        &["--get=one", "--max-output=2"],
        &created.stdout,
        "output limit",
    );
    let listed = invoke(&exe, &["--max-output=4"], &created.stdout);
    checked(&listed, 0);
    assert_eq!(listed.stdout, b"one\0");
    error(&exe, &["--max-output=3"], &created.stdout, "output limit");
    error(
        &exe,
        &["--max-archive=2047"],
        &created.stdout,
        "archive limit",
    );
    error(&exe, &["--max-input=2047"], &created.stdout, "input limit");
    error(&exe, &["--max-entries=0"], &created.stdout, "entry limit");
    error(&exe, &["--get=missing"], &created.stdout, "not found");
    let duplicate = reference_multi(true);
    error(&exe, &["--get=first"], &duplicate, "duplicate");
    let multi = reference_multi(false);
    error(&exe, &["--get=folder/"], &multi, "regular");
    error(&exe, &["--get=link"], &multi, "regular");
    error(&exe, &["--max-entries=3"], &multi, "entry limit");
    let exact = invoke(&exe, &["--max-entries=4"], &multi);
    checked(&exact, 0);
    let mut corrupt = created.stdout.clone();
    corrupt[0] ^= 1;
    error(&exe, &[], &corrupt, "tar archive");
    // Raw TAR checksums protect headers, not member payloads.
    let mut changed_payload = created.stdout.clone();
    changed_payload[512] = b'z';
    let changed = invoke(&exe, &["--get=one"], &changed_payload);
    checked(&changed, 0);
    assert_eq!(changed.stdout, b"zbc");
    for length in [0, 511, 512, 513, 1024, 1536, 2047] {
        error(
            &exe,
            &["--get=one"],
            &created.stdout[..length],
            "tar archive",
        );
    }
    let mut late_bad = multi.clone();
    // First file: 1024 bytes; second file: 512 + 1024 bytes.
    // Corrupt the following directory header, after the selected first file.
    late_bad[2560] ^= 1;
    error(&exe, &["--get=first"], &late_bad, "tar archive");
    let mut trailing = created.stdout.clone();
    trailing.extend_from_slice(&[0; 512]);
    trailing.push(1);
    error(&exe, &[], &trailing, "tar archive");
    let gzip = invoke(&exe, &["--create=one", "--gzip"], b"abc");
    checked(&gzip, 0);
    let got = invoke(
        &exe,
        &[
            "--get=one",
            "--gzip",
            "--max-archive=2048",
            "--max-output=3",
        ],
        &gzip.stdout,
    );
    checked(&got, 0);
    assert_eq!(got.stdout, b"abc");
    error(
        &exe,
        &["--gzip", "--max-archive=2047"],
        &gzip.stdout,
        "archive limit",
    );
    let mut bad_gzip = gzip.stdout;
    let crc = bad_gzip.len() - 8;
    bad_gzip[crc] ^= 1;
    error(&exe, &["--gzip"], &bad_gzip, "compressed archive");
    let empty = invoke(
        &exe,
        &["--create=empty", "--max-input=0", "--max-archive=1536"],
        b"",
    );
    checked(&empty, 0);
    let got = invoke(&exe, &["--get=empty", "--max-output=0"], &empty.stdout);
    checked(&got, 0);
    assert!(got.stdout.is_empty());
    let zero_members = invoke(&exe, &["--max-entries=0", "--max-output=0"], &[0; 1024]);
    checked(&zero_members, 0);
    assert!(zero_members.stdout.is_empty());
    error(&exe, &["--create", &"x".repeat(101)], b"", "tar member");
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
fn tar_program_frees_all_owners_under_allocation_and_host_io_failures() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_tar_bytes", "trace", None);
    let data: Vec<u8> = (0..2500).map(|i| ((i * 97) ^ (i / 256)) as u8).collect();
    let created = invoke(&exe, &["--create=one", "--gzip"], &data);
    checked(&created, 0);
    for (args, bytes, expected) in [
        (
            vec!["--create=one", "--gzip"],
            data.as_slice(),
            created.stdout.as_slice(),
        ),
        (
            vec!["--get=one", "--gzip"],
            created.stdout.as_slice(),
            data.as_slice(),
        ),
        (
            vec!["--gzip"],
            created.stdout.as_slice(),
            b"one\0".as_slice(),
        ),
    ] {
        let file = input(bytes);
        let execute = |injection: Option<&str>, status| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,read,write"]);
            if let Some(injection) = injection {
                command.arg("-e").arg(format!("inject={injection}"));
            }
            let output = run(command
                .arg(exe.path())
                .args(&args)
                .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
            if injection == Some("write:error=EIO:when=1+") {
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
        assert_eq!(output.stdout, expected);
        assert!(count >= 3, "{events}");
        for when in 1..=count {
            execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
        }
        for when in 1..=events.lines().filter(|s| s.starts_with("read(")).count() {
            let (output, _, _) = execute(Some(&format!("read:error=EIO:when={when}")), 3);
            assert!(output.stdout.is_empty());
        }
        for when in 1..=events.lines().filter(|s| s.starts_with("write(")).count() {
            execute(Some(&format!("write:error=EIO:when={when}")), 3);
        }
        for injection in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
            let (output, _, _) = execute(Some(injection), 0);
            assert_eq!(output.stdout, expected);
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
