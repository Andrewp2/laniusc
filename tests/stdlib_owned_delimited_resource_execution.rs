//! Bounded owned record resources, pending bytes and honest physical boundaries.
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
const LENGTH: usize = 1_048_576;
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/owned_delimited_resources")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("owned delimited resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("owned delimited {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_owned_delimited_resources", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.rsplit_once('=')
        .unwrap()
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap()
        .split_once('(')
        .unwrap()
        .1
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
#[derive(Debug, Default)]
struct Operation {
    attempts: Vec<(usize, bool)>,
    fills: usize,
    consumes: usize,
    terminal: u8,
    failed: bool,
}
#[derive(Debug, Default)]
struct Effects {
    setup: Vec<usize>,
    operations: Vec<Operation>,
    allocations: usize,
    releases: usize,
    phases: usize,
    protections: usize,
}
fn effects(events: &str, stderr: &[u8], provider_markers: bool) -> Effects {
    let mut report = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut released = Vec::new();
    let mut active: Option<Operation> = None;
    let mut pure = false;
    let mut done = false;
    let mut markers = Vec::new();
    let (mut entries, mut exits, mut reads) = (0, 0, 0);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            assert!(!done, "{events}");
            let marker = [b'C', b'V', b'B', b'U', b'L', b'E', b'P', b'p', b'D']
                .into_iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(*byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            if let Some(operation) = active.as_ref() {
                if operation.failed || operation.terminal != 0 {
                    assert_eq!(
                        marker, b'V',
                        "no provider delegation after reserve failure/terminal acknowledgement: {events}"
                    );
                }
            }
            match marker {
                b'C' => {
                    assert!(!pure && active.is_none(), "{events}");
                    active = Some(Operation::default());
                }
                b'V' => {
                    assert!(!pure, "{events}");
                    let operation = active.take().unwrap();
                    if provider_markers {
                        assert!(operation.failed || operation.terminal != 0, "{events}");
                    }
                    report.operations.push(operation);
                }
                b'B' => {
                    assert!(provider_markers && !pure, "{events}");
                    active.as_mut().unwrap().fills += 1;
                }
                b'U' => {
                    assert!(provider_markers && !pure, "{events}");
                    let operation = active.as_mut().unwrap();
                    assert!(operation.fills > operation.consumes, "{events}");
                    operation.consumes += 1;
                }
                b'L' => {
                    assert!(provider_markers && !pure, "{events}");
                    let operation = active.as_mut().unwrap();
                    assert!(operation.consumes > 0, "{events}");
                    operation.terminal = b'L';
                }
                b'E' => {
                    assert!(provider_markers && !pure, "{events}");
                    let operation = active.as_mut().unwrap();
                    assert!(operation.fills > 0, "{events}");
                    operation.terminal = b'E';
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
                        "exact owner cleanup before D: {events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "no host service in transfer/admission/check phase: {line}"
        );
        if let Some(operation) = active.as_ref() {
            assert!(
                !operation.failed && operation.terminal == 0,
                "no host work after reserve failure/terminal provider return before API return: {line}"
            );
        }
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit after D: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            assert_eq!(entries, 0);
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                provider_markers && reads == 0 && active.is_none() && report.setup.is_empty(),
                "one mode read before setup: {events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields[0], "NULL", "{events}");
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0, "{events}");
            let value = result(line);
            let pointer = value.split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            if success {
                assert!(!value.contains("INJECTED"), "{events}");
                assert!(
                    live.insert(address(pointer), (size, report.allocations))
                        .is_none(),
                    "distinct live backing: {events}"
                );
                report.allocations += 1;
            } else {
                assert!(
                    pointer == "-1" && value.contains("ENOMEM") && value.contains("INJECTED"),
                    "only selected reached ENOMEM: {events}"
                );
            }
            if let Some(operation) = active.as_mut() {
                operation.attempts.push((size, success));
                operation.failed = !success;
            } else {
                assert!(
                    success && report.phases == 0 && report.operations.is_empty(),
                    "setup allocation before phases: {events}"
                );
                report.setup.push(size);
            }
        } else if line.starts_with("munmap(") {
            let (pointer, size) = arguments(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (expected, id) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown/double release: {line}"));
            assert_eq!(size, expected, "exact full owner extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            report.releases += 1;
            released.push(id);
        } else if line.starts_with("mprotect(") {
            assert!(
                !provider_markers
                    && report.setup == [8192]
                    && report.protections == 0
                    && report.phases == 0
                    && active.is_none()
                    && live.len() == 1,
                "{events}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            let (&pointer, &(size, _)) = live.iter().next().unwrap();
            assert_eq!(size, 8192);
            assert_eq!(pointer % 4096, 0);
            assert_eq!(address(fields[0]), pointer + 4096);
            assert_eq!(&fields[1..], &["4096", "PROT_NONE"]);
            assert_eq!(result(line), "0", "{events}");
            report.protections += 1;
        } else if line.starts_with("write(1,") {
            assert!(
                active.is_none(),
                "observe only completed API result: {events}"
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
        done && !pure && active.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!(
        (entries, exits, reads),
        (1, 1, usize::from(provider_markers)),
        "{events}"
    );
    assert_eq!(report.allocations, report.releases, "{events}");
    assert_eq!(
        released.last(),
        Some(&0),
        "provider/guard backing outlives all results: {events}"
    );
    assert_eq!(markers, stderr, "{events}");
    report
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    denied_collector_allocation: Option<usize>,
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_owned_delimited_resources", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_owned_delimited_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = denied_collector_allocation {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={}", ordinal + 1));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let output = common::process_output_with_timeout(
        "owned delimited finite native lifecycle",
        &mut command,
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode:?} denied={denied_collector_allocation:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(denied_collector_allocation.is_some()),
        "exactly one genuine reached reservation failure: {events}"
    );
    let effects = effects(&events, &output.stderr, mode.is_some());
    (output.stdout, effects)
}
fn data(mode: u8, index: usize) -> u8 {
    if index >= LENGTH {
        return b"NEXT\n"[index - LENGTH];
    }
    if index == LENGTH - 1 {
        return 10;
    }
    if mode == 0 || mode == 3 {
        let value = (index * 37 + index / 251) % 255;
        return (if value >= 10 { value + 1 } else { value }) as u8;
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
#[derive(Debug)]
struct Record {
    words: [i32; 12],
    bytes: Vec<u8>,
}
fn records(mut bytes: &[u8]) -> Vec<Record> {
    let mut records = Vec::new();
    while !bytes.is_empty() {
        assert!(bytes.len() >= 48);
        let words = std::array::from_fn(|i| {
            i32::from_le_bytes(bytes[i * 4..i * 4 + 4].try_into().unwrap())
        });
        let count = usize::try_from(words[3]).unwrap();
        assert!(count <= LENGTH && bytes.len() - 48 >= count);
        records.push(Record {
            words,
            bytes: bytes[48..48 + count].to_vec(),
        });
        bytes = &bytes[48 + count..];
    }
    records
}
fn capacities(length: usize, single: bool) -> Vec<usize> {
    if length == 0 {
        return Vec::new();
    }
    if single {
        return vec![length];
    }
    let mut values = vec![length.min(1024)];
    while *values.last().unwrap() < length {
        values.push((values.last().unwrap() * 2).min(length));
    }
    values
}
fn checked(
    record: &Record,
    stage: i32,
    mode: u8,
    cause: i32,
    calls: usize,
    consumed: usize,
    ending: i32,
    position: usize,
    fills: usize,
    consumes: usize,
    capacity: usize,
    start: usize,
) {
    assert_eq!(
        record.words,
        [
            stage,
            i32::from(mode),
            cause,
            record.bytes.len() as i32,
            calls as i32,
            consumed as i32,
            ending,
            position as i32,
            fills as i32,
            consumes as i32,
            capacity as i32,
            if cause == 2 { 1300 } else { -1 }
        ]
    );
    assert_eq!(
        record.bytes,
        (start..start + record.bytes.len())
            .map(|i| data(mode, i))
            .collect::<Vec<_>>(),
        "entire retained/recovered record bytes"
    );
}
fn tail_records(
    records: &[Record],
    operations: &[Operation],
    mode: u8,
    mut fills: usize,
    mut consumes: usize,
) {
    assert_eq!(records.len(), 2);
    assert_eq!(operations.len(), 2);
    fills += 1;
    consumes += 1;
    assert_eq!(records[0].bytes, b"NEXT\n");
    checked(
        &records[0],
        2,
        mode,
        0,
        2,
        5,
        1,
        LENGTH + 5,
        fills,
        consumes,
        5,
        LENGTH,
    );
    assert_eq!(operations[0].attempts, [(5, true)]);
    assert_eq!(
        (
            operations[0].fills,
            operations[0].consumes,
            operations[0].terminal
        ),
        (1, 1, b'L')
    );
    fills += 1;
    assert!(records[1].bytes.is_empty());
    checked(
        &records[1],
        3,
        mode,
        0,
        1,
        0,
        2,
        LENGTH + 5,
        fills,
        consumes,
        0,
        LENGTH + 5,
    );
    assert!(operations[1].attempts.is_empty());
    assert_eq!(
        (
            operations[1].fills,
            operations[1].consumes,
            operations[1].terminal
        ),
        (1, 0, b'E')
    );
}
#[test]
fn owned_delimited_megabyte_records_grow_geometrically_and_transfer_text_without_allocation() {
    let executable = executable("records.lani");
    for mode in 0..=3 {
        let (output, effects) = run(&executable, Some(mode), None);
        let records = records(&output);
        let chunks = if mode == 3 { 1 } else { 1024 };
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].bytes.len(), LENGTH);
        checked(
            &records[0],
            0,
            mode,
            if mode == 2 { 2 } else { 0 },
            chunks * 2,
            LENGTH,
            1,
            LENGTH,
            chunks,
            chunks,
            LENGTH,
            0,
        );
        assert_eq!(effects.setup, [LENGTH + 5]);
        assert_eq!(effects.operations.len(), 3);
        assert_eq!(effects.protections, 0);
        assert_eq!(effects.phases, if mode == 1 || mode == 2 { 3 } else { 2 });
        assert_eq!(
            effects.operations[0].attempts,
            capacities(LENGTH, mode == 3)
                .into_iter()
                .map(|n| (n, true))
                .collect::<Vec<_>>()
        );
        assert_eq!(
            (
                effects.operations[0].fills,
                effects.operations[0].consumes,
                effects.operations[0].terminal
            ),
            (chunks, chunks, b'L')
        );
        tail_records(
            &records[1..],
            &effects.operations[1..],
            mode,
            chunks,
            chunks,
        );
        assert_eq!(effects.allocations, if mode == 3 { 3 } else { 13 });
        eprintln!(
            "owned-delimited scale-mode={mode} bytes={LENGTH} fill-consume-calls={} maps={} exact-releases={} pure-phases={}",
            chunks * 2,
            effects.allocations,
            effects.releases,
            effects.phases
        );
    }
}
#[test]
fn owned_delimited_selected_reservation_failures_retain_prefix_without_consuming_pending_chunk() {
    let executable = executable("records.lani");
    let schedules = [(0, 1), (0, 2), (0, 5), (0, 11), (1, 5), (2, 5), (3, 1)];
    for (mode, ordinal) in schedules {
        let (output, effects) = run(&executable, Some(mode), Some(ordinal));
        let records = records(&output);
        assert_eq!(records.len(), 4);
        assert_eq!(effects.operations.len(), 4);
        let prefix = if ordinal == 1 {
            0
        } else {
            1024usize << (ordinal - 2)
        };
        let consumed_chunks = prefix / 1024;
        let fills = consumed_chunks + 1;
        assert_eq!(records[0].bytes.len(), prefix);
        checked(
            &records[0],
            0,
            mode,
            1,
            consumed_chunks * 2 + 1,
            prefix,
            0,
            prefix,
            fills,
            consumed_chunks,
            prefix,
            0,
        );
        let expected: Vec<_> = capacities(LENGTH, mode == 3)
            .into_iter()
            .take(ordinal)
            .enumerate()
            .map(|(i, n)| (n, i + 1 != ordinal))
            .collect();
        assert_eq!(effects.operations[0].attempts, expected);
        assert!(effects.operations[0].failed);
        assert_eq!(
            (effects.operations[0].fills, effects.operations[0].consumes),
            (fills, consumed_chunks)
        );
        let remaining = LENGTH - prefix;
        let recovery_chunks = if mode == 3 {
            1
        } else {
            remaining.div_ceil(1024)
        };
        let total_fills = fills + recovery_chunks;
        let total_consumes = consumed_chunks + recovery_chunks;
        assert_eq!(records[1].bytes.len(), remaining);
        checked(
            &records[1],
            1,
            mode,
            0,
            recovery_chunks * 2,
            remaining,
            1,
            LENGTH,
            total_fills,
            total_consumes,
            remaining,
            prefix,
        );
        assert_eq!(
            effects.operations[1].attempts,
            capacities(remaining, mode == 3)
                .into_iter()
                .map(|n| (n, true))
                .collect::<Vec<_>>()
        );
        assert_eq!(
            (
                effects.operations[1].fills,
                effects.operations[1].consumes,
                effects.operations[1].terminal
            ),
            (recovery_chunks, recovery_chunks, b'L')
        );
        let combined: Vec<_> = records[0]
            .bytes
            .iter()
            .chain(&records[1].bytes)
            .copied()
            .collect();
        assert_eq!(
            combined,
            (0..LENGTH).map(|i| data(mode, i)).collect::<Vec<_>>()
        );
        tail_records(
            &records[2..],
            &effects.operations[2..],
            mode,
            total_fills,
            total_consumes,
        );
        assert_eq!(effects.setup, [LENGTH + 5]);
        assert_eq!(effects.phases, 2);
        assert_eq!(effects.protections, 0);
        eprintln!(
            "owned-delimited fault-mode={mode} reached-reservation={ordinal} retained={prefix} confirmed={prefix} pending-chunk-not-consumed maps={} exact-releases={}",
            effects.allocations, effects.releases
        );
    }
}
#[test]
fn owned_delimited_guarded_fill_extents_stop_at_delimiters_and_leave_capped_data_pending() {
    let executable = executable("guards.lani");
    let (output, effects) = run(&executable, None, None);
    let mut bytes = output.as_slice();
    let expected: [(&[u8], [i32; 8]); 9] = [
        (b"", [0, 0, 1, 0, 2, 0, 1, 0]),
        (b"a", [1, 1, 3, 1, 2, 1, 2, 1]),
        (b"\n", [2, 1, 2, 1, 1, 1, 1, 1]),
        (b"abc\n", [3, 4, 2, 4, 1, 4, 1, 1]),
        (b"abcd", [4, 4, 3, 4, 2, 4, 2, 1]),
        (b"\n", [5, 1, 2, 1, 1, 1, 1, 1]),
        (b"abc", [6, 3, 3, 3, 0, 3, 2, 1]),
        (b"\n", [7, 1, 2, 1, 1, 4, 3, 2]),
        (b"Z", [8, 1, 3, 1, 2, 5, 5, 3]),
    ];
    for (payload, header) in expected {
        assert!(bytes.len() >= 32 + payload.len());
        let actual: [i32; 8] = std::array::from_fn(|i| {
            i32::from_le_bytes(bytes[i * 4..i * 4 + 4].try_into().unwrap())
        });
        assert_eq!(actual, header);
        assert_eq!(&bytes[32..32 + payload.len()], payload);
        bytes = &bytes[32 + payload.len()..];
    }
    assert!(bytes.is_empty());
    assert_eq!(effects.setup, [8192]);
    assert_eq!(
        (
            effects.allocations,
            effects.releases,
            effects.protections,
            effects.phases
        ),
        (9, 9, 1, 1)
    );
    assert_eq!(
        effects
            .operations
            .iter()
            .map(|operation| operation.attempts.clone())
            .collect::<Vec<_>>(),
        [
            vec![],
            vec![(1, true)],
            vec![(1, true)],
            vec![(4, true)],
            vec![(4, true)],
            vec![(1, true)],
            vec![(3, true)],
            vec![(1, true)],
            vec![(1, true)]
        ]
    );
    eprintln!(
        "owned-delimited guards=9 metadata-pure-phases=1 protected-inputs=1 mappings=9 exact-releases=9"
    );
}
