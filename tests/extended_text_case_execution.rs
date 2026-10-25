#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/text_case.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("text-case", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("text-case: {e}"));
    let exe = common::TempArtifact::new("laniusc_text_case", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("text-case", command, Duration::from_secs(15))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_text_case", "input", None);
    data.write_bytes(bytes);
    data
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let input = file(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
}
fn success(output: &Output, expected: &[u8]) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "status={} stderr={:?}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty(), "{:?}", output.stderr);
    let mismatch = output.stdout.iter().zip(expected).position(|(a, b)| a != b);
    assert!(
        mismatch.is_none() && output.stdout.len() == expected.len(),
        "first mismatch={mismatch:?}, actual len={}, expected len={}",
        output.stdout.len(),
        expected.len()
    );
}
fn failure(output: &Output, status: i32, reason: &str) {
    assert_eq!(
        output.status.code(),
        Some(status),
        "status={} stderr={:?}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unexpected stdout length={}",
        output.stdout.len()
    );
    let text = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        text.starts_with("text-case: ") && text.ends_with('\n') && text.contains(reason),
        "{text}"
    );
}

#[test]
fn text_case_executes_contextual_casing_locales_and_checked_resource_contracts() {
    let exe = executable();
    for (kind, locale, input, expected) in [
        (
            "lower",
            "root",
            "ΟΣ ΟΣΑ ΟΣ' Σ Σ\u{301}",
            "ος οσα ος' σ σ\u{301}",
        ),
        ("upper", "root", "Straße ﬃ ὀδυσσεύς", "STRASSE FFI ὈΔΥΣΣΕΎΣ"),
        (
            "title",
            "root",
            "they're BILL'S 123ABC",
            "They're Bill's 123Abc",
        ),
        ("fold", "root", "Straße ςΣ İI ﬃ", "strasse σσ i\u{307}i ffi"),
        ("lower", "turkic", "I İ I\u{307}", "ı i i"),
        ("upper", "turkic", "i ı", "İ I"),
        ("fold", "turkic", "İ I I\u{307}", "i ı ı\u{307}"),
        (
            "lower",
            "lithuanian",
            "I\u{301} J\u{300} Į\u{303}",
            "i\u{307}\u{301} j\u{307}\u{300} į\u{307}\u{303}",
        ),
        ("upper", "lithuanian", "i\u{307}\u{301}", "I\u{301}"),
        (
            "title",
            "root",
            "ǳUNGLE ﬃOO\0DOS\r\n",
            "ǲungle Ffioo\0Dos\r\n",
        ),
    ] {
        success(
            &invoke(
                &exe,
                &["--kind", kind, "--locale", locale],
                input.as_bytes(),
            ),
            expected.as_bytes(),
        );
    }
    success(&invoke(&exe, &[], b"ABC\0XYZ\r\n"), b"abc\0xyz\r\n");
    success(
        &invoke(
            &exe,
            &[
                "--max-input-bytes=0",
                "--max-output-bytes=0",
                "--max-work=0",
            ],
            b"",
        ),
        b"",
    );
    success(
        &invoke(
            &exe,
            &[
                "--kind=upper",
                "--max-input-bytes=2",
                "--max-output-bytes=2",
            ],
            "ß".as_bytes(),
        ),
        b"SS",
    );
    for (args, input) in [
        (vec!["--max-input-bytes=1"], "ß".as_bytes()),
        (vec!["--kind=upper", "--max-output-bytes=1"], "ß".as_bytes()),
        (vec!["--max-work=0"], b"A".as_slice()),
    ] {
        failure(&invoke(&exe, &args, input), 2, "resource-limit");
    }
    for invalid in [
        b"a\xff".as_slice(),
        b"a\xc0\x80",
        b"a\xed\xa0\x80",
        b"a\xf4\x90\x80\x80",
        b"a\xf0\x9f",
    ] {
        failure(
            &invoke(&exe, &[], invalid),
            2,
            "invalid-utf8 stage=input byte=1",
        );
    }
    let boundary = format!("{}ΟΣ", "a".repeat(1023));
    let wanted = format!("{}ος", "a".repeat(1023));
    success(&invoke(&exe, &[], boundary.as_bytes()), wanted.as_bytes());
    let mut truncated = vec![b'A'; 1023];
    truncated.extend_from_slice(b"\xf0\x9f");
    failure(
        &invoke(&exe, &[], &truncated),
        2,
        "invalid-utf8 stage=input byte=1023",
    );
    for args in [
        vec!["--kind=wat"],
        vec!["--kind=LOWER"],
        vec!["--kind"],
        vec!["--locale=tr"],
        vec!["--locale=Root"],
        vec!["--max-work=+1"],
        vec!["--max-work=-1"],
        vec!["--max-work=1000000001"],
        vec!["--max-input-bytes=67108865"],
        vec!["--help=yes"],
        vec!["operand"],
        vec!["--bad"],
    ] {
        failure(&invoke(&exe, &args, b"x"), 2, "invalid-arguments");
    }
    failure(
        &invoke(&exe, &vec!["--help"; 33], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &invoke(&exe, &[&"x".repeat(8193)], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"--locale=\xff"))),
        2,
        "invalid-arguments",
    );
    let help = invoke(&exe, &["--help"], b"\xff");
    assert_eq!(help.status.code(), Some(0));
    assert!(
        help.stderr.is_empty()
            && help.stdout.starts_with(b"Usage: text-case ")
            && help.stdout.ends_with(b"\n")
    );
}

