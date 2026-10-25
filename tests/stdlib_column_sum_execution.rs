//! Real bounded text selection and fallible reduction application.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::PermissionsExt,
    },
    path::PathBuf,
    process::{Command, Output, Stdio},
};

const MAX_INPUT: usize = 1_048_576;

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/column_sum.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("column_sum application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("column_sum: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_column_sum", "executable", None);
    file.write_bytes(bytes); // Unchanged shared strict ELF/jump checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (arguments, value) = body
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing result: {line}"));
    (
        arguments.trim_end().strip_suffix(')').unwrap(),
        value.trim(),
    )
}

#[derive(Debug)]
struct Memory {
    attempts: usize,
    successful: usize,
    failed: Vec<usize>,
}
fn memory(events: &str) -> Memory {
    let mut live = BTreeMap::<u64, usize>::new();
    let mut report = Memory {
        attempts: 0,
        successful: 0,
        failed: Vec::new(),
    };
    let mut releases = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let (arguments, value) = result(line, "mmap");
            let mut fields = arguments.split(',').map(str::trim);
            assert_eq!(fields.next(), Some("NULL"), "{events}");
            let length: usize = fields.next().unwrap().parse().unwrap();
            assert!(length > 0, "{events}");
            report.attempts += 1;
            let address = value.split_whitespace().next().unwrap();
            if let Some(address) = address.strip_prefix("0x") {
                assert!(!value.contains("INJECTED"), "{events}");
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(
                    live.insert(address, length).is_none(),
                    "duplicate live allocation: {events}"
                );
                report.successful += 1;
            } else {
                assert_eq!(address, "-1", "{events}");
                assert!(
                    value.contains("ENOMEM") && value.contains("INJECTED"),
                    "{events}"
                );
                report.failed.push(report.attempts);
            }
        } else if line.starts_with("munmap(") {
            let (arguments, value) = result(line, "munmap");
            assert_eq!(value, "0", "{events}");
            let (address, length) = arguments.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let owned = live
                .remove(&address)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(length.trim().parse::<usize>().unwrap(), owned, "{events}");
            releases += 1;
        } else if line.starts_with("mremap(") {
            panic!("unexpected growth: {events}");
        }
    }
    assert!(live.is_empty(), "unreleased owners {live:?}: {events}");
    assert_eq!(releases, report.successful, "{events}");
    report
}

struct Run {
    output: Output,
    events: String,
    memory: Memory,
}
fn run(
    executable: &common::TempArtifact,
    args: &[OsString],
    input: &[u8],
    injections: &[&str],
    closed_stdout: bool,
) -> Run {
    let data = common::TempArtifact::new("laniusc_column_sum", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_column_sum", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "5s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap",
            "-e",
            "signal=none",
        ]);
    for injection in injections {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command
        .arg(executable.path())
        .args(args)
        .stdin(Stdio::from(fs::File::open(data.path()).unwrap()));
    if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    // output() preserves explicit closed stdout; the external timeout bounds
    // the tracee without replacing that descriptor through a capture helper.
    let output = command.output().expect("bounded column_sum native case");
    let events = fs::read_to_string(trace.path()).unwrap();
    for injection in injections {
        let syscall = injection.split(':').next().unwrap();
        let reached = calls(&events, syscall)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        assert_eq!(reached.len(), 1, "unreached/repeated {injection}: {events}");
        if let Some(tail) = injection.split("error=").nth(1) {
            assert!(
                reached[0].contains(tail.split(':').next().unwrap()),
                "{events}"
            );
        }
        if let Some(tail) = injection.split("retval=").nth(1) {
            assert_eq!(
                result(reached[0], syscall)
                    .1
                    .split_whitespace()
                    .next()
                    .unwrap(),
                tail.split(':').next().unwrap(),
                "{events}"
            );
        }
    }
    if injections.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let memory = memory(&events);
    Run {
        output,
        events,
        memory,
    }
}

