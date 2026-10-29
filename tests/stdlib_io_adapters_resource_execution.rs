//! Borrowed reader composition, retained buffered suffixes and exact owner cleanup.
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

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_io_adapters_resources")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("I/O adapter resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("I/O adapter resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_io_adapters_resources", name, None);
    file.write_bytes(bytes); // Shared assertion checks every x86 jump before execution.
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
#[derive(Clone, Debug, PartialEq, Eq)]
enum Action {
    Allocate {
        ordinal: usize,
        size: usize,
        success: bool,
    },
    Release {
        ordinal: usize,
        size: usize,
    },
}
#[derive(Debug, Default)]
struct Operation {
    actions: Vec<Action>,
    attempts: Vec<(usize, usize, bool)>,
    live_at_return: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Effects {
    setup: Vec<usize>,
    operations: Vec<Operation>,
    allocations: usize,
    releases: usize,
    phases: usize,
}
fn effects(events: &str, stderr: &[u8], configured: bool) -> Effects {
    let mut report = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut active: Option<Operation> = None;
    let (mut pure, mut done) = (false, false);
    let (mut entries, mut exits, mut reads, mut ordinal) = (0, 0, 0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            assert!(!done, "{events}");
            let marker = [b'C', b'F', b'P', b'p', b'D']
                .into_iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(*byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'C' => {
                    assert!(!pure && active.is_none(), "{events}");
                    active = Some(Operation::default());
                }
                b'F' => {
                    assert!(!pure, "{events}");
                    let mut operation = active.take().unwrap();
                    operation.live_at_return = live.values().copied().collect();
                    operation.live_at_return.sort_unstable();
                    report.operations.push(operation);
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
                        "all owners retired before D: {events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(!pure, "observation phase reached host service: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows D: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            assert_eq!(entries, 0);
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                reads == 0
                    && report.setup.is_empty()
                    && active.is_none()
                    && report.operations.is_empty(),
                "one initial configuration read: {events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields.len(), 6, "{events}");
            assert_eq!(fields[0], "NULL", "{events}");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ],
                "{events}"
            );
            let length: usize = fields[1].parse().unwrap();
            assert!(length > 0, "{events}");
            let value = result(line);
            let pointer = value.split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            ordinal += 1;
            if success {
                assert!(!value.contains("INJECTED"), "{events}");
                let pointer = address(pointer);
                let end = pointer.checked_add(length as u64).unwrap();
                assert!(
                    live.iter()
                        .all(|(&start, &(_, size))| end <= start || pointer >= start + size as u64),
                    "live extents cannot overlap: {events}"
                );
                assert!(
                    live.insert(pointer, (ordinal, length)).is_none(),
                    "distinct live owner: {events}"
                );
                report.allocations += 1;
            } else {
                assert!(
                    pointer == "-1" && value.contains("ENOMEM") && value.contains("INJECTED"),
                    "reached injected ENOMEM: {events}"
                );
            }
            if let Some(operation) = active.as_mut() {
                operation.attempts.push((ordinal, length, success));
                operation.actions.push(Action::Allocate {
                    ordinal,
                    size: length,
                    success,
                });
            } else {
                assert!(
                    success && report.phases == 0 && report.operations.is_empty(),
                    "setup reserved before observations: {events}"
                );
                report.setup.push(length);
            }
        } else if line.starts_with("munmap(") {
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            let (allocation, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("release of unknown/retired address: {line}\n{events}"));
            assert_eq!(actual, length, "exact release extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            report.releases += 1;
            if let Some(operation) = active.as_mut() {
                operation.actions.push(Action::Release {
                    ordinal: allocation,
                    size: length,
                });
            }
        } else if line.starts_with("write(1,") {
            assert!(active.is_none(), "output outside operation: {events}");
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
        (1, 1, usize::from(configured)),
        "{events}"
    );
    assert_eq!(report.allocations, report.releases, "{events}");
    assert_eq!(stderr, markers, "trace/native marker agreement: {events}");
    report
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
    seconds: u64,
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_io_adapters_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_io_adapters_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = failure {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let output = common::process_output_with_timeout(
        "I/O adapters finite native lifecycle",
        &mut command,
        Duration::from_secs(seconds),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode:?} failure={failure:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some()),
        "one reached fault: {events}"
    );
    let effects = effects(&events, &output.stderr, mode.is_some());
    (output.stdout, effects)
}

fn successful(operation: &Operation, sizes: &[usize]) {
    assert_eq!(
        operation
            .attempts
            .iter()
            .map(|&(_, size, success)| (size, success))
            .collect::<Vec<_>>(),
        sizes.iter().map(|&size| (size, true)).collect::<Vec<_>>()
    );
}
fn live(operation: &Operation, owners: &[(usize, usize)]) {
    let mut expected = owners.to_vec();
    expected.sort_unstable();
    assert_eq!(operation.live_at_return, expected);
}
fn last_owner(operation: &Operation) -> (usize, usize) {
    let &(ordinal, size, success) = operation.attempts.last().unwrap();
    assert!(success);
    (ordinal, size)
}
fn capacities(maximum: usize) -> Vec<usize> {
    if maximum == 0 {
        return vec![];
    }
    let mut values = vec![maximum.min(1024)];
    while *values.last().unwrap() < maximum {
        values.push((2 * values.last().unwrap()).min(maximum));
    }
    values
}
#[test]
fn io_adapters_preserve_real_buffered_suffixes_and_caller_owned_sources() {
    let executable = executable("composition.lani");
    let (output, effects) = run(&executable, None, None, 10);
    assert_eq!(output, [7, 8, 133, 134, 135]);
    assert_eq!(effects.setup, [32, 24]);
    assert_eq!(effects.operations.len(), 3);
    assert_eq!(effects.phases, 7);
    successful(&effects.operations[0], &[8]);
    successful(&effects.operations[1], &[5]);
    successful(&effects.operations[2], &[1, 2, 5]);
    live(&effects.operations[0], &[(1, 32), (2, 24), (3, 8)]);
    live(&effects.operations[1], &[(1, 32), (2, 24), (3, 8), (4, 5)]);
    live(
        &effects.operations[2],
        &[(1, 32), (2, 24), (3, 8), (4, 5), (7, 5)],
    );
    assert_eq!((effects.allocations, effects.releases), (7, 7));
    eprintln!(
        "io-adapter-composition pure-phases=7 allocations=7 exact-releases=7 delimiter-bytes=5 retained-input-reused=true"
    );
}
const TOTAL: usize = 327_692;
const LIMIT: usize = 300_007;
fn checked_collection(output: &[u8], mode: u8) -> usize {
    assert_eq!(output.len(), 24 + TOTAL);
    let report: [i32; 6] = std::array::from_fn(|index| {
        i32::from_le_bytes(output[index * 4..index * 4 + 4].try_into().unwrap())
    });
    let prefix = usize::try_from(report[1]).unwrap();
    assert!(prefix < LIMIT);
    assert_eq!(
        report,
        [
            i32::from(mode),
            prefix as i32,
            (LIMIT - prefix) as i32,
            27685,
            104703,
            1309
        ]
    );
    if mode != 2 {
        assert_eq!(prefix, 0);
    }
    let expected: Vec<u8> = (0..TOTAL)
        .map(|index| ((index * 29 + index / 251 + 17) % 256) as u8)
        .collect();
    assert_eq!(
        &output[24..],
        expected,
        "every retained, resumed and prefetched suffix byte appears once, in original order"
    );
    prefix
}
fn unchanged_prefix(baseline: &Operation, interrupted: &Operation, site: usize) {
    let (ordinal, size, success) = baseline.attempts[site];
    assert!(success);
    assert_eq!(interrupted.attempts.len(), site + 1);
    let boundary = baseline.actions.iter().position(|action| matches!(action, Action::Allocate { ordinal: current, .. } if *current == ordinal)).unwrap();
    assert_eq!(
        &interrupted.actions[..boundary],
        &baseline.actions[..boundary],
        "complete normalized syscall sequence before reached allocation denial"
    );
    assert_eq!(
        &interrupted.actions[boundary..],
        &[Action::Allocate {
            ordinal,
            size,
            success: false
        }],
        "consumer preserves error-owned prefix without new effects after failed reservation"
    );
}
#[test]
fn io_adapters_large_binary_collection_and_reached_allocations_preserve_exact_prefixes() {
    let executable = executable("collection.lani");
    let (output, baseline) = run(&executable, Some(0), None, 30);
    checked_collection(&output, 0);
    assert_eq!(baseline.setup, [196613, 131079]);
    assert_eq!(baseline.operations.len(), 5);
    assert_eq!(baseline.phases, 9);
    let original = [(1, 196613), (2, 131079)];
    let mut input_owners = original.to_vec();
    for (operation, size) in baseline.operations[..3].iter().zip([4093, 2053, 3079]) {
        successful(operation, &[size]);
        input_owners.push(last_owner(operation));
        live(operation, &input_owners);
    }
    let collection = &baseline.operations[3];
    successful(collection, &capacities(LIMIT));
    let collected_owner = last_owner(collection);
    let mut owned = input_owners.clone();
    owned.push(collected_owner);
    live(collection, &owned);
    owned.retain(|&(ordinal, _)| ordinal != input_owners[4].0);
    successful(&baseline.operations[4], &capacities(TOTAL - LIMIT));
    owned.push(last_owner(&baseline.operations[4]));
    live(&baseline.operations[4], &owned);
    assert_eq!((baseline.allocations, baseline.releases), (21, 21));

    // Bind each selected site to its successful baseline operation. One new
    // nested reader construction plus first, middle and final collection
    // growth exercise composition risk without rerunning all old allocator tests.
    let schedules = [
        (1, 2, 0),
        (2, 3, 0),
        (2, 3, 4),
        (2, 3, collection.attempts.len() - 1),
    ];
    for (mode, operation_index, site) in schedules {
        let selected = &baseline.operations[operation_index];
        let ordinal = selected.attempts[site].0;
        let (output, effects) = run(&executable, Some(mode), Some(ordinal), 30);
        let prefix = checked_collection(&output, mode);
        assert_eq!(effects.setup, baseline.setup);
        assert_eq!(effects.operations.len(), 6);
        assert_eq!(effects.phases, 10);
        for index in 0..operation_index {
            assert_eq!(
                effects.operations[index].actions,
                baseline.operations[index].actions
            );
            assert_eq!(
                effects.operations[index].live_at_return,
                baseline.operations[index].live_at_return
            );
        }
        unchanged_prefix(selected, &effects.operations[operation_index], site);
        let mut expected_owners = if mode == 1 {
            input_owners[..4].to_vec()
        } else {
            input_owners.clone()
        };
        if mode == 2 && site > 0 {
            let &(allocation, size, _) = &selected.attempts[site - 1];
            expected_owners.push((allocation, size));
            assert!(
                prefix > size.saturating_sub(1024) && prefix <= size,
                "growth error preserves complete prefix within prior capacity"
            );
        } else {
            assert_eq!(prefix, 0);
        }
        live(&effects.operations[operation_index], &expected_owners);
        let retry = &effects.operations[operation_index + 1];
        if mode == 1 {
            successful(retry, &[3079]);
            expected_owners.push(last_owner(retry));
            live(retry, &expected_owners);
            let result = &effects.operations[4];
            successful(result, &capacities(LIMIT));
            expected_owners.push(last_owner(result));
            live(result, &expected_owners);
            expected_owners.retain(|&(allocation, _)| allocation != retry.attempts[0].0);
        } else {
            successful(retry, &capacities(LIMIT - prefix));
            expected_owners.push(last_owner(retry));
            live(retry, &expected_owners);
            expected_owners.retain(|&(allocation, _)| allocation != input_owners[4].0);
        }
        let tail = &effects.operations[5];
        successful(tail, &capacities(TOTAL - LIMIT));
        expected_owners.push(last_owner(tail));
        live(tail, &expected_owners);
        eprintln!(
            "io-adapter-failure mode={mode} baseline-operation={operation_index} allocation-site={site} reached-mmap={ordinal} retained-prefix={prefix} complete-bytes={TOTAL} allocations={} exact-releases={}",
            effects.allocations, effects.releases
        );
    }
    eprintln!(
        "io-adapter-large bytes={TOTAL} quota={LIMIT} retained-prefetch=1309 baseline-allocations=21 exact-releases=21 reached-denials=4 same-process-recoveries=4"
    );
}
