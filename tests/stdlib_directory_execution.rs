#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::{BTreeMap, BTreeSet},
    ffi::OsString,
    os::unix::{
        ffi::OsStringExt,
        fs::{PermissionsExt, symlink},
    },
    process::{Command, Output},
    time::Duration,
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let label = path.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_directory", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let p = common::TempArtifact::new("laniusc_directory", "dir", None);
        std::fs::create_dir(p.path()).unwrap();
        Self(p)
    }
    fn path(&self) -> &std::path::Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.path());
    }
}
fn tree(dir: &Directory) {
    std::fs::create_dir(dir.path().join("sub")).unwrap();
    std::fs::write(dir.path().join("file"), b"abc").unwrap();
    std::fs::write(dir.path().join("sub/leaf"), b"data").unwrap();
    symlink("sub", dir.path().join("link")).unwrap();
    std::fs::write(dir.path().join(OsString::from_vec(vec![b'n', 255])), b"").unwrap();
}
fn run(c: &mut Command) -> Output {
    common::process_output_with_timeout("directory", c, Duration::from_secs(8))
}
fn checked(out: &Output, status: i32) {
    assert_eq!(out.status.code(), Some(status), "{out:?}");
}
fn freed(events: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut count = 0;
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap();
                let size = args.split(',').nth(1).unwrap().trim();
                assert!(live.insert(address, size).is_none(), "{events}");
                count += 1;
            }
        } else if let Some(args) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            let (address, rest) = args.split_once(',').unwrap();
            let size = rest.split(')').next().unwrap().trim();
            assert_eq!(live.remove(address), Some(size), "{line}");
        }
    }
    assert!(live.is_empty(), "leaked allocations:{live:?}\n{events}");
    count
}
fn closed(events: &str) {
    // A close attempt consumes the owner even on error. Injected close errors
    // skip the real syscall; normal traces check actual successful releases.
    let mut live = BTreeSet::new();
    for line in events.lines() {
        if line.starts_with("openat(") {
            let ret = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap()
                .parse::<i32>()
                .unwrap();
            if ret >= 0 {
                assert!(live.insert(ret), "{events}");
            }
        } else if let Some(args) = line.strip_prefix("close(") {
            let fd = args.split(')').next().unwrap().parse::<i32>().unwrap();
            assert!(live.remove(&fd), "{events}");
        }
    }
    assert!(live.is_empty(), "unclosed descriptors:{live:?}\n{events}");
}
fn record(name: &[u8], hint: u8) -> Vec<u8> {
    let length = (19 + name.len() + 1 + 7) & !7;
    let mut raw = vec![0; length];
    raw[..8].copy_from_slice(&u64::MAX.to_le_bytes());
    raw[8..16].copy_from_slice(&i64::MIN.to_le_bytes());
    raw[16..18].copy_from_slice(&(length as u16).to_le_bytes());
    raw[18] = hint;
    raw[19..19 + name.len()].copy_from_slice(name);
    raw
}
fn invoke(exe: &common::TempArtifact, data: &[u8]) -> Output {
    let input = common::TempArtifact::new("laniusc_directory", "input", None);
    input.write_bytes(data);
    run(Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()))
}
#[test]
fn directory_record_parser_validates_boundaries_before_output() {
    let exe = fixture("directory_decode");
    let names: [&[u8]; 7] = [
        b".",
        b"..",
        b"a",
        b"line\n\tname",
        b"n\xff",
        b"abc",
        b"unknown",
    ];
    let mut batch = Vec::new();
    let mut expected = Vec::new();
    for (i, name) in names.iter().enumerate() {
        batch.extend(record(name, if i == 6 { 255 } else { 8 }));
        expected.extend_from_slice(name);
        expected.push(0);
    }
    let out = invoke(&exe, &batch);
    checked(&out, 0);
    assert_eq!(out.stdout, expected);
    assert!(out.stderr.is_empty());
    for size in [1, 4, 63, 255, 1024] {
        let name = vec![b'x'; size];
        let raw = record(&name, 0);
        let out = invoke(&exe, &raw);
        checked(&out, 0);
        assert_eq!(out.stdout, [name.clone(), vec![0]].concat());
        for prefix in 1..raw.len() {
            let out = invoke(&exe, &raw[..prefix]);
            checked(&out, 2);
            assert!(out.stdout.is_empty());
        }
    }
    for length in [0u16, 1, 19, 20, 23, 25, 65535] {
        let mut raw = record(b"x", 8);
        raw[16..18].copy_from_slice(&length.to_le_bytes());
        let out = invoke(&exe, &raw);
        checked(&out, 2);
        assert!(out.stdout.is_empty());
    }
    for name in [b"".as_slice(), b"a/b"] {
        let out = invoke(&exe, &record(name, 8));
        checked(&out, 2);
        assert!(out.stdout.is_empty());
    }
    let mut raw = record(b"x", 8);
    raw[19..].fill(b'x');
    let out = invoke(&exe, &raw);
    checked(&out, 2);
    assert!(out.stdout.is_empty());
    let mut late = record(b"good", 8);
    late.extend(raw);
    let out = invoke(&exe, &late);
    checked(&out, 2);
    assert!(out.stdout.is_empty());
}
#[test]
fn directory_iteration_walk_limits_and_cleanup_execute() {
    let exe = fixture("directory_contracts");
    let dir = Directory::new();
    tree(&dir);
    let trace = common::TempArtifact::new("laniusc_directory", "trace", None);
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,openat,close"])
        .arg(exe.path())
        .current_dir(dir.path()));
    checked(&out, 0);
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(freed(&events) > 0);
    closed(&events);
}