fn checked(
    run: &Run,
    args: &[OsString],
    status: i32,
    stdout: &[u8],
    input_reserved: bool,
    failed_map: Option<usize>,
    signal_ok: bool,
) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{args:?}: {:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, stdout, "{}", run.events);
    assert!(
        run.output.stderr.is_empty(),
        "{:?}\n{}",
        run.output,
        run.events
    );
    let actions = calls(&run.events, "rt_sigaction");
    assert_eq!(actions.len(), 1, "{}", run.events);
    assert!(
        actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"),
        "{}",
        run.events
    );
    if signal_ok {
        assert_eq!(result(actions[0], "rt_sigaction").1, "0", "{}", run.events);
    } else {
        assert!(
            actions[0].contains("EINTR") && actions[0].contains("INJECTED"),
            "{}",
            run.events
        );
    }
    let action_position = run
        .events
        .lines()
        .position(|line| line.starts_with("rt_sigaction("))
        .unwrap();
    if let Some(next) = run.events.lines().position(|line| {
        line.starts_with("mmap(") || line.starts_with("read(") || line.starts_with("write(")
    }) {
        assert!(action_position < next, "{}", run.events);
    }
    let bytes: usize = args.iter().map(|arg| arg.as_bytes().len()).sum();
    let snapshot_maps = if !signal_ok || args.len() > 1 || bytes > 32 {
        0
    } else {
        usize::from(!args.is_empty()) + usize::from(bytes != 0)
    };
    let expected = snapshot_maps + usize::from(input_reserved);
    if let Some(ordinal) = failed_map {
        assert_eq!(run.memory.attempts, ordinal, "{}", run.events);
        assert_eq!(run.memory.successful, ordinal - 1, "{}", run.events);
        assert_eq!(run.memory.failed, [ordinal], "{}", run.events);
    } else {
        assert_eq!(run.memory.attempts, expected, "{}", run.events);
        assert_eq!(run.memory.successful, expected, "{}", run.events);
        assert!(run.memory.failed.is_empty(), "{}", run.events);
    }
    for read in calls(&run.events, "read") {
        assert!(read.starts_with("read(0,"), "{}", run.events);
    }
    for write in calls(&run.events, "write") {
        assert!(write.starts_with("write(1,"), "{}", run.events);
    }
    if status != 0 && stdout.is_empty() && status != 3 {
        assert!(calls(&run.events, "write").is_empty(), "{}", run.events);
    }
}

fn ascii_space(value: u8) -> bool {
    matches!(value, b' ' | b'\t' | b'\n' | 11 | 12 | b'\r')
}
// Host parsing uses UTF-8 validation, byte word boundaries, and independent
// i128 prefix sums. It does not construct Lanius callback/adaptor objects.
fn reference(input: &[u8], column: u64) -> (i32, Vec<u8>) {
    if input.len() > MAX_INPUT {
        return (7, Vec::new());
    }
    if std::str::from_utf8(input).is_err() {
        return (6, Vec::new());
    }
    let mut count = 0_u64;
    let mut sum = 0_i128;
    for line in input.split(|&byte| byte == b'\n') {
        let Some(first) = line.iter().position(|&byte| !ascii_space(byte)) else {
            continue;
        };
        if line[first] == b'#' {
            continue;
        }
        let words = line
            .split(|&byte| ascii_space(byte))
            .filter(|part| !part.is_empty());
        let Some(word) = words
            .enumerate()
            .find_map(|(index, word)| (index as u64 + 1 == column).then_some(word))
        else {
            return (6, Vec::new());
        };
        let Some(digits) = word
            .strip_prefix(b"+")
            .or_else(|| word.strip_prefix(b"-"))
            .or(Some(word))
        else {
            unreachable!()
        };
        if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
            return (6, Vec::new());
        }
        let Ok(value) = std::str::from_utf8(word).unwrap().parse::<i64>() else {
            return (6, Vec::new());
        };
        sum += i128::from(value);
        if !(i128::from(i64::MIN)..=i128::from(i64::MAX)).contains(&sum) {
            return (5, Vec::new());
        }
        count += 1;
    }
    (0, format!("count,sum\n{count},{sum}\n").into_bytes())
}