#[test]
fn text_case_matches_independent_root_casing_oracle_on_large_mixed_text() {
    let exe = executable();
    let input = file(b"");
    let expected = file(b"");
    let script = r#"import random,sys
r=random.Random(0xca5e17)
alphabet=list('aAZßﬃǳİIıiΟΣΑςσ\u0301\u0307\u0327\u0345\u200d\u2019\x00\r\n🙂𐐀𐐨')
s=''.join(''.join(r.choice(alphabet) for _ in range(r.randrange(1,80)))+'\x00' for _ in range(2400))
open(sys.argv[1],'wb').write(s.encode())
open(sys.argv[2],'wb').write(getattr(s,sys.argv[3])().encode())
"#;
    for (kind, python) in [("lower", "lower"), ("upper", "upper"), ("fold", "casefold")] {
        let oracle = run(Command::new("python3")
            .args(["-c", script])
            .arg(input.path())
            .arg(expected.path())
            .arg(python));
        assert!(oracle.status.success() && oracle.stderr.is_empty());
        let bytes = std::fs::read(input.path()).unwrap();
        let wanted = std::fs::read(expected.path()).unwrap();
        let start = Instant::now();
        let output = invoke(&exe, &["--kind", kind], &bytes);
        let elapsed = start.elapsed();
        success(&output, &wanted);
        eprintln!(
            "text-case {kind}: {} input bytes / {} output bytes, {:.3}ms native process/file setup and I/O, compilation excluded",
            bytes.len(),
            wanted.len(),
            elapsed.as_secs_f64() * 1000.0
        );
    }
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
fn text_case_releases_owners_on_every_observed_allocation_and_io_failure() {
    let exe = executable();
    let source = "Straße İ ΟΣ\n".repeat(256);
    let expected = "STRASSE İ ΟΣ\n".repeat(256);
    let input = file(source.as_bytes());
    let trace = common::TempArtifact::new("laniusc_text_case", "trace", None);
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
            .arg("--kind=upper")
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    let (baseline, events) = execute(None);
    success(&baseline, expected.as_bytes());
    let allocations = no_leaks(&events);
    assert!(allocations >= 4);
    for when in 1..=allocations {
        failure(
            &execute(Some(&format!("mmap:error=ENOMEM:when={when}"))).0,
            4,
            "allocation-failure",
        );
    }
    let reads = events.lines().filter(|l| l.starts_with("read(")).count();
    for when in 1..=reads {
        failure(
            &execute(Some(&format!("read:error=EIO:when={when}"))).0,
            3,
            "io-failure stage=input",
        );
    }
    let writes = events.lines().filter(|l| l.starts_with("write(")).count();
    for when in 1..=writes {
        for fault in [
            format!("write:error=EIO:when={when}"),
            format!("write:retval=0:when={when}"),
        ] {
            let (output, _) = execute(Some(&fault));
            assert_eq!(output.status.code(), Some(3));
            let diag = std::str::from_utf8(&output.stderr).unwrap();
            assert!(diag.contains("io-failure stage=output"), "{diag}");
            assert!(expected.as_bytes().starts_with(&output.stdout));
        }
    }
    for fault in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        success(&execute(Some(fault)).0, expected.as_bytes());
    }
    success(
        &execute(Some("write:retval=17:when=1")).0,
        &expected.as_bytes()[17..],
    );
    let full = run(Command::new("sh")
        .args([
            "-c",
            "exec \"$1\" --kind=upper <\"$2\" >/dev/full",
            "text-case",
        ])
        .arg(exe.path())
        .arg(input.path()));
    failure(&full, 3, "io-failure stage=output");
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
    assert_eq!(output.status.code(), Some(3));
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
