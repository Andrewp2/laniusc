//! Bounded unique-word indexing via the real iterator-to-TreeMap transfer.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
};

const MAX_INPUT: usize = 1_048_576;

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/index_words.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("index_words application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("index_words: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_index_words", "executable", None);
    file.write_bytes(bytes); // Existing unchanged strict ELF/jump checker.
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
    failures: Vec<usize>,
}
fn memory(events: &str) -> Memory {
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut report = Memory {
        attempts: 0,
        successful: 0,
        failures: Vec::new(),
    };
    let mut released = Vec::new();
    let mut publishing = false;
    for line in events.lines() {
        if line.starts_with("write(") {
            publishing = true;
        }
        if line.starts_with("mmap(") {
            assert!(!publishing, "publication must not allocate: {events}");
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
                    live.insert(address, (report.successful, length)).is_none(),
                    "duplicate live mapping: {events}"
                );
                report.successful += 1;
            } else {
                assert_eq!(address, "-1", "{events}");
                assert!(
                    value.contains("ENOMEM") && value.contains("INJECTED"),
                    "{events}"
                );
                report.failures.push(report.attempts);
            }
        } else if line.starts_with("munmap(") {
            let (arguments, value) = result(line, "munmap");
            assert_eq!(value, "0", "{events}");
            let (address, length) = arguments.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let (identity, owned_length) = live
                .remove(&address)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(
                length.trim().parse::<usize>().unwrap(),
                owned_length,
                "{events}"
            );
            released.push(identity);
        } else if line.starts_with("mremap(") {
            panic!("typed map relocation must not mremap: {events}");
        }
    }
    assert!(live.is_empty(), "unreleased owners {live:?}: {events}");
    assert_eq!(released.len(), report.successful, "{events}");
    if report.successful != 0 {
        // The first mapping backs every borrowed Text. It must outlive all
        // current and superseded map allocations, including failed transfer.
        assert_eq!(
            released.last(),
            Some(&0),
            "input backing retired before map storage: {events}"
        );
    }
    report
}

