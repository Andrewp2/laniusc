#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/text_grep.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("text-grep", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("text-grep: {error}"));
        let exe = common::TempArtifact::new("laniusc_text_grep", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("text-grep", command, Duration::from_secs(30))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_text_grep", "input", None);
    data.write_bytes(bytes);
    data
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let input = file(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
}
fn selected(output: &Output, status: i32, expected: &[u8]) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn failure(output: &Output, status: i32, reason: &str, prefix: &[u8]) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(prefix.starts_with(&output.stdout), "{output:?}");
    let message = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        message.starts_with("text-grep: ") && message.ends_with('\n') && message.contains(reason),
        "{output:?}"
    );
}

#[test]
fn text_grep_preserves_records_reports_errors_and_enforces_bounds() {
    let exe = executable();
    let source = "no\nαβ\r\n\nα\0🙂\nlast α";
    selected(
        &invoke(exe, &["α"], source.as_bytes()),
        0,
        "αβ\r\nα\0🙂\nlast α".as_bytes(),
    );
    selected(
        &invoke(exe, &["-n", "α"], source.as_bytes()),
        0,
        "2:αβ\r\n4:α\0🙂\n5:last α".as_bytes(),
    );
    selected(
        &invoke(exe, &["--invert", "α"], source.as_bytes()),
        0,
        b"no\n\n",
    );
    selected(&invoke(exe, &["-nc", "α"], source.as_bytes()), 0, b"3\n");
    selected(&invoke(exe, &["-vc", "α"], source.as_bytes()), 0, b"2\n");
    for (pattern, input, status, expected) in [
        ("", b"".as_slice(), 1, b"".as_slice()),
        ("", b"\n", 0, b"\n"),
        ("^$", b"\r\n\n\r", 0, b"\r\n\n"),
        ("^a$", b"a\r\na\na\r", 0, b"a\r\na\n"),
        ("\\r$", b"a\r\na\r", 0, b"a\r"),
        ("\\x00", b"a\0b\nnone", 0, b"a\0b\n"),
        ("z", b"a\nb", 1, b""),
    ] {
        selected(&invoke(exe, &[pattern], input), status, expected);
    }
    selected(&invoke(exe, &["-c", ""], b""), 1, b"0\n");
    selected(&invoke(exe, &["-v", ""], b"x\n\n"), 1, b"");
    selected(&invoke(exe, &["--", "-a"], b"-a\n+a"), 0, b"-a\n");
    selected(&invoke(exe, &["--max-line=0", "^$"], b"\n"), 0, b"\n");
    selected(
        &invoke(exe, &["--max-line=4", "^éé$"], "éé\n".as_bytes()),
        0,
        "éé\n".as_bytes(),
    );
    selected(&invoke(exe, &["--max-pattern=0", ""], b"\n"), 0, b"\n");
    selected(
        &invoke(exe, &["--max-groups=0", "(?:a)"], b"a\n"),
        0,
        b"a\n",
    );
    failure(
        &invoke(exe, &["--max-line=3", "."], "éé\n".as_bytes()),
        2,
        "line-limit stage=input line=1 byte=3",
        b"",
    );
    failure(
        &invoke(exe, &["--max-line=1", "."], b"a\r\n"),
        2,
        "line-limit stage=input line=1 byte=1",
        b"",
    );
    for args in [
        vec!["--max-pattern=1", "ab"],
        vec!["--max-states=4", "abcdef"],
        vec!["--max-groups=0", "(a)"],
    ] {
        failure(
            &invoke(exe, &args, b"ab\n"),
            2,
            "resource-limit stage=pattern",
            b"",
        );
    }
    failure(
        &invoke(exe, &["--max-work=1", "a"], b"a\n"),
        2,
        "work-limit stage=search line=1",
        b"",
    );
    for pattern in ["(", "[", "a{3,2}", "*a"] {
        failure(
            &invoke(exe, &[pattern], b""),
            2,
            "invalid-regex stage=pattern",
            b"",
        );
    }
    for pattern in ["(?=a)", "(a)\\1", "a++"] {
        failure(
            &invoke(exe, &[pattern], b""),
            2,
            "unsupported-regex stage=pattern",
            b"",
        );
    }
    for bad in [
        b"a\xff".as_slice(),
        b"a\xc0\x80",
        b"a\xed\xa0\x80",
        b"a\xf4\x90\x80\x80",
        b"a\xf0\x9f",
    ] {
        failure(
            &invoke(exe, &["."], bad),
            2,
            "invalid-utf8 stage=input line=1 byte=1",
            b"",
        );
    }
    let boundary = format!("{}🙂\n", "a".repeat(1023));
    selected(
        &invoke(exe, &["🙂$"], boundary.as_bytes()),
        0,
        boundary.as_bytes(),
    );
    let mut bad = vec![b'a'; 1023];
    bad.extend_from_slice(b"\xf0\x9f\n");
    failure(
        &invoke(exe, &["."], &bad),
        2,
        "invalid-utf8 stage=input line=1 byte=1023",
        b"",
    );
    failure(
        &invoke(exe, &["."], b"ok\nno\xff\n"),
        2,
        "invalid-utf8 stage=input line=2 byte=2",
        b"ok\n",
    );
    failure(
        &invoke(exe, &["-c", "."], b"ok\nno\xff\n"),
        2,
        "invalid-utf8 stage=input",
        b"",
    );
    for args in [
        vec![],
        vec!["a", "b"],
        vec!["--bad", "a"],
        vec!["--max-line", "a"],
        vec!["--max-line=-1", "a"],
        vec!["--max-line=67108865", "a"],
        vec!["--max-pattern=65537", "a"],
        vec!["--max-states=3", "a"],
        vec!["--max-groups=129", "a"],
        vec!["--max-work=0", "a"],
        vec!["--max-work=2147483648", "a"],
        vec!["--count=yes", "a"],
    ] {
        failure(&invoke(exe, &args, b""), 2, "invalid-arguments", b"");
    }
    failure(
        &invoke(exe, &vec!["-c"; 65], b""),
        2,
        "invalid-arguments",
        b"",
    );
    failure(
        &invoke(exe, &[&"a".repeat(69633)], b""),
        2,
        "invalid-arguments",
        b"",
    );
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"a\xff"))),
        2,
        "invalid-utf8 stage=pattern argument=0 byte=1",
        b"",
    );
    let help = invoke(exe, &["--help"], b"\xff");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stdout.starts_with(b"Usage: text-grep ")
            && help.stdout.ends_with(b"PATTERN\n")
            && help.stderr.is_empty(),
        "{help:?}"
    );
}