fn oracle(directory: &Directory, depth: u32, prefix: &str, suffix: &str, kind: &str) -> Vec<u8> {
    let out = run(Command::new("python3")
        .arg("tests/fixtures/stdlib_foundation/directory_oracle.py")
        .arg(directory.path())
        .arg(depth.to_string())
        .args([prefix, suffix, kind]));
    checked(&out, 0);
    assert!(out.stderr.is_empty(), "{out:?}");
    out.stdout
}

#[test]
fn directory_report_matches_os_oracle_and_checks_limits_faults_and_scale() {
    let exe = executable("sample_programs/library/directory_report.lani");
    let basic = Directory::new();
    tree(&basic);
    let expected = oracle(&basic, 64, "", "", "all");
    let actual = run(Command::new(exe.path()).arg(basic.path()));
    checked(&actual, 0);
    assert_eq!(actual.stdout, expected);
    assert!(actual.stderr.is_empty());
    for (flag, value) in [
        ("--max-entries", "4".to_owned()),
        ("--max-bytes", "20".to_owned()),
        ("--max-path-bytes", "7".to_owned()),
        ("--max-work", "0".to_owned()),
        ("--max-output", (expected.len() - 1).to_string()),
    ] {
        let out = run(Command::new(exe.path())
            .args([flag, &value])
            .arg(basic.path()));
        checked(&out, 2);
        assert!(out.stdout.is_empty(), "{flag}: {out:?}");
    }
    let exact = run(Command::new(exe.path())
        .args([
            "--max-entries",
            "5",
            "--max-bytes",
            "21",
            "--max-path-bytes",
            "8",
            "--max-output",
            &expected.len().to_string(),
        ])
        .arg(basic.path()));
    checked(&exact, 0);
    assert_eq!(exact.stdout, expected);
    let mut low = 0u64;
    let mut high = 134_217_728u64;
    while low < high {
        let middle = low + (high - low) / 2;
        let out = run(Command::new(exe.path())
            .args(["--max-work", &middle.to_string()])
            .arg(basic.path()));
        if out.status.code() == Some(0) {
            assert_eq!(out.stdout, expected);
            high = middle;
        } else {
            checked(&out, 2);
            assert!(out.stdout.is_empty());
            low = middle + 1;
        }
    }
    assert!(high > 0);
    let below = run(Command::new(exe.path())
        .args(["--max-work", &(high - 1).to_string()])
        .arg(basic.path()));
    checked(&below, 2);
    assert!(below.stdout.is_empty());
    for args in [
        vec!["--kind", "bad"],
        vec!["--depth", "129"],
        vec!["--prefix-hex", "f"],
        vec!["--suffix-hex", "zz"],
        vec!["--max-work", "18446744073709551615"],
        vec!["--unknown"],
        vec!["--depth"],
    ] {
        let out = run(Command::new(exe.path()).args(args).arg(basic.path()));
        checked(&out, 2);
        assert!(out.stdout.is_empty());
    }
    let help = run(Command::new(exe.path()).arg("--help"));
    checked(&help, 0);
    assert!(help.stdout.starts_with(b"Usage: directory-report "));
    let trace = common::TempArtifact::new("laniusc_directory", "trace", None);
    let traced = |injection: Option<&str>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"]).arg(trace.path()).args([
            "-e",
            "trace=mmap,munmap,openat,close,getdents64,statx,write",
        ]);
        if let Some(value) = injection {
            c.arg("-e").arg(format!("inject={value}"));
        }
        run(c.arg(exe.path()).arg(basic.path()))
    };
    let out = traced(None);
    checked(&out, 0);
    assert_eq!(out.stdout, expected);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let allocations = freed(&events);
    closed(&events);
    assert!(allocations >= 8);
    for at in 1..=allocations {
        let injection = format!("mmap:error=ENOMEM:when={at}");
        let out = traced(Some(&injection));
        checked(&out, 4);
        assert!(out.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{events}");
        freed(&events);
        closed(&events);
    }
    for (injection, status) in [
        ("openat:error=EACCES:when=1", 3),
        ("getdents64:error=EINTR:when=1", 3),
        ("getdents64:error=EIO:when=3", 3),
        ("statx:error=EIO:when=4", 3),
        ("close:error=EIO:when=1", 3),
        ("write:error=EIO:when=1", 3),
        ("getdents64:retval=1:when=1", 2),
        ("getdents64:retval=2147483647:when=1", 3),
        ("statx:retval=0:when=1", 2),
    ] {
        let out = traced(Some(injection));
        checked(&out, status);
        assert!(out.stdout.is_empty(), "{injection}: {out:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{events}");
        freed(&events);
        closed(&events);
    }
    let out = traced(Some("write:error=EINTR:when=1"));
    checked(&out, 0);
    assert_eq!(out.stdout, expected);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    freed(&events);
    closed(&events);
    let complex = Directory::new();
    tree(&complex);
    std::fs::create_dir(complex.path().join("sub/deep")).unwrap();
    std::fs::write(complex.path().join("sub/deep/leaf.x"), b"xyz").unwrap();
    std::fs::write(
        complex
            .path()
            .join(OsString::from_vec(vec![255, b'\t', b'\n', b'.', b'x'])),
        b"raw",
    )
    .unwrap();
    std::fs::write(complex.path().join("x".repeat(200)), b"long").unwrap();
    symlink(".", complex.path().join("loop")).unwrap();
    let fifo = run(Command::new("python3")
        .args(["-c", "import os,sys;os.mkfifo(sys.argv[1])"])
        .arg(complex.path().join("fifo")));
    checked(&fifo, 0);
    let _socket = std::os::unix::net::UnixListener::bind(complex.path().join("socket")).unwrap();
    for (depth, prefix, suffix, kind) in [
        (0, "", "", "all"),
        (1, "", "", "all"),
        (2, "", "", "all"),
        (64, "", "", "all"),
        (64, "ff", "", "file"),
        (64, "", "2e78", "file"),
        (64, "", "", "directory"),
        (64, "", "", "symlink"),
        (64, "", "", "fifo"),
        (64, "", "", "socket"),
    ] {
        let out = run(Command::new(exe.path())
            .args([
                "--depth",
                &depth.to_string(),
                "--prefix-hex",
                prefix,
                "--suffix-hex",
                suffix,
                "--kind",
                kind,
            ])
            .arg(complex.path()));
        checked(&out, 0);
        assert_eq!(
            out.stdout,
            oracle(&complex, depth, prefix, suffix, kind),
            "depth={depth},prefix={prefix},suffix={suffix},kind={kind}"
        );
    }
    let scale = Directory::new();
    for i in 0..1024 {
        std::fs::write(
            scale.path().join(format!("prefix-{i:04}.x")),
            vec![i as u8; i % 17],
        )
        .unwrap();
    }
    let mut nested = scale.path().to_path_buf();
    for i in 0..24 {
        nested.push(format!("depth-{i}"));
        std::fs::create_dir(&nested).unwrap();
        std::fs::write(nested.join("leaf"), b"").unwrap();
    }
    let out = run(Command::new(exe.path()).arg(scale.path()));
    checked(&out, 0);
    assert_eq!(out.stdout, oracle(&scale, 64, "", "", "all"));
}