struct Run {
    output: Output,
    events: String,
    memory: Memory,
}
fn run(
    executable: &common::TempArtifact,
    input: &[u8],
    args: &[&str],
    injections: &[&str],
    closed_stdout: bool,
) -> Run {
    let data = common::TempArtifact::new("laniusc_index_words", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_index_words", "trace", None);
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
    // output preserves the actual closed pipe; the external timeout bounds it.
    let output = command.output().expect("bounded index_words native case");
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

fn checked(run: &Run, status: i32, stdout: &[u8], signal_ok: bool) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
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
    let action = run
        .events
        .lines()
        .position(|line| line.starts_with("rt_sigaction("))
        .unwrap();
    if let Some(next) = run.events.lines().position(|line| {
        line.starts_with("mmap(") || line.starts_with("read(") || line.starts_with("write(")
    }) {
        assert!(action < next, "{}", run.events);
    }
    for read in calls(&run.events, "read") {
        assert!(read.starts_with("read(0,"), "{}", run.events);
    }
    for write in calls(&run.events, "write") {
        assert!(write.starts_with("write(1,"), "{}", run.events);
    }
    if matches!(status, 2 | 4 | 6 | 7 | 8) {
        assert!(calls(&run.events, "write").is_empty(), "{}", run.events);
    }
}
fn profile(run: &Run, attempts: usize, failed: Option<usize>) {
    assert_eq!(run.memory.attempts, attempts, "{}", run.events);
    if let Some(ordinal) = failed {
        assert_eq!(run.memory.failures, [ordinal], "{}", run.events);
        assert_eq!(run.memory.successful, attempts - 1, "{}", run.events);
    } else {
        assert!(run.memory.failures.is_empty(), "{}", run.events);
        assert_eq!(run.memory.successful, attempts, "{}", run.events);
    }
}

fn ascii_space(byte: u8) -> bool {
    matches!(byte, b' ' | 9..=13)
}
fn reference(input: &[u8]) -> (i32, Vec<u8>) {
    if input.len() > MAX_INPUT {
        return (7, Vec::new());
    }
    if std::str::from_utf8(input).is_err() {
        return (6, Vec::new());
    }
    let mut index = BTreeMap::<&[u8], u64>::new();
    for (position, word) in input
        .split(|&byte| ascii_space(byte))
        .filter(|word| !word.is_empty())
        .enumerate()
    {
        match index.entry(word) {
            std::collections::btree_map::Entry::Vacant(entry) => {
                entry.insert(position as u64 + 1);
            }
            std::collections::btree_map::Entry::Occupied(_) => return (8, Vec::new()),
        }
    }
    let mut output = Vec::new();
    for (word, position) in index {
        output.extend_from_slice(position.to_string().as_bytes());
        output.push(b'\t');
        output.extend_from_slice(word);
        output.push(b'\n');
    }
    (0, output)
}

#[test]
fn index_words_unique_positions_transfer_and_exact_failure_cleanup() {
    let executable = executable(); // One production-root compile/strict ELF.
    let cases: &[&[u8]] = &[
        b"",
        b" \t\n\x0b\x0c\r ",
        b"single",
        b"pear apple banana",
        b"b a B A",
        b"z\ta\nb\x0bc\x0cd\re",
        b"a\0b a\0a a",
        "é e\u{301} É café 🦀 漢字".as_bytes(),
        "a\u{00a0}b c".as_bytes(),
        b"aa a aaa",
        b"9 10 2 -1 +1",
        b"a b c d",
        b"d c b a",
        b"\xff",
        b"valid words \xff",
        b"\xe2\x82",
        b"\xc0\xaf",
        b"\xed\xa0\x80",
        b"\xf4\x90\x80\x80",
        b"same same \xff", // Complete UTF-8 validation precedes duplicates.
    ];
    for &input in cases {
        let (status, expected) = reference(input);
        let observed = run(&executable, input, &[], &[], false);
        checked(&observed, status, &expected, true);
        if status == 6 || input.iter().all(|&byte| ascii_space(byte)) {
            profile(&observed, 1, None);
        } else {
            assert!(observed.memory.attempts >= 2, "{}", observed.events);
        }
    }
    for input in [
        b"a a".as_slice(),
        b"a b a",
        b"b a b",
        b"x y z y",
        b"z a b c a d",
        b"a b c d d",
    ] {
        assert_eq!(reference(input), (8, Vec::new()));
        let observed = run(&executable, input, &[], &[], false);
        checked(&observed, 8, b"", true);
    }
    let mut crossing = vec![b'x'; 1023];
    crossing.extend_from_slice("é a".as_bytes());
    for input in [
        crossing,
        vec![b'x'; MAX_INPUT],
        vec![b' '; MAX_INPUT],
        vec![b' '; MAX_INPUT + 1],
    ] {
        let (status, expected) = reference(&input);
        let observed = run(&executable, &input, &[], &[], false);
        checked(&observed, status, &expected, true);
        if expected.is_empty() {
            profile(&observed, 1, None);
        }
    }

    // A duplicate at either end of the ordered keys must not grow storage,
    // even when the accepted prefix exactly fills the existing capacity.
    let prefix = run(&executable, b"d b c a", &[], &[], false);
    checked(&prefix, 0, &reference(b"d b c a").1, true);
    for input in [b"d b c a d".as_slice(), b"d b c a a"] {
        let observed = run(&executable, input, &[], &[], false);
        checked(&observed, 8, b"", true);
        profile(&observed, prefix.memory.attempts, None);
    }

    let reverse = (0..2048)
        .rev()
        .map(|index| format!("w{index:04}"))
        .collect::<Vec<_>>()
        .join(" ")
        .into_bytes();
    let observed = run(&executable, &reverse, &[], &[], false);
    checked(&observed, 0, &reference(&reverse).1, true);
    let large = (0..4096)
        .map(|index| format!("w{:04}", (index * 37) % 4096))
        .collect::<Vec<_>>()
        .join(" ")
        .into_bytes();
    let large_expected = reference(&large).1;
    let baseline = run(&executable, &large, &[], &[], false);
    checked(&baseline, 0, &large_expected, true);
    assert!(
        baseline.memory.attempts > 2,
        "baseline must exercise typed map relocation: {}",
        baseline.events
    );
    profile(&baseline, baseline.memory.attempts, None);
    let mut late_duplicate = large.clone();
    late_duplicate.extend_from_slice(b" w0000");
    let observed = run(&executable, &late_duplicate, &[], &[], false);
    checked(&observed, 8, b"", true);
    profile(&observed, baseline.memory.attempts, None);
    eprintln!(
        "index_words: one strict ELF, {} observed allocation positions, {} native cases including every allocation denial",
        baseline.memory.attempts,
        53 + baseline.memory.attempts
    );
    let baseline_reads = calls(&baseline.events, "read").len();
    // Every observed input/map allocation attempt is individually denied.
    // The test does not assume Text/Node width or a particular growth factor.
    for ordinal in 1..=baseline.memory.attempts {
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(&executable, &large, &[], &[&injection], false);
        checked(&observed, 4, b"", true);
        profile(&observed, ordinal, Some(ordinal));
        assert_eq!(
            calls(&observed.events, "read").len(),
            if ordinal == 1 { 0 } else { baseline_reads },
            "{}",
            observed.events
        );
    }

    let input = b"zebra alpha beta";
    let expected = reference(input).1;
    assert_eq!(expected, b"2\talpha\n3\tbeta\n1\tzebra\n");
    let small = run(&executable, input, &[], &[], false);
    checked(&small, 0, &expected, true);
    let small_maps = small.memory.attempts;
    for (injection, status, output, reads) in [
        ("read:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("read:error=EIO:when=2", 3, b"".as_slice(), 2),
        ("read:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("read:retval=1025:when=1", 3, b"".as_slice(), 1),
        ("read:error=EINTR:when=1", 0, expected.as_slice(), 3),
    ] {
        let observed = run(&executable, input, &[], &[injection], false);
        checked(&observed, status, output, true);
        profile(&observed, if status == 0 { small_maps } else { 1 }, None);
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
        ("write:error=EIO:when=2", 3, b"2\t".as_slice(), 2),
        ("write:error=EIO:when=3", 3, b"2\talpha".as_slice(), 3),
        ("write:error=EIO:when=4", 3, b"2\talpha\n".as_slice(), 4),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, expected.as_slice(), 10),
        ("write:retval=1:when=1", 0, &expected[1..], 10),
    ] {
        let observed = run(&executable, input, &[], &[injection], false);
        checked(&observed, status, output, true);
        profile(&observed, small_maps, None);
        let writes_observed = calls(&observed.events, "write");
        assert_eq!(writes_observed.len(), writes, "{}", observed.events);
        if injection.contains("retval=1") {
            // strace suppresses the first host write while reporting one byte.
            // The real next call emits only TAB, then the rest of the row.
            let (arguments, _) = result(writes_observed[1], "write");
            assert_eq!(
                arguments.rsplit_once(',').unwrap().1.trim(),
                "1",
                "{}",
                observed.events
            );
        }
    }
    let observed = run(&executable, input, &[], &[], true);
    checked(&observed, 3, b"", true);
    profile(&observed, small_maps, None);
    let writes = calls(&observed.events, "write");
    assert_eq!(writes.len(), 1, "{}", observed.events);
    assert!(
        writes[0].contains("EPIPE") && !writes[0].contains("INJECTED"),
        "{}",
        observed.events
    );
    let observed = run(
        &executable,
        input,
        &[],
        &["rt_sigaction:error=EINTR:when=1"],
        false,
    );
    checked(&observed, 3, b"", false);
    profile(&observed, 0, None);
    assert!(
        calls(&observed.events, "read").is_empty() && calls(&observed.events, "write").is_empty(),
        "{}",
        observed.events
    );
    let observed = run(&executable, input, &["extra"], &[], false);
    checked(&observed, 2, b"", true);
    profile(&observed, 0, None);
    assert!(
        calls(&observed.events, "read").is_empty(),
        "{}",
        observed.events
    );
}
