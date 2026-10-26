//! Lookahead ownership, exact poll order and useful shallow reductions.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/iterator_lookahead");
    let entry = if name == "column_extrema.lani" {
        root.join("sample_programs/library").join(name)
    } else {
        fixtures.join(name)
    };
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("lookahead {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("iterator_lookahead", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn success(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn mappings(trace: &str) -> (Vec<usize>, Vec<usize>) {
    let mut live = BTreeMap::new();
    let mut sizes = Vec::new();
    let mut released = Vec::new();
    for line in trace.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let size: usize = args.split(',').nth(1).unwrap().trim().parse().unwrap();
            sizes.push(size);
            let address = line.rsplit_once(" = ").unwrap().1.trim();
            assert!(address.starts_with("0x"), "{trace}");
            assert!(
                live.insert(address.to_owned(), (size, sizes.len()))
                    .is_none(),
                "{trace}"
            );
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (args, result) = tail.split_once(')').unwrap();
            let (address, size) = args.split_once(',').unwrap();
            let (actual, id) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("one live owner: {trace}"));
            assert_eq!(actual, size.trim().parse::<usize>().unwrap(), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
            released.push(id);
        } else {
            panic!("unexpected allocation service: {line}");
        }
    }
    assert!(live.is_empty(), "all owners released: {trace}");
    (sizes, released)
}
fn trace(exe: &common::TempArtifact) -> (Output, String) {
    let file = common::TempArtifact::new("iterator_lookahead", "mappings", None);
    let output = common::process_output_with_timeout(
        "lookahead mapping ledger",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(file.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(exe.path()),
        Duration::from_secs(8),
    );
    success(&output);
    (output, fs::read_to_string(file.path()).unwrap())
}

#[test]
fn nested_optional_cache_relative_positions_and_exact_bound_rejections() {
    let exe = executable("contracts.lani");
    let (output, events) = trace(&exe);
    assert!(output.stdout.is_empty());
    assert!(mappings(&events).0.is_empty());
    for (name, call) in [
        ("missing_ord.lani", "core::iter::min<"),
        ("wrong_comparator.lani", "core::iter::min_by<"),
        ("wrong_predicate.lani", "core::iter::position<"),
    ] {
        let error = match compile(name) {
            Err(error) => error,
            Ok(bytes) => panic!("{name} produced {} bytes", bytes.len()),
        };
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{error}");
        let label = diagnostic.primary_label.expect("actual source call");
        assert!(label.path.ends_with(name), "{label:?}");
        assert!(
            label.source_line.as_deref().unwrap_or("").contains(call),
            "{label:?}"
        );
    }
}
fn optional(words: &mut Vec<u64>, item: Option<u64>) {
    words.extend([u64::from(item.is_some()), item.unwrap_or(0)]);
}
fn rich(words: &mut Vec<u64>, item: Option<u64>, seed: u64) {
    optional(words, item);
    if let Some(id) = item {
        words.extend([
            (((id * 7 + seed * 3) % 5) as i64 - 2) as u64,
            u64::MAX - id,
            (-4_294_967_297 - id as i64) as u64,
            8_589_934_593 + id,
        ]);
    }
}
fn selected(ids: std::ops::Range<u64>, seed: u64, max: bool, reverse: bool) -> Option<u64> {
    // Sort independent (priority, source-position) keys: minima use earliest
    // ties, maxima latest. No heap/reduction transition is reproduced here.
    let key = |id: &u64| {
        let value = ((id * 7 + seed * 3) % 5) as i64 - 2;
        if reverse { -value } else { value }
    };
    if max {
        ids.max_by_key(key)
    } else {
        ids.min_by_key(key)
    }
}
#[test]
fn action_models_and_reduction_oracles_preserve_poll_callback_and_tie_contracts() {
    let exe = executable("model.lani");
    let (output, events) = trace(&exe);
    assert!(mappings(&events).0.is_empty());
    let mut expected = Vec::new();
    for length in 0..5_u64 {
        for schedule in 0..256_u64 {
            let (mut position, mut polls, mut cached, mut done) = (0, 0, None, false);
            for step in 0..4 {
                let op = (schedule >> (step * 2)) & 3;
                let mut value = None;
                let mut error = false;
                match op {
                    0 | 1 => {
                        if let Some(item) = cached {
                            value = Some(item);
                            if op == 1 {
                                cached = None;
                            }
                        } else if !done {
                            polls += 1;
                            if position < length {
                                value = Some(position);
                                position += 1;
                                if op == 0 {
                                    cached = value;
                                }
                            } else {
                                done = true;
                            }
                        }
                    }
                    2 => {
                        value = cached.take();
                    }
                    3 => {
                        if cached.is_some() {
                            error = true;
                        } else {
                            done = true;
                        }
                    }
                    _ => unreachable!(),
                }
                optional(&mut expected, value);
                expected.extend([
                    position,
                    polls,
                    u64::from(cached.is_some()),
                    u64::from(error),
                ]);
            }
            optional(&mut expected, cached.take());
            polls += 1;
            let raw = if position < length {
                let id = position;
                position += 1;
                Some(id)
            } else {
                None
            };
            optional(&mut expected, raw);
            expected.extend([position, polls]);
        }
    }
    for mode in 0..4_u64 {
        for seed in 0..8_u64 {
            for length in 0..10_u64 {
                let winner = selected(0..length, seed, mode == 1 || mode == 3, mode >= 2);
                rich(&mut expected, winner, seed);
                let calls = if mode >= 2 {
                    length.saturating_sub(1)
                } else {
                    0
                };
                expected.extend([length, length + 1, calls]);
                for next in 1..=calls {
                    expected.extend([selected(0..next, seed, mode == 3, true).unwrap(), next]);
                }
            }
        }
    }
    for start in 0..2_u64 {
        for length in 0..9_u64 {
            for target in 0..10_u64 {
                let found = (target < length).then_some(start * 7 + target);
                optional(&mut expected, found);
                let mut position = if found.is_some() { target + 1 } else { length };
                let mut polls = if found.is_some() {
                    position
                } else {
                    length + 1
                };
                expected.extend([position, polls, position]);
                polls += 1;
                let raw = if position < length {
                    let item = position;
                    position += 1;
                    Some(item)
                } else {
                    None
                };
                optional(&mut expected, raw);
                expected.extend([position, polls]);
            }
        }
    }
    assert_eq!(output.stdout.len() % 8, 0);
    let actual: Vec<_> = output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect();
    if actual != expected {
        let first = actual
            .iter()
            .zip(&expected)
            .position(|(a, b)| a != b)
            .unwrap_or(actual.len().min(expected.len()));
        panic!(
            "lookahead model word {first}, actual {:?}, expected {:?}, lengths {} vs {}",
            actual.get(first.saturating_sub(4)..(first + 6).min(actual.len())),
            expected.get(first.saturating_sub(4)..(first + 6).min(expected.len())),
            actual.len(),
            expected.len()
        );
    }
    eprintln!("1280 four-action schedules,320 extrema cases,180 position cases passed");
}
#[test]
fn cached_string_owners_and_borrowed_reduction_aliases_release_exactly_once() {
    let exe = executable("owners.lani");
    let (output, events) = trace(&exe);
    let width: usize = std::str::from_utf8(&output.stdout)
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    let (sizes, released) = mappings(&events);
    assert_eq!(
        sizes,
        [
            width * 3,
            4,
            4,
            4,
            width * 3,
            4,
            4,
            4,
            width * 4,
            4,
            4,
            4,
            4
        ],
        "{events}"
    );
    assert_eq!(
        released,
        [3, 4, 1, 2, 6, 7, 8, 5, 13, 12, 11, 10, 9],
        "cache ownership independent of source cleanup: {events}"
    );
}
#[test]
fn position_overflow_consumes_extra_item_then_panics_before_predicate() {
    let exe = executable("overflow.lani");
    let output = common::signal_process_output_with_timeout(
        "position overflow witness",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.signal(), Some(4), "{output:?}");
    assert_eq!(output.stdout, b"aPb");
    assert!(output.stderr.is_empty());
}
fn app_run(
    exe: &common::TempArtifact,
    args: &[&str],
    input: &[u8],
    stdout: Option<&Path>,
) -> Output {
    let file = common::TempArtifact::new("column_extrema", "stdin", None);
    file.write_bytes(input);
    // The common bounded collector always pipes its immediate child's stdout.
    // Put the intentional failing fd inside the child, as other sample gates do.
    let mut command = if let Some(path) = stdout {
        assert_eq!(path, Path::new("/dev/full"));
        let mut shell = Command::new("sh");
        shell
            .args(["-c", "exec \"$@\" > /dev/full", "column-extrema-output"])
            .arg(exe.path());
        shell
    } else {
        Command::new(exe.path())
    };
    command
        .args(args)
        .stdin(fs::File::open(file.path()).unwrap());
    common::process_output_with_timeout(
        "bounded column extrema",
        &mut command,
        Duration::from_secs(8),
    )
}
fn app_trace(exe: &common::TempArtifact, injection: Option<&str>) -> (Output, String) {
    let input = common::TempArtifact::new("column_extrema", "trace_input", None);
    input.write_bytes(b"1\n2\n");
    let file = common::TempArtifact::new("column_extrema", "fault_trace", None);
    let mut command = Command::new("strace");
    command.args(["-qq", "-o"]).arg(file.path()).args([
        "-e",
        "trace=mmap,munmap,write",
        "-e",
        "signal=none",
    ]);
    if let Some(fault) = injection {
        command.args(["-e", fault]);
    }
    command
        .arg(exe.path())
        .arg("1")
        .stdin(fs::File::open(input.path()).unwrap());
    let output = common::process_output_with_timeout(
        "column extrema fault cleanup",
        &mut command,
        Duration::from_secs(8),
    );
    (output, fs::read_to_string(file.path()).unwrap())
}
fn app_mappings(events: &str) -> (Vec<usize>, Vec<usize>) {
    // Writes are checked separately; preserve strict rejection of every other
    // unknown service in the allocation ledger.
    let memory = events
        .lines()
        .filter(|line| !line.starts_with("write("))
        .collect::<Vec<_>>()
        .join("\n");
    mappings(&memory)
}
fn injected_write(events: &str, request: usize, interrupted: bool) {
    let writes: Vec<_> = events
        .lines()
        .filter(|line| line.starts_with("write("))
        .collect();
    let injected: Vec<_> = writes
        .iter()
        .filter(|line| line.contains("(INJECTED)"))
        .collect();
    assert_eq!(
        injected.len(),
        1,
        "exactly one reached write fault: {events}"
    );
    assert_eq!(
        writes.len(),
        2,
        "one failed/short write and one retry: {events}"
    );
    assert_eq!(
        injected[0], &writes[0],
        "inject the initial write: {events}"
    );
    for line in &writes {
        assert!(
            line.starts_with("write(1, "),
            "only stdout writes: {events}"
        );
    }
    let count = |line: &str| -> usize {
        // Injected returns append `(INJECTED)` after the syscall result.
        line.split_once(") = ")
            .unwrap()
            .0
            .rsplit_once(", ")
            .unwrap()
            .1
            .parse()
            .unwrap()
    };
    assert_eq!(count(writes[0]), request, "{events}");
    let first = writes[0].rsplit_once("= ").unwrap().1.trim();
    if interrupted {
        assert!(
            first.starts_with("-1 EINTR "),
            "actual EINTR injection: {events}"
        );
        assert_eq!(
            count(writes[1]),
            request,
            "retry preserves offset after EINTR: {events}"
        );
    } else {
        assert_eq!(
            first, "2 (INJECTED)",
            "actual synthetic short write: {events}"
        );
        assert_eq!(
            count(writes[1]),
            request - 2,
            "retry advances offset after short write: {events}"
        );
    }
    let accepted = if interrupted { request } else { request - 2 };
    assert_eq!(
        writes[1].rsplit_once("= ").unwrap().1.trim(),
        accepted.to_string(),
        "retry succeeds: {events}"
    );
}
#[test]
fn column_extrema_reports_physical_tie_rows_and_rejects_bad_inputs_before_output() {
    let exe = executable("column_extrema.lani");
    let header = b"count,min,max,min_row,max_row\n";
    let cases: Vec<(&[&str], Vec<u8>, i32, Vec<u8>)> = vec![
        (
            &["2"],
            "# café\nα 8\n\nβ -5\nγ 8\nδ -5\n".as_bytes().to_vec(),
            0,
            [header.as_slice(), b"4,-5,8,4,5\n"].concat(),
        ),
        (
            &["1"],
            b"-9223372036854775808\n9223372036854775807".to_vec(),
            0,
            [
                header.as_slice(),
                b"2,-9223372036854775808,9223372036854775807,1,2\n",
            ]
            .concat(),
        ),
        (
            &["1"],
            b" \t\r\n # comment\n".to_vec(),
            0,
            [header.as_slice(), b"0,,,,\n"].concat(),
        ),
        (&["1"], vec![], 0, [header.as_slice(), b"0,,,,\n"].concat()),
        (&[], vec![], 2, vec![]),
        (&["0"], vec![], 2, vec![]),
        (&["4097"], vec![], 2, vec![]),
        (&["1", "2"], vec![], 2, vec![]),
        (&["1"], b"1\n# \xff\n".to_vec(), 6, vec![]),
        (&["2"], b"one 1\ntwo\n".to_vec(), 6, vec![]),
        (&["1"], b"1\n9223372036854775808\n".to_vec(), 6, vec![]),
        (&["1"], b"1x\n".to_vec(), 6, vec![]),
        (
            &["1"],
            [vec![b'#'], vec![b'x'; 65535]].concat(),
            0,
            [header.as_slice(), b"0,,,,\n"].concat(),
        ),
        (&["1"], [vec![b'#'], vec![b'x'; 65536]].concat(), 7, vec![]),
        (
            &["1"],
            b"1\n".repeat(4096),
            0,
            [header.as_slice(), b"4096,1,1,1,4096\n"].concat(),
        ),
        (&["1"], b"1\n".repeat(4097), 7, vec![]),
    ];
    for (args, input, status, expected) in cases {
        let output = app_run(&exe, args, &input, None);
        assert_eq!(
            output.status.code(),
            Some(status),
            "args {args:?}: {output:?}"
        );
        assert_eq!(output.stdout, expected, "args {args:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    let output = app_run(&exe, &["1"], b"1\n", Some(Path::new("/dev/full")));
    assert_eq!(output.status.code(), Some(3), "{output:?}");
    assert!(output.stderr.is_empty());
    let (healthy, events) = app_trace(&exe, None);
    success(&healthy);
    let expected = [header.as_slice(), b"2,1,2,1,2\n"].concat();
    assert_eq!(healthy.stdout, expected);
    let requests = app_mappings(&events).0;
    assert_eq!(
        requests.len(),
        4,
        "argv entries/bytes, input and numeric rows: {events}"
    );
    for index in 1..=requests.len() {
        let (output, events) = app_trace(
            &exe,
            Some(&format!("inject=mmap:error=ENOMEM:when={index}")),
        );
        assert_eq!(output.status.code(), Some(4), "OOM{index}: {output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
        let denied: Vec<_> = events
            .lines()
            .filter(|line| line.starts_with("mmap(") && line.contains("ENOMEM"))
            .collect();
        assert_eq!(denied.len(), 1, "{events}");
        let length: usize = denied[0].split(',').nth(1).unwrap().trim().parse().unwrap();
        assert_eq!(length, requests[index - 1], "{events}");
        let clean = events
            .lines()
            .filter(|line| !line.contains("ENOMEM"))
            .collect::<Vec<_>>()
            .join("\n");
        assert_eq!(
            app_mappings(&clean).0,
            requests[..index - 1],
            "each reached OOM preserves exact allocation prefix: {events}"
        );
    }
    let (interrupted, events) = app_trace(&exe, Some("inject=write:error=EINTR:when=1"));
    success(&interrupted);
    injected_write(&events, expected.len(), true);
    assert_eq!(interrupted.stdout, expected);
    assert_eq!(app_mappings(&events).0, requests);
    let (short, events) = app_trace(&exe, Some("inject=write:retval=2:when=1"));
    success(&short);
    injected_write(&events, expected.len(), false);
    // strace's synthetic successful return does not emit those first bytes.
    // The real retry must begin at the advanced offset, without duplicating it.
    assert_eq!(short.stdout, expected[2..]);
    assert_eq!(app_mappings(&events).0, requests);
}