#[test]
fn directory_report_handles_real_stdout_failures_and_signal_setup() {
    let exe = executable("sample_programs/library/directory_report.lani");
    let directory = Directory::new();
    tree(&directory);
    let trace = common::TempArtifact::new("laniusc_directory", "real_output", None);
    for (closed_pipe, setup_failure) in [(true, false), (false, false), (false, true)] {
        let mut command = Command::new("timeout");
        command
            .args(["--kill-after=1s", "8s", "strace", "-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=rt_sigaction,mmap,munmap,openat,close,write"]);
        if setup_failure {
            command.args(["-e", "inject=rt_sigaction:error=EINTR:when=1"]);
        }
        command.arg(exe.path()).arg(directory.path());
        if closed_pipe {
            let (reader, writer) = std::io::pipe().unwrap();
            drop(reader);
            command.stdout(writer);
        } else {
            command.stdout(
                std::fs::OpenOptions::new()
                    .write(true)
                    .open("/dev/full")
                    .unwrap(),
            );
        }
        // Keep the configured output descriptor; the common capturing helper
        // replaces stdout and would not exercise either real error boundary.
        let out = command.output().expect("bounded directory stdout failure");
        checked(&out, 3);
        assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = freed(&events);
        closed(&events);
        if setup_failure {
            assert!(
                events.contains("INJECTED") && events.contains("EINTR"),
                "{events}"
            );
            assert_eq!(allocations, 0, "setup must precede allocation: {events}");
            assert!(!events.contains("openat("));
        } else {
            assert!(allocations > 0);
            assert!(
                events.contains("SIG_IGN")
                    && events.contains(if closed_pipe { "EPIPE" } else { "ENOSPC" }),
                "{events}"
            );
        }
    }
}
