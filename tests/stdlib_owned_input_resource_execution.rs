//! Real allocation failures, retained owned prefixes and zero-copy text adoption.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

const LENGTH: usize = 262_147;

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/owned_input_resources/collection.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("owned input resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("owned input resources: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_owned_input_resources", "executable", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.split_once('(').unwrap().1.rsplit_once(')').unwrap().0
}
fn address(text: &str) -> u64 {
    u64::from_str_radix(text.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}

#[derive(Debug, Default)]
struct Collection {
    allocations: Vec<(usize, bool)>,
    reads: usize,
    eof: bool,
    failed: bool,
}
#[derive(Debug)]
struct Effects {
    collections: Vec<Collection>,
    allocations: usize,
    releases: usize,
    phases: usize,
}

fn effects(events: &str, stderr: &[u8]) -> Effects {
    let mut live = BTreeMap::<u64, usize>::new();
    let mut active: Option<Collection> = None;
    let mut report = Effects {
        collections: Vec::new(),
        allocations: 0,
        releases: 0,
        phases: 0,
    };
    let mut pure = false;
    let mut finished = false;
    let mut entries = 0;
    let mut exits = 0;
    let mut configuration_reads = 0;
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            let marker = [b'C', b'F', b'R', b'E', b'P', b'p', b'D']
                .into_iter()
                .find(|marker| line.contains(&format!("\"{}\", 1)", char::from(*marker))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            assert!(!finished, "no effects after D: {events}");
            markers.push(marker);
            match marker {
                b'C' => {
                    assert!(!pure && active.is_none(), "{events}");
                    active = Some(Collection::default());
                }
                b'R' => {
                    assert!(!pure, "{events}");
                    let current = active.as_mut().unwrap();
                    assert!(
                        !current.eof && !current.failed,
                        "no read after EOF/allocation error: {events}"
                    );
                    current.reads += 1;
                }
                b'E' => {
                    assert!(!pure, "{events}");
                    let current = active.as_mut().unwrap();
                    assert!(
                        !current.eof && !current.failed && current.reads > 0,
                        "{events}"
                    );
                    current.eof = true;
                }
                b'F' => {
                    assert!(!pure, "{events}");
                    let current = active.take().unwrap();
                    assert!(
                        current.eof || current.failed,
                        "terminal cause observed: {events}"
                    );
                    report.collections.push(current);
                }
                b'P' => {
                    assert!(!pure && active.is_none(), "{events}");
                    pure = true;
                }
                b'p' => {
                    assert!(pure && active.is_none(), "{events}");
                    pure = false;
                    report.phases += 1;
                }
                b'D' => {
                    assert!(
                        !pure && active.is_none() && live.is_empty(),
                        "complete owner cleanup before D: {events}"
                    );
                    finished = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "transfer/adoption phase reached a host service: {line}"
        );
        if let Some(current) = active.as_ref() {
            assert!(
                !current.eof && !current.failed,
                "no allocation, release or other host work after EOF/failure before collection returns: {line}"
            );
        }
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(finished, "{events}");
            exits += 1;
            continue;
        }
        assert!(!finished, "only process exit follows D: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            assert!(
                report.collections.is_empty() && active.is_none() && entries == 0,
                "{events}"
            );
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                entries == 1
                    && configuration_reads == 0
                    && active.is_none()
                    && report.collections.is_empty(),
                "one configuration byte before collection: {events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).trim_end().ends_with(", 1"), "{events}");
            configuration_reads += 1;
        } else if line.starts_with("mmap(") {
            let current = active.as_mut().expect("collection reserves before reading");
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields[0], "NULL", "{events}");
            let length: usize = fields[1].parse().unwrap();
            assert!(length > 0, "{events}");
            let value = result(line);
            let pointer = value.split_whitespace().next().unwrap();
            if pointer.starts_with("0x") {
                assert!(!value.contains("INJECTED"), "{events}");
                assert!(
                    live.insert(address(pointer), length).is_none(),
                    "distinct live owner: {events}"
                );
                report.allocations += 1;
                current.allocations.push((length, true));
            } else {
                assert!(
                    pointer == "-1" && value.contains("ENOMEM") && value.contains("INJECTED"),
                    "reached ENOMEM only: {events}"
                );
                current.allocations.push((length, false));
                current.failed = true;
            }
        } else if line.starts_with("munmap(") {
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            assert_eq!(
                live.remove(&address(pointer)),
                Some(length),
                "exact address/length once-only release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            report.releases += 1;
        } else if line.starts_with("write(1,") {
            assert!(
                active.is_none(),
                "observe only completed collection: {events}"
            );
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = result(line).parse().unwrap();
            assert!(used > 0 && used <= requested, "{events}");
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        finished && !pure && active.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!((entries, exits, configuration_reads), (1, 1, 1), "{events}");
    assert_eq!(report.allocations, report.releases, "{events}");
    assert_eq!(
        stderr, markers,
        "native markers and trace must agree: {events}"
    );
    report
}

#[derive(Debug)]
struct Record {
    words: [i32; 12],
    bytes: Vec<u8>,
}
fn records(mut bytes: &[u8]) -> Vec<Record> {
    let mut result = Vec::new();
    while !bytes.is_empty() {
        assert!(bytes.len() >= 48, "truncated observation header");
        let words: [i32; 12] = std::array::from_fn(|index| {
            i32::from_le_bytes(bytes[index * 4..index * 4 + 4].try_into().unwrap())
        });
        let length = usize::try_from(words[2]).unwrap();
        assert!(
            length <= LENGTH && bytes.len() - 48 >= length,
            "bounded complete byte observation"
        );
        result.push(Record {
            words,
            bytes: bytes[48..48 + length].to_vec(),
        });
        bytes = &bytes[48 + length..];
    }
    result
}

fn data(mode: u8, index: usize) -> u8 {
    if mode == 0 || mode == 3 {
        return ((index * 37 + index / 251) % 256) as u8;
    }
    if mode == 2 && index == 1300 {
        return 255;
    }
    if index > 0 && index % 1024 == 0 {
        return 162;
    }
    if index % 1024 == 1023 {
        return 194;
    }
    if index % 17 == 0 {
        return 0;
    }
    (65 + index % 26) as u8
}
fn capacity_steps(maximum: usize) -> Vec<usize> {
    if maximum == 0 {
        return Vec::new();
    }
    let mut values = vec![maximum.min(1024)];
    while *values.last().unwrap() < maximum {
        values.push((values.last().unwrap() * 2).min(maximum));
    }
    values
}
fn checked_record(
    record: &Record,
    stage: i32,
    mode: u8,
    cause: i32,
    calls: usize,
    position: usize,
    total_calls: usize,
    capacity: usize,
    start: usize,
    repaired: bool,
) {
    let length = if mode == 3 { 1 } else { LENGTH };
    assert_eq!(
        record.words,
        [
            stage,
            cause,
            record.bytes.len() as i32,
            calls as i32,
            position as i32,
            total_calls as i32,
            capacity as i32,
            -1,
            if cause == 2 { 1300 } else { -1 },
            length as i32,
            i32::from(mode),
            0
        ]
    );
    let expected: Vec<_> = (start..start + record.bytes.len())
        .map(|index| {
            if repaired && index == 1300 {
                65
            } else {
                data(mode, index)
            }
        })
        .collect();
    assert_eq!(
        record.bytes, expected,
        "every error-owned/recovered raw byte"
    );
}

fn run(
    executable: &common::TempArtifact,
    mode: u8,
    failed_at: Option<usize>,
) -> (Vec<Record>, Effects) {
    let input = common::TempArtifact::new("laniusc_owned_input_resources", "mode", None);
    input.write_bytes([mode]);
    let trace = common::TempArtifact::new("laniusc_owned_input_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = failed_at {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let output = common::process_output_with_timeout(
        "owned input finite resource schedule",
        &mut command,
        Duration::from_secs(10),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode} failure={failed_at:?}: {output:?}\n{events}"
    );
    let injected: Vec<_> = events
        .lines()
        .filter(|line| line.contains("INJECTED"))
        .collect();
    assert_eq!(
        injected.len(),
        usize::from(failed_at.is_some()),
        "one genuine reached fault: {events}"
    );
    let effects = effects(&events, &output.stderr);
    (records(&output.stdout), effects)
}

#[test]
fn owned_input_geometric_growth_and_text_adoption_release_actual_owners() {
    let executable = executable();
    for mode in 0..=3 {
        let (records, effects) = run(&executable, mode, None);
        let length = if mode == 3 { 1 } else { LENGTH };
        let calls = if mode == 3 {
            2
        } else {
            LENGTH.div_ceil(1024) + 1
        };
        let capacity = if mode == 3 { 2048 } else { LENGTH };
        let cause = if mode == 2 { 2 } else { 0 };
        assert_eq!(records.len(), if mode == 2 { 2 } else { 1 });
        assert_eq!(records[0].bytes.len(), length);
        checked_record(
            &records[0],
            0,
            mode,
            cause,
            calls,
            length,
            calls,
            capacity,
            0,
            false,
        );
        assert_eq!(effects.collections.len(), 1);
        let current = &effects.collections[0];
        let expected = if mode == 3 {
            vec![1024, 2048]
        } else {
            capacity_steps(LENGTH)
        };
        assert_eq!(
            current.allocations,
            expected
                .into_iter()
                .map(|size| (size, true))
                .collect::<Vec<_>>()
        );
        assert_eq!(current.reads, calls);
        assert!(current.eof && !current.failed);
        assert_eq!(effects.phases, usize::from(mode == 1 || mode == 2));
        if mode == 2 {
            assert_eq!(records[1].bytes.len(), LENGTH);
            checked_record(&records[1], 1, mode, 0, 0, LENGTH, calls, LENGTH, 0, true);
        }
        eprintln!(
            "owned-input-resource mode={mode} bytes={length} calls={calls} maps={} releases={} pure-phases={}",
            effects.allocations, effects.releases, effects.phases
        );
    }
}

#[test]
fn owned_input_reached_allocation_failures_precede_consumption_and_allow_recovery() {
    let executable = executable();
    // First, second, middle and last growth points plus text and unobserved EOF.
    let schedules = [
        (0, 1, 0, 0, 0),
        (0, 2, 1024, 1, 1024),
        (0, 5, 8192, 8, 8192),
        (0, 10, 262144, 256, 262144),
        (1, 1, 0, 0, 0),
        (1, 5, 8192, 8, 8192),
        (3, 2, 1, 1, 1024),
    ];
    for (mode, ordinal, prefix, calls, capacity) in schedules {
        let (records, effects) = run(&executable, mode, Some(ordinal));
        let length = if mode == 3 { 1 } else { LENGTH };
        let remaining = length - prefix;
        let recovery_calls = remaining.div_ceil(1024) + 1;
        assert_eq!(records.len(), 2);
        assert_eq!(records[0].bytes.len(), prefix);
        assert_eq!(records[1].bytes.len(), remaining);
        checked_record(
            &records[0],
            0,
            mode,
            1,
            calls,
            prefix,
            calls,
            capacity,
            0,
            false,
        );
        checked_record(
            &records[1],
            1,
            mode,
            0,
            recovery_calls,
            length,
            calls + recovery_calls,
            remaining,
            prefix,
            false,
        );
        assert_eq!(effects.collections.len(), 2);
        assert_eq!(effects.phases, 0);
        let first = &effects.collections[0];
        let sizes = if mode == 3 {
            vec![1024, 2048]
        } else {
            capacity_steps(LENGTH)
        };
        let expected: Vec<_> = sizes
            .into_iter()
            .take(ordinal)
            .enumerate()
            .map(|(index, size)| (size, index + 1 != ordinal))
            .collect();
        assert_eq!(first.allocations, expected);
        assert_eq!(first.reads, calls);
        assert!(first.failed && !first.eof);
        let recovery = &effects.collections[1];
        assert_eq!(
            recovery.allocations,
            capacity_steps(remaining)
                .into_iter()
                .map(|size| (size, true))
                .collect::<Vec<_>>()
        );
        assert_eq!(recovery.reads, recovery_calls);
        assert!(recovery.eof && !recovery.failed);
        let combined: Vec<_> = records[0]
            .bytes
            .iter()
            .chain(&records[1].bytes)
            .copied()
            .collect();
        assert_eq!(
            combined,
            (0..length)
                .map(|index| data(mode, index))
                .collect::<Vec<_>>(),
            "no dropped, duplicated or invented bytes after recovery"
        );
        eprintln!(
            "owned-input-resource fault-mode={mode} reached-mmap={ordinal} retained={prefix} calls={calls} recovered={remaining} maps={} releases={}",
            effects.allocations, effects.releases
        );
    }
}