#[test]
fn text_grep_matches_python_re_on_generated_unicode_lines_and_large_input() {
    let exe = executable();
    let input = file(b"");
    let expected = file(b"");
    let status = file(b"");
    // re.ASCII matches the provider's documented ASCII shorthand/boundary
    // semantics. Python is an independent oracle, never production code.
    let script = r#"import random,re,sys
r=random.Random(0x7e87)
alphabet=list('aaabXYZ_0123éα🙂\x00\t\r')
lines=['','aaab','éα🙂','a\x00b','Z123_','\r','a\r','abbb','αé']
lines += [''.join(r.choice(alphabet) for _ in range(r.randrange(0,96))) for _ in range(900)]
raw=''.join(s+('\r\n' if i%4==0 else '\n') for i,s in enumerate(lines))+'tail éα🙂'
open(sys.argv[1],'wb').write(raw.encode())
rx=re.compile(sys.argv[4],re.ASCII)
selected=[]
parts=raw.split('\n')
for i,part in enumerate(parts):
    terminated=i<len(parts)-1
    if not terminated and not part: continue
    logical=part[:-1] if terminated and part.endswith('\r') else part
    yes=bool(rx.search(logical))
    if 'v' in sys.argv[5]: yes=not yes
    if yes: selected.append((i+1,part+('\n' if terminated else '')))
if 'c' in sys.argv[5]: output=str(len(selected))+'\n'
else: output=''.join((str(i)+':' if 'n' in sys.argv[5] else '')+s for i,s in selected)
open(sys.argv[2],'wb').write(output.encode())
open(sys.argv[3],'w').write('0' if selected else '1')
"#;
    for pattern in [
        "",
        "a|é",
        "^(?:a|é)+$",
        "^(?:a?|é)*$", // Nullable repetition must remain bounded for every record.
        "[a-z0-9]{2,5}",
        "[^aé]+",
        "^.{0,3}$",
        "a.*?b",
        "\\b[a-z]+\\b",
        "\\w+",
        "\\s$",
        "(?:ab|α|🙂)+",
        "é?α",
        "\\x00",
        "^Z[0-9]+_$",
    ] {
        for flags in ["", "n", "v", "vc"] {
            let oracle = run(Command::new("python3")
                .args(["-c", script])
                .arg(input.path())
                .arg(expected.path())
                .arg(status.path())
                .args([pattern, flags]));
            assert!(
                oracle.status.success() && oracle.stderr.is_empty(),
                "{oracle:?}"
            );
            let source = std::fs::read(input.path()).unwrap();
            let wanted = std::fs::read(expected.path()).unwrap();
            let code: i32 = std::fs::read_to_string(status.path())
                .unwrap()
                .parse()
                .unwrap();
            let mut args = vec![];
            let option = format!("-{flags}");
            if !flags.is_empty() {
                args.push(option.as_str());
            }
            args.extend(["--", pattern]);
            selected(&invoke(exe, &args, &source), code, &wanted);
        }
    }
    // Observe useful native throughput while reusing one compiled regex across
    // many records; compilation and oracle generation are outside the timer.
    let source = "info service=mail id=103 text=éα🙂\nerror service=store id=829 text=éα🙂\r\nwarning service=mail id=300\n".repeat(4000);
    let wanted = "error service=store id=829 text=éα🙂\r\n".repeat(4000);
    let start = Instant::now();
    let output = invoke(
        exe,
        &["^error service=[a-z]+ id=[0-9]{3} text=.+$"],
        source.as_bytes(),
    );
    let elapsed = start.elapsed();
    selected(&output, 0, wanted.as_bytes());
    eprintln!(
        "text-grep: {} input bytes, {} selected bytes, {:.3} ms native elapsed (process/file setup and I/O included; compilation excluded)",
        source.len(),
        wanted.len(),
        elapsed.as_secs_f64() * 1000.0
    );
}

