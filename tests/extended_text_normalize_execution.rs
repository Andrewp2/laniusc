#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/text_normalize.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("text-normalize", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("text-normalize: {error}"));
    let exe = common::TempArtifact::new("laniusc_text_normalize", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("text-normalize", command, Duration::from_secs(15))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_text_normalize", "input", None);
    data.write_bytes(bytes);
    data
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let input = file(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
}
fn success(output: &Output, expected: &[u8], stats: Option<&str>) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert_eq!(output.stderr, stats.unwrap_or("").as_bytes(), "{output:?}");
}
fn failure(output: &Output, status: i32, reason: &str) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    let message = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        message.starts_with("text-normalize: ")
            && message.ends_with('\n')
            && message.contains(reason),
        "{output:?}"
    );
}

#[test]
fn text_normalize_executes_all_forms_preserves_binary_text_and_enforces_limits() {
    let exe = executable();
    for (form, input, expected) in [
        ("nfc", "A\u{30a}e\u{301}\u{1100}\u{1161}\u{11a8}", "Åé각"),
        ("nfd", "Åé각", "A\u{30a}e\u{301}\u{1100}\u{1161}\u{11a8}"),
        ("nfkc", "\u{fb03}①Ａ\u{212b}", "ffi1AÅ"),
        ("nfkd", "\u{fb03}①Ａ\u{212b}", "ffi1AA\u{30a}"),
    ] {
        success(
            &invoke(&exe, &["--form", form], input.as_bytes()),
            expected.as_bytes(),
            None,
        );
    }
    let source = "A\u{30a} 👩\u{200d}💻 🇺🇸\r\n\0";
    let expected = "Å 👩\u{200d}💻 🇺🇸\r\n\0";
    success(
        &invoke(&exe, &["--stats"], source.as_bytes()),
        expected.as_bytes(),
        Some("bytes=26 scalars=11 graphemes=7\n"),
    );
    success(
        &invoke(
            &exe,
            &[
                "--stats",
                "--max-input-bytes=0",
                "--max-output-bytes=0",
                "--max-scratch-scalars=0",
            ],
            b"",
        ),
        b"",
        Some("bytes=0 scalars=0 graphemes=0\n"),
    );
    success(
        &invoke(
            &exe,
            &[
                "--max-input-bytes=3",
                "--max-output-bytes=2",
                "--max-scratch-scalars=2",
            ],
            "A\u{30a}".as_bytes(),
        ),
        "Å".as_bytes(),
        None,
    );
    for (args, input) in [
        (vec!["--max-input-bytes=2"], "A\u{30a}".as_bytes()),
        (vec!["--max-output-bytes=1"], "A\u{30a}".as_bytes()),
        (vec!["--max-scratch-scalars=1"], "A\u{30a}".as_bytes()),
        (vec!["--max-work=0"], b"a".as_slice()),
        (
            vec!["--max-work=10"],
            "a\u{315}\u{300}\u{315}\u{300}".as_bytes(),
        ),
    ] {
        failure(&invoke(&exe, &args, input), 2, "resource-limit");
    }
    for input in [
        b"a\xff".as_slice(),
        b"a\xc0\x80",
        b"a\xed\xa0\x80",
        b"a\xf4\x90\x80\x80",
        b"a\xf0\x9f",
    ] {
        failure(
            &invoke(&exe, &[], input),
            2,
            "invalid-utf8 stage=input byte=1",
        );
    }
    let boundary = format!("{}A\u{30a}🙂", "a".repeat(1023));
    let boundary_expected = format!("{}Å🙂", "a".repeat(1023));
    success(
        &invoke(&exe, &[], boundary.as_bytes()),
        boundary_expected.as_bytes(),
        None,
    );
    let mut invalid = vec![b'a'; 1023];
    invalid.extend_from_slice(b"\xf0\x9f");
    failure(
        &invoke(&exe, &[], &invalid),
        2,
        "invalid-utf8 stage=input byte=1023",
    );
    for args in [
        vec!["--form=nfx"],
        vec!["--form=NFC"],
        vec!["--form"],
        vec!["--stats=yes"],
        vec!["operand"],
        vec!["--max-work=1000000001"],
        vec!["--max-work=-1"],
        vec!["--max-input-bytes=67108865"],
        vec!["--max-scratch-scalars=+1"],
        vec!["--bad"],
    ] {
        failure(&invoke(&exe, &args, b"a"), 2, "invalid-arguments");
    }
    failure(
        &invoke(&exe, &vec!["--stats"; 33], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &invoke(&exe, &[&"x".repeat(8193)], b""),
        2,
        "invalid-arguments",
    );
    use std::os::unix::ffi::OsStrExt;
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"--form=\xff"))),
        2,
        "invalid-arguments",
    );
    let help = invoke(&exe, &["--help"], b"\xff");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stdout.starts_with(b"Usage: text-normalize ")
            && help.stdout.ends_with(b"\n")
            && help.stderr.is_empty(),
        "{help:?}"
    );
}

