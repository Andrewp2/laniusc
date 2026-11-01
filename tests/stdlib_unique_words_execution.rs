//! Streaming UTF-8 deduplication through reusable owned String batch cursors.
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
    let entry = root.join("sample_programs/library/unique_words.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("unique_words application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("unique_words: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_unique_words", "executable", None);
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
    batch_length: Option<usize>,
    requests: Vec<String>,
    // Old/new successful allocation identities and extents for an immediate
    // allocate-larger/retire-old exchange. Identities survive address reuse.
    growths: Vec<(usize, usize, usize, usize)>,
}
fn memory(events: &str) -> Memory {
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut report = Memory {
        attempts: 0,
        successful: 0,
        failures: Vec::new(),
        batch_length: None,
        requests: Vec::new(),
        growths: Vec::new(),
    };
    let mut latest_allocation = None;
    let mut released = Vec::new();
    let mut batch_release = None;
    let first_write = events.lines().position(|line| line.starts_with("write("));
    let last_read = events
        .lines()
        .enumerate()
        .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
        .last();
    for (line_index, line) in events.lines().enumerate() {
        if line.starts_with("mmap(") {
            assert!(
                first_write.is_none_or(|first| line_index < first),
                "publication must not allocate: {events}"
            );
            let (arguments, value) = result(line, "mmap");
            let mut fields = arguments.split(',').map(str::trim);
            assert_eq!(fields.next(), Some("NULL"), "{events}");
            let length: usize = fields.next().unwrap().parse().unwrap();
            assert!(length > 0, "{events}");
            report.attempts += 1;
            report.requests.push(arguments.to_owned());
            let address = value.split_whitespace().next().unwrap();
            if let Some(address) = address.strip_prefix("0x") {
                assert!(!value.contains("INJECTED"), "{events}");
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(
                    live.insert(address, (report.successful, length)).is_none(),
                    "duplicate live mapping: {events}"
                );
                if report.successful == 0 {
                    report.batch_length = Some(length);
                }
                latest_allocation = Some((line_index, address, report.successful, length));
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
            if let Some((allocated_at, new_address, new_identity, new_length)) = latest_allocation {
                if allocated_at + 1 == line_index
                    && new_identity != identity
                    && new_length > owned_length
                {
                    assert_eq!(
                        live.get(&new_address),
                        Some(&(new_identity, new_length)),
                        "{events}"
                    );
                    report
                        .growths
                        .push((identity, new_identity, owned_length, new_length));
                }
            }
            if identity == 0 {
                batch_release = Some(line_index);
            }
            released.push(identity);
        } else if line.starts_with("mremap(") {
            panic!("typed owner relocation must not mremap: {events}");
        }
    }
    assert!(live.is_empty(), "unreleased owners {live:?}: {events}");
    assert_eq!(released.len(), report.successful, "{events}");
    if report.successful != 0 {
        // The first allocation is the batch backing. It must survive every
        // read/flush and be retired before publication, without assuming its
        // physical String width. Identity survives reuse of a host address.
        let release = batch_release.unwrap();
        assert!(
            last_read.is_none_or(|last| release > last),
            "batch backing released before collection ended: {events}"
        );
        assert!(
            first_write.is_none_or(|first| release < first),
            "batch backing retained during publication: {events}"
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
    let data = common::TempArtifact::new("laniusc_unique_words", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_unique_words", "trace", None);
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
    let output = command.output().expect("bounded unique_words native case");
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
    if status == 0 || !calls(&run.events, "write").is_empty() {
        let reads = calls(&run.events, "read");
        assert_eq!(
            result(reads.last().unwrap(), "read").1,
            "0",
            "success/publication requires actual EOF: {}",
            run.events
        );
    }
    if let Some(first_write) = run
        .events
        .lines()
        .position(|line| line.starts_with("write("))
    {
        let last_read = run
            .events
            .lines()
            .enumerate()
            .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
            .last()
            .unwrap();
        assert!(
            first_write > last_read,
            "publication before EOF: {}",
            run.events
        );
    }
    if status == 2 || status == 4 || status == 6 || status == 7 {
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

fn reached_storage_growth(run: &Run, first_word_bytes: usize) {
    let lines = run.events.lines().collect::<Vec<_>>();
    let reads = lines
        .iter()
        .enumerate()
        .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
        .collect::<Vec<_>>();
    assert!(
        reads.len() >= 3,
        "representative must cross an input read: {}",
        run.events
    );
    let first_read_bytes: usize = result(lines[reads[0]], "read").1.parse().unwrap();
    assert!(first_read_bytes < first_word_bytes);
    // The first word is unfinished after the first read. Its one new mapping
    // before the next read is token storage, not an independent String or set.
    let token_maps = (reads[0] + 1..reads[1])
        .filter(|&index| lines[index].starts_with("mmap("))
        .collect::<Vec<_>>();
    assert_eq!(token_maps.len(), 1, "{}", run.events);
    let token_identity = lines[..token_maps[0]]
        .iter()
        .filter(|line| line.starts_with("mmap("))
        .count();
    let token_growth = run
        .memory
        .growths
        .iter()
        .find(|growth| growth.0 == token_identity)
        .expect("the split first word must reach replacement token storage");
    assert!(token_growth.2 >= first_read_bytes && token_growth.3 >= first_word_bytes);
    // Apart from that token buffer, only the set grows backing in this source.
    // Require linked real replacement generations, without assuming Node or
    // String layout, a total allocation count, or exact capacity increments.
    assert!(
        run.memory.growths.iter().any(|first| {
            first.0 != token_identity
                && run
                    .memory
                    .growths
                    .iter()
                    .any(|next| next.0 == first.1 && next.2 == first.3)
        }),
        "representative must reach repeated set-storage growth: {}",
        run.events
    );
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
    let words = input
        .split(|&byte| ascii_space(byte))
        .filter(|word| !word.is_empty())
        .collect::<std::collections::BTreeSet<_>>();
    let mut output = Vec::new();
    for word in words {
        output.extend_from_slice(word);
        output.push(b'\n');
    }
    (0, output)
}
fn read_request(line: &str) -> usize {
    result(line, "read")
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}
fn assert_eof_probe(run: &Run, exceeded: bool) {
    let reads = calls(&run.events, "read");
    let last = reads.last().unwrap();
    assert_eq!(read_request(last), 1, "{}", run.events);
    assert_eq!(
        result(last, "read").1,
        if exceeded { "1" } else { "0" },
        "{}",
        run.events
    );
}

#[test]
fn unique_words_streaming_owners_reuse_and_exact_failure_cleanup() {
    let executable = executable(); // One production-root compile/strict ELF.
    let mut native_cases = 0usize;
    let mut single_copy_requests = None;
    let cases: &[&[u8]] = &[
        b"",
        b" \t\n\x0b\x0c\r ",
        b"same ",
        b"b a b A a",
        b"z\ta\nb\x0bc\x0cd\re",
        b"a\0b a\0a a a\0b",
        "é e\u{301} É café 🦀 漢字 é".as_bytes(),
        "a\u{00a0}b c a\u{00a0}b".as_bytes(),
        b"aa a aaa aa",
        b"9 10 2 -1 +1",
        b"a b c d",
        b"d c b a",
        b"\xff",
        b"valid words \xff",
        b"\xe2\x82",
        b"\xc0\xaf",
        b"\xed\xa0\x80",
        b"\xf4\x90\x80\x80",
    ];
    for &input in cases {
        let (status, expected) = reference(input);
        let observed = run(&executable, input, &[], &[], false);
        native_cases += 1;
        checked(&observed, status, &expected, true);
        if input == b"same " {
            single_copy_requests = Some(observed.memory.requests.clone());
        }
        if input.iter().all(|&byte| ascii_space(byte)) {
            profile(&observed, 1, None);
        }
    }
    let mut crossing = vec![b'x'; 1023];
    crossing.extend_from_slice("é a".as_bytes());
    let mut crossing_four = vec![b' '; 1022];
    crossing_four.extend_from_slice("🦀 b 🦀".as_bytes());
    let mut long_word = vec![b'z'; 4097];
    long_word.extend_from_slice(b" a ");
    long_word.extend_from_slice(&vec![b'z'; 4097]);
    let mut crossing_invalid = vec![b'x'; 1023];
    crossing_invalid.extend_from_slice(b"\xe2\x82");
    for input in [
        crossing,
        crossing_four,
        long_word,
        crossing_invalid,
        vec![b'x'; MAX_INPUT],
        vec![b' '; MAX_INPUT],
        vec![b' '; MAX_INPUT + 1],
    ] {
        let (status, expected) = reference(&input);
        let observed = run(&executable, &input, &[], &[], false);
        native_cases += 1;
        checked(&observed, status, &expected, true);
        if input.len() >= MAX_INPUT {
            assert_eof_probe(&observed, input.len() > MAX_INPUT);
        }
    }

    // A borrowed lookup skips owned-key construction for pending and committed
    // duplicates. Reuse the earlier one-token process as the baseline: 64 and
    // 192 completed tokens must have exactly its allocation request sequence.
    let once = b"same ".repeat(64);
    let repeated = b"same ".repeat(192);
    let one_batch = run(&executable, &once, &[], &[], false);
    native_cases += 1;
    checked(&one_batch, 0, b"same\n", true);
    let three_batches = run(&executable, &repeated, &[], &[], false);
    native_cases += 1;
    checked(&three_batches, 0, b"same\n", true);
    let single_copy_requests = single_copy_requests.unwrap();
    assert_eq!(one_batch.memory.requests, single_copy_requests);
    assert_eq!(three_batches.memory.requests, single_copy_requests);
    assert_eq!(
        three_batches.memory.batch_length,
        one_batch.memory.batch_length
    );

    // This same three-key vocabulary crosses both real read boundaries and
    // completed-token windows. Duplicate traffic must add no allocation, even
    // when a later read splits a token. First-pass and repeated output are the
    // independent BTreeSet reference, not a production traversal transcript.
    let vocabulary = b"alpha beta gamma ";
    let repeated_vocabulary = vocabulary.repeat(192);
    assert!(repeated_vocabulary.len() > 2 * 1024 && 3 * 192 > 2 * 64);
    let vocabulary_once = run(&executable, vocabulary, &[], &[], false);
    native_cases += 1;
    checked(&vocabulary_once, 0, &reference(vocabulary).1, true);
    let vocabulary_many = run(&executable, &repeated_vocabulary, &[], &[], false);
    native_cases += 1;
    checked(
        &vocabulary_many,
        0,
        &reference(&repeated_vocabulary).1,
        true,
    );
    assert_eq!(
        vocabulary_once.memory.requests,
        vocabulary_many.memory.requests
    );
    assert_eq!(
        vocabulary_once.memory.batch_length,
        vocabulary_many.memory.batch_length
    );
    assert!(
        calls(&vocabulary_many.events, "read").len() > calls(&vocabulary_once.events, "read").len()
    );
    let mut consumed = 0usize;
    let mut split_token = false;
    for read in calls(&vocabulary_many.events, "read") {
        consumed += result(read, "read").1.parse::<usize>().unwrap();
        if consumed > 0 && consumed < repeated_vocabulary.len() {
            split_token |= !ascii_space(repeated_vocabulary[consumed - 1])
                && !ascii_space(repeated_vocabulary[consumed]);
        }
    }
    assert_eq!(consumed, repeated_vocabulary.len());
    assert!(
        split_token,
        "repeated vocabulary must cross an observed read inside a word"
    );
    let repeated_lines = vocabulary_many.events.lines().collect::<Vec<_>>();
    let second_read = repeated_lines
        .iter()
        .enumerate()
        .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
        .nth(1)
        .unwrap();
    let final_allocation = repeated_lines
        .iter()
        .rposition(|line| line.starts_with("mmap("))
        .unwrap();
    // With only three pending keys, flushing by the number of novel keys would
    // postpone the first set allocation until EOF. A completed-token window
    // must commit this vocabulary during the first actual input chunk.
    assert!(
        final_allocation < second_read,
        "duplicate tokens must not postpone the first batch flush"
    );

    // A representative multi-batch sweep reaches token growth, independent
    // String allocation, borrowed duplicate suppression, set growth, final partial batch,
    // and an owning cursor whose rejected item has an unconsumed suffix.
    let representative = (0..70)
        .map(|index| {
            if index == 0 {
                "z".repeat(1300)
            } else {
                let key = match index {
                    7 | 64 => 1,
                    69 => 3,
                    _ => index,
                };
                format!("w{key:03}")
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
        .into_bytes();
    let representative_expected = reference(&representative).1;
    let baseline = run(&executable, &representative, &[], &[], false);
    native_cases += 1;
    checked(&baseline, 0, &representative_expected, true);
    profile(&baseline, baseline.memory.attempts, None);
    reached_storage_growth(&baseline, 1300);
    let allocation_positions = baseline.memory.attempts;
    for ordinal in 1..=allocation_positions {
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(&executable, &representative, &[], &[&injection], false);
        native_cases += 1;
        checked(&observed, 4, b"", true);
        profile(&observed, ordinal, Some(ordinal));
        assert_eq!(
            observed.memory.requests,
            baseline.memory.requests[..ordinal],
            "denial must reach the same allocation request prefix: {}",
            observed.events
        );
        if ordinal == 1 {
            assert!(
                calls(&observed.events, "read").is_empty(),
                "{}",
                observed.events
            );
        }
    }
    let mut invalid_late = representative.clone();
    invalid_late.extend_from_slice(b" \xff");
    let observed = run(&executable, &invalid_late, &[], &[], false);
    native_cases += 1;
    checked(&observed, 6, b"", true);
    let late_read = calls(&baseline.events, "read").len();
    let injection = format!("read:error=EIO:when={late_read}");
    let observed = run(&executable, &representative, &[], &[&injection], false);
    native_cases += 1;
    checked(&observed, 3, b"", true);
    assert_eq!(calls(&observed.events, "read").len(), late_read);
    assert!(
        calls(&observed.events, "write").is_empty(),
        "{}",
        observed.events
    );

    // Scale/correctness uses 4,096 input words, separately from the bounded
    // exhaustive fault sweep above; duplicates recur across many batch edges.
    let large = (0..4096)
        .rev()
        .map(|index| format!("w{:04}", (index * 37) % 997))
        .collect::<Vec<_>>()
        .join(" ")
        .into_bytes();
    let observed = run(&executable, &large, &[], &[], false);
    native_cases += 1;
    checked(&observed, 0, &reference(&large).1, true);

    let input = b"zebra alpha beta alpha";
    let expected = reference(input).1;
    assert_eq!(expected, b"alpha\nbeta\nzebra\n");
    let small = run(&executable, input, &[], &[], false);
    native_cases += 1;
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
        native_cases += 1;
        checked(&observed, status, output, true);
        if status == 0 {
            profile(&observed, small_maps, None);
        } else if reads == 1 {
            profile(&observed, 1, None);
        }
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
        ("write:error=EIO:when=2", 3, b"alpha".as_slice(), 2),
        ("write:error=EIO:when=3", 3, b"alpha\n".as_slice(), 3),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, expected.as_slice(), 7),
    ] {
        let observed = run(&executable, input, &[], &[injection], false);
        native_cases += 1;
        checked(&observed, status, output, true);
        profile(&observed, small_maps, None);
        let writes_observed = calls(&observed.events, "write");
        assert_eq!(writes_observed.len(), writes, "{}", observed.events);
    }
    let observed = run(&executable, input, &[], &[], true);
    native_cases += 1;
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
    native_cases += 1;
    checked(&observed, 3, b"", false);
    profile(&observed, 0, None);
    assert!(
        calls(&observed.events, "read").is_empty() && calls(&observed.events, "write").is_empty(),
        "{}",
        observed.events
    );
    let observed = run(&executable, input, &["extra"], &[], false);
    native_cases += 1;
    checked(&observed, 2, b"", true);
    profile(&observed, 0, None);
    assert!(
        calls(&observed.events, "read").is_empty(),
        "{}",
        observed.events
    );
    assert_eq!(native_cases, 48 + allocation_positions);
    eprintln!(
        "unique_words: one strict ELF, {allocation_positions} reached representative allocation denials, {native_cases} native cases; equal allocation sequences for 1/64/192 repeats and first/repeated vocabulary; 4096-word scale workload is correctness-only"
    );
}