#[test]
fn column_sum_selection_checked_reduction_and_exact_cleanup() {
    let executable = executable(); // One production compile, one strict ELF.
    let cases: &[(u64, &[u8])] = &[
        (1, b""),
        (1, b"\n \t\r\n\x0b# ignored\n# text\r\n"),
        (1, b"1 apples\n-2 bananas\n+003 text"),
        (3, b"alpha beta 7\ngamma delta -2\n"),
        (2, b"alpha\t1\r\nbeta\x0b2\ngamma\x0c3\r\n"),
        (1, b"9223372036854775807\n-9223372036854775808\n"),
        (1, b"9223372036854775807"),
        (1, b"-9223372036854775808"),
        (2, "café 7\n🦀 -2\n".as_bytes()),
        (1, b"-0\n+0\n0000\n"),
        (u64::MAX, b"# no retained rows\n"),
        (2, b"onlyone\n"),
        (1, b"text 7\n"),
        (1, b"9223372036854775808\n"),
        (1, b"-9223372036854775809\n"),
        (1, b"1x\n"),
        (2, "1\u{00a0}2\n".as_bytes()),
        (1, b"#\xff\n"),
        (2, b"\xff 1\n"),
        (1, b"1\n#\xff\n"),
        (1, b"9223372036854775807\n1\n-1\n"),
        (1, b"-9223372036854775808\n-1\n1\n"),
        (1, b"9223372036854775807\n1\nwrong\n"),
        (1, b"wrong\n9223372036854775807\n1\n"),
        (1, b"9223372036854775807\n1\n#\xff\n"),
        (u64::MAX, b"1\n"),
    ];
    for &(column, input) in cases {
        let args = vec![column.to_string().into()];
        let (status, expected) = reference(input, column);
        let observed = run(&executable, &args, input, &[], false);
        checked(&observed, &args, status, &expected, true, None, true);
    }
    let mut crossing = vec![b' '; 1023];
    crossing.extend_from_slice("é 7\n".as_bytes());
    let mut boundary = vec![b'#'];
    boundary.extend(std::iter::repeat_n(b'x', MAX_INPUT - 3));
    boundary.extend_from_slice(b"\n1");
    assert_eq!(boundary.len(), MAX_INPUT);
    let mut over = boundary.clone();
    over.push(b'\n');
    for (column, input) in [(2, crossing), (1, boundary), (1, over)] {
        let args = vec![column.to_string().into()];
        let (status, expected) = reference(&input, column);
        let observed = run(&executable, &args, &input, &[], false);
        checked(&observed, &args, status, &expected, true, None, true);
    }
    let input = b"a 7\nb -2\n";
    let valid = vec![OsString::from("2")];
    let expected = reference(input, 2).1;
    let padded = vec![OsString::from(format!("{}2", "0".repeat(31)))];
    let observed = run(&executable, &padded, input, &[], false);
    checked(&observed, &padded, 0, &expected, true, None, true);

    let mut invalid = vec![Vec::new(), vec!["1".into(), "2".into()]];
    for argument in [
        "",
        "0",
        "+1",
        "-1",
        " 1",
        "1 ",
        "1x",
        "١",
        "18446744073709551616",
    ] {
        invalid.push(vec![argument.into()]);
    }
    invalid.push(vec![OsString::from_vec(vec![255])]);
    invalid.push(vec!["0".repeat(33).into()]);
    assert_eq!(invalid.len(), 13);
    for args in invalid {
        let observed = run(&executable, &args, input, &[], false);
        checked(&observed, &args, 2, b"", false, None, true);
        assert!(
            calls(&observed.events, "read").is_empty()
                && calls(&observed.events, "write").is_empty(),
            "{}",
            observed.events
        );
    }
    for ordinal in 1..=3 {
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(&executable, &valid, input, &[&injection], false);
        checked(&observed, &valid, 4, b"", true, Some(ordinal), true);
        assert!(
            calls(&observed.events, "read").is_empty(),
            "{}",
            observed.events
        );
    }
    for (injection, status, output, reads) in [
        ("read:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("read:error=EIO:when=2", 3, b"".as_slice(), 2),
        ("read:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("read:retval=1025:when=1", 3, b"".as_slice(), 1),
        ("read:error=EINTR:when=1", 0, expected.as_slice(), 3),
    ] {
        let observed = run(&executable, &valid, input, &[injection], false);
        checked(&observed, &valid, status, output, true, None, true);
        assert_eq!(
            calls(&observed.events, "read").len(),
            reads,
            "{}",
            observed.events
        );
        if status != 0 {
            assert!(
                calls(&observed.events, "write").is_empty(),
                "{}",
                observed.events
            );
        }
    }
    for (injection, status, output, writes) in [
        ("write:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, expected.as_slice(), 2),
        ("write:retval=1:when=1", 0, &expected[1..], 2),
    ] {
        let observed = run(&executable, &valid, input, &[injection], false);
        checked(&observed, &valid, status, output, true, None, true);
        assert_eq!(
            calls(&observed.events, "write").len(),
            writes,
            "{}",
            observed.events
        );
    }
    let observed = run(&executable, &valid, input, &[], true);
    checked(&observed, &valid, 3, b"", true, None, true);
    let writes = calls(&observed.events, "write");
    assert_eq!(writes.len(), 1, "{}", observed.events);
    assert!(
        writes[0].contains("EPIPE") && !writes[0].contains("INJECTED"),
        "{}",
        observed.events
    );
    let observed = run(
        &executable,
        &valid,
        input,
        &["rt_sigaction:error=EINTR:when=1"],
        false,
    );
    checked(&observed, &valid, 3, b"", false, None, false);
    assert!(
        calls(&observed.events, "read").is_empty() && calls(&observed.events, "write").is_empty(),
        "{}",
        observed.events
    );
}