#[test]
fn text_normalize_matches_independent_oracle_on_large_mixed_text() {
    let exe = executable();
    let input = file(b"");
    let expected = file(b"");
    // Python is only an independent test oracle. All characters here were
    // assigned before Unicode 14; the production library pins Unicode 17.
    let script = r#"import random,sys,unicodedata
r=random.Random(0x7e8717)
alphabet=list('AabcZéÅ\u212b\ufb03\u2460\uff21\uac00\uac01\u1100\u1161\u11a8\u0344\u0300\u0315\u0301\u0327\u0937\u094d\u0915👩💻\u200d🇺🇸\x00\r\n')
s=''.join(''.join(r.choice(alphabet) for _ in range(r.randrange(1,80)))+'\x00' for _ in range(3000))
open(sys.argv[1],'wb').write(s.encode())
open(sys.argv[2],'wb').write(unicodedata.normalize(sys.argv[3],s).encode())
"#;
    for form in ["NFC", "NFD", "NFKC", "NFKD"] {
        let oracle = run(Command::new("python3")
            .args(["-c", script])
            .arg(input.path())
            .arg(expected.path())
            .arg(form));
        assert!(
            oracle.status.success() && oracle.stderr.is_empty(),
            "{oracle:?}"
        );
        let bytes = std::fs::read(input.path()).unwrap();
        let wanted = std::fs::read(expected.path()).unwrap();
        let start = Instant::now();
        let output = invoke(&exe, &["--form", &form.to_ascii_lowercase()], &bytes);
        let elapsed = start.elapsed();
        success(&output, &wanted, None);
        success(
            &invoke(
                &exe,
                &["--form", &form.to_ascii_lowercase()],
                &output.stdout,
            ),
            &wanted,
            None,
        );
        eprintln!(
            "text-normalize {form}: {} input bytes, {} output bytes, {:.3} ms native elapsed (process/file setup and I/O included; compilation excluded)",
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
fn text_normalize_cleans_up_every_observed_allocation_and_io_failure() {
    let exe = executable();
    let source = "A\u{30a}é👩\u{200d}💻\n".repeat(256);
    let expected = "Åé👩\u{200d}💻\n".repeat(256);
    let stats = "bytes=4096 scalars=1536 graphemes=1024\n";
    let input = file(source.as_bytes());
    let trace = common::TempArtifact::new("laniusc_text_normalize", "trace", None);
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
            .arg("--stats")
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    let (baseline, events) = execute(None);
    success(&baseline, expected.as_bytes(), Some(stats));
    let allocations = no_leaks(&events);
    assert!(allocations >= 5, "{events}");
    for when in 1..=allocations {
        failure(
            &execute(Some(&format!("mmap:error=ENOMEM:when={when}"))).0,
            4,
            "allocation-failure",
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
            "io-failure",
        );
    }
    let writes: Vec<_> = events
        .lines()
        .filter(|line| line.starts_with("write("))
        .collect();
    for when in 1..=writes.len() {
        for fault in [
            format!("write:error=EIO:when={when}"),
            format!("write:retval=0:when={when}"),
        ] {
            let (output, _) = execute(Some(&fault));
            assert_eq!(output.status.code(), Some(3), "{output:?}");
            let diagnostic = std::str::from_utf8(&output.stderr).unwrap();
            let statistics = writes[when - 1].starts_with("write(2,");
            if statistics {
                assert_eq!(output.stdout, expected.as_bytes(), "{output:?}");
                assert!(
                    diagnostic.contains("io-failure stage=statistics"),
                    "{output:?}"
                );
            } else {
                assert!(
                    diagnostic.contains("io-failure stage=output")
                        && !diagnostic.contains("graphemes="),
                    "{output:?}"
                );
            }
            assert!(
                expected.as_bytes().starts_with(&output.stdout),
                "{output:?}"
            );
        }
    }
    for fault in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        success(&execute(Some(fault)).0, expected.as_bytes(), Some(stats));
    }
    let (short, _) = execute(Some("write:retval=17:when=1"));
    // strace skips the actual first write; the writer must advance by exactly17.
    success(&short, &expected.as_bytes()[17..], Some(stats));
    // The common timeout helper captures stdout; redirect inside the child.
    let output = run(Command::new("sh")
        .args([
            "-c",
            "exec \"$1\" --stats <\"$2\" >/dev/full",
            "text-normalize",
        ])
        .arg(exe.path())
        .arg(input.path()));
    failure(&output, 3, "io-failure stage=output");
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