fn no_leaks(events: &str) -> usize {
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
    assert!(live.is_empty(), "unreleased owners: {events}");
    count
}

#[test]
fn text_grep_releases_owners_at_every_observed_allocation_and_io_fault() {
    let exe = executable();
    let input = file("aaé\r\nnope\néa".as_bytes());
    let expected = "1:aaé\r\n3:éa".as_bytes();
    let trace = common::TempArtifact::new("laniusc_text_grep", "trace", None);
    let execute = |fault: Option<&str>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(fault) = fault {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command
            .arg(exe.path())
            .args(["-n", "^(?:a|é)+$"])
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    let (baseline, events) = execute(None);
    selected(&baseline, 0, expected);
    let allocations = no_leaks(&events);
    assert!(allocations >= 5, "{events}");
    for when in 1..=allocations {
        failure(
            &execute(Some(&format!("mmap:error=ENOMEM:when={when}"))).0,
            4,
            "allocation-failure",
            expected,
        );
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    for when in 1..=reads {
        failure(
            &execute(Some(&format!("read:error=EIO:when={when}"))).0,
            3,
            "io-failure stage=input",
            expected,
        );
        selected(
            &execute(Some(&format!("read:error=EINTR:when={when}"))).0,
            0,
            expected,
        );
    }
    let writes: Vec<_> = events
        .lines()
        .filter(|line| line.starts_with("write(1,"))
        .collect();
    let mut offset = 0;
    for (index, line) in writes.iter().enumerate() {
        let when = index + 1;
        let count: usize = line.rsplit(" = ").next().unwrap().parse().unwrap();
        for fault in [
            format!("write:error=EIO:when={when}"),
            format!("write:retval=0:when={when}"),
        ] {
            failure(
                &execute(Some(&fault)).0,
                3,
                "io-failure stage=output",
                expected,
            );
        }
        selected(
            &execute(Some(&format!("write:error=EINTR:when={when}"))).0,
            0,
            expected,
        );
        // strace fakes one successful byte without transferring it. The next
        // real write must resume at precisely the following byte.
        let mut shortened = expected.to_vec();
        shortened.remove(offset);
        selected(
            &execute(Some(&format!("write:retval=1:when={when}"))).0,
            0,
            &shortened,
        );
        offset += count;
    }
    assert_eq!(offset, expected.len());
    let output = run(Command::new("sh")
        .args(["-c", "exec \"$1\" . <\"$2\" >/dev/full", "text-grep"])
        .arg(exe.path())
        .arg(input.path()));
    failure(&output, 3, "io-failure stage=output", b"");
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(exe.path())
        .arg("--bad"));
    assert_eq!(output.status.code(), Some(3), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
