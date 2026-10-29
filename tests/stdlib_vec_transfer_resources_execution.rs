//! Manual nested ownership, atomic transfer failures and complete typed scale states.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_vec_transfer_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![
            root.join("extended"),
            root.join("tests/fixtures/stdlib_vec_transfer_resources"),
        ],
    };
    let bytes = common::run_gpu_codegen_with_timeout("vector transfer resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("vector transfer resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_vec_transfer_resources", name, None);
    file.write_bytes(bytes); // The shared writer validates every x86 jump.
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
    live_at_entry: Vec<(usize, usize)>,
    live_at_return: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Cycle {
    setup: Vec<Action>,
    backing: Vec<(usize, usize)>,
    operations: Vec<Operation>,
    phases: usize,
    cleanup_phases: Vec<Vec<(usize, usize)>>,
    cleanup_order: Vec<usize>,
    publications: Vec<Vec<(usize, usize)>>,
}
#[derive(Debug, Default)]
struct Effects {
    cycles: Vec<Cycle>,
    allocations: usize,
    releases: usize,
    output: usize,
}
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Vec<(usize, usize)> {
    let mut owners = live.values().copied().collect::<Vec<_>>();
    owners.sort_unstable();
    owners
}
fn effects(events: &str, stderr: &[u8], configured: bool) -> Effects {
    let mut effects = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut cycle: Option<Cycle> = None;
    let mut operation: Option<Operation> = None;
    let mut pure: Option<Vec<(usize, usize)>> = None;
    let (mut sealed, mut cleanup, mut done) = (false, false, false);
    let (mut entries, mut exits, mut reads, mut ordinal) = (0, 0, 0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASPpCFRED"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(
                        cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
                        "{events}"
                    );
                    cycle = Some(Cycle::default());
                    sealed = false;
                    cleanup = false;
                }
                b'S' => {
                    assert!(
                        !sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    let current = cycle.as_mut().unwrap();
                    assert!(
                        !live.is_empty(),
                        "the witness has real live owners: {events}"
                    );
                    current.backing = owners(&live);
                    sealed = true;
                }
                b'P' => {
                    assert!(
                        sealed && cycle.is_some() && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    pure = Some(owners(&live));
                }
                b'p' => {
                    let before = pure.take().unwrap();
                    assert_eq!(
                        before,
                        owners(&live),
                        "all owner identities/extents survive the pure phase"
                    );
                    let current = cycle.as_mut().unwrap();
                    current.phases += 1;
                    if cleanup {
                        current.cleanup_phases.push(before);
                    }
                }
                b'C' => {
                    assert!(
                        sealed
                            && !cleanup
                            && cycle.is_some()
                            && operation.is_none()
                            && pure.is_none(),
                        "{events}"
                    );
                    operation = Some(Operation {
                        live_at_entry: owners(&live),
                        ..Operation::default()
                    });
                }
                b'F' => {
                    assert!(sealed && !cleanup && pure.is_none(), "{events}");
                    let mut completed = operation.take().unwrap();
                    completed.live_at_return = owners(&live);
                    cycle.as_mut().unwrap().operations.push(completed);
                }
                b'R' => {
                    assert!(
                        sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    cleanup = true;
                }
                b'E' => {
                    assert!(
                        sealed
                            && cleanup
                            && operation.is_none()
                            && pure.is_none()
                            && live.is_empty(),
                        "caller retires every actual owner before E: {events}"
                    );
                    effects.cycles.push(cycle.take().unwrap());
                    sealed = false;
                    cleanup = false;
                }
                b'D' => {
                    assert!(
                        cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
                        "{events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            pure.is_none(),
            "borrowed operation performed a host effect: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows complete retirement: {events}");
        if line.starts_with("execve(") {
            assert!(cycle.is_none() && entries == 0, "{events}");
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                configured && reads == 0 && ordinal == 0 && cycle.is_none(),
                "{events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            assert!(
                cycle.is_some() && !cleanup && (!sealed || operation.is_some()),
                "only setup and marked owned operations may allocate: {events}"
            );
            let fields = arguments(line)
                .split(',')
                .map(str::trim)
                .collect::<Vec<_>>();
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
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0, "{events}");
            ordinal += 1;
            let returned = result(line);
            let pointer = returned.split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            if success {
                assert!(!returned.contains("INJECTED"), "{events}");
                let pointer = address(pointer);
                let end = pointer.checked_add(size as u64).unwrap();
                assert!(
                    live.iter()
                        .all(|(&start, &(_, length))| end <= start
                            || pointer >= start + length as u64),
                    "distinct live extents cannot overlap: {events}"
                );
                assert!(live.insert(pointer, (ordinal, size)).is_none(), "{events}");
                effects.allocations += 1;
            } else {
                assert!(
                    operation.is_some()
                        && pointer == "-1"
                        && returned.contains("ENOMEM")
                        && returned.contains("INJECTED"),
                    "only a reached owned-operation denial is admitted: {events}"
                );
            }
            let action = Action::Allocate {
                ordinal,
                size,
                success,
            };
            if let Some(operation) = operation.as_mut() {
                operation.attempts.push((ordinal, size, success));
                operation.actions.push(action);
            } else {
                assert!(success, "{events}");
                cycle.as_mut().unwrap().setup.push(action);
            }
        } else if line.starts_with("munmap(") {
            assert!(
                cycle.is_some() && (!sealed || operation.is_some() || cleanup),
                "borrowed state never releases backing: {events}"
            );
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let size: usize = length.trim().parse().unwrap();
            let (allocation, actual) = live.remove(&address(pointer)).unwrap_or_else(|| {
                panic!("release of unknown/already retired address: {line}\n{events}")
            });
            assert_eq!(size, actual, "exact live release extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            effects.releases += 1;
            let action = Action::Release {
                ordinal: allocation,
                size,
            };
            if let Some(operation) = operation.as_mut() {
                assert!(
                    !cycle
                        .as_ref()
                        .unwrap()
                        .backing
                        .contains(&(allocation, size))
                        || (size != 8 && size != 12),
                    "transfers cannot destroy any nested data/String owner: {events}"
                );
                operation.actions.push(action);
            } else if !sealed {
                cycle.as_mut().unwrap().setup.push(action);
            } else {
                assert!(cleanup, "{events}");
                cycle.as_mut().unwrap().cleanup_order.push(allocation);
            }
        } else if line.starts_with("write(1,") {
            assert!(
                sealed && cleanup && operation.is_none() && cycle.is_some(),
                "publication follows explicit container retirement: {events}"
            );
            cycle.as_mut().unwrap().publications.push(owners(&live));
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = result(line).parse().unwrap();
            assert!(used > 0 && used <= requested, "{events}");
            effects.output += used;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        done && cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!(
        (entries, exits, reads),
        (1, 1, usize::from(configured)),
        "{events}"
    );
    assert_eq!(
        effects.allocations, effects.releases,
        "cleanup observed before exit: {events}"
    );
    assert_eq!(stderr, markers, "native marker and syscall evidence agree");
    effects
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
) -> (Vec<u8>, Effects, Duration) {
    let input = common::TempArtifact::new("laniusc_vec_transfer_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_vec_transfer_resources", "trace", None);
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
    let native_start = Instant::now();
    let output = common::process_output_with_timeout(
        "vector transfer finite owner lifecycle",
        &mut command,
        Duration::from_secs(15),
    );
    let elapsed = native_start.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode:?} denial={failure:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some()),
        "every configured fault must be reached: {events}"
    );
    let observed = effects(&events, &output.stderr, mode.is_some());
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed, elapsed)
}

const ENTRY: usize = 6 * 8; // Two three-word owners, Vec<u8> and String.
fn header(output: &[u8], position: &mut usize) -> [usize; 4] {
    let mut fields = [0; 4];
    for field in &mut fields {
        let value = i32::from_le_bytes(output[*position..*position + 4].try_into().unwrap());
        assert!(value >= 0);
        *field = value as usize;
        *position += 4;
    }
    fields
}
fn entry_bytes(id: usize) -> Vec<u8> {
    (0..8)
        .map(|i| ((id * 29 + i * 17 + 3) % 256) as u8)
        .chain((0..12).map(|i| (65 + (id * 7 + i * 3) % 26) as u8))
        .collect()
}
fn entry_output(output: &[u8], position: &mut usize, ids: impl IntoIterator<Item = usize>) {
    let expected: Vec<_> = ids.into_iter().flat_map(entry_bytes).collect();
    assert_eq!(&output[*position..*position + expected.len()], expected);
    *position += expected.len();
}
fn inner_owners(cycle: &Cycle) -> Vec<(usize, usize)> {
    let nested: Vec<_> = cycle
        .backing
        .iter()
        .copied()
        .filter(|&(_, size)| size == 8 || size == 12)
        .collect();
    assert_eq!(nested.len(), 34);
    assert!(
        nested
            .chunks_exact(2)
            .all(|pair| pair[0].1 == 8 && pair[1].1 == 12)
    );
    nested
}
fn union(left: &[(usize, usize)], right: &[(usize, usize)]) -> Vec<(usize, usize)> {
    let mut result = left.to_vec();
    result.extend_from_slice(right);
    result.sort_unstable();
    result
}
fn only_allocate(operation: &Operation, size: usize) -> (usize, usize) {
    assert_eq!(operation.attempts.len(), 1);
    let (ordinal, actual, success) = operation.attempts[0];
    assert!(success);
    assert_eq!(actual, size);
    assert_eq!(
        operation.actions,
        [Action::Allocate {
            ordinal,
            size,
            success: true
        }]
    );
    (ordinal, size)
}
fn publication(cycle: &Cycle, expected: &[(usize, usize)]) {
    assert_eq!(cycle.cleanup_phases, [expected]);
    assert!(!cycle.publications.is_empty());
    for live in &cycle.publications {
        assert_eq!(
            live, expected,
            "every actual stdout write has exactly the intended surviving cleanup owners"
        );
    }
}
fn setup(cycle: &Cycle, expected: &[usize]) {
    assert_eq!(
        cycle
            .backing
            .iter()
            .map(|&(_, size)| size)
            .collect::<Vec<_>>(),
        expected
    );
    assert_eq!(cycle.setup.len(), expected.len());
    assert!(
        cycle
            .setup
            .iter()
            .all(|event| matches!(event, Action::Allocate { success: true, .. }))
    );
}
fn nested_setup(capacity: usize, count: usize) -> Vec<usize> {
    let mut values = vec![capacity * ENTRY];
    for _ in 0..count {
        values.extend([8, 12]);
    }
    values
}

#[test]
fn vector_transfers_conserve_nested_owners_and_reuse_empty_donors_without_hidden_cleanup() {
    let started = Instant::now();
    let executable = executable("nested.lani");
    let compile = started.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    let mut position = 0;
    let [capacity, middle_capacity, tail_capacity, count] = header(&output, &mut position);
    assert_eq!((capacity, count), (33, 17));
    assert!(middle_capacity >= 7 && tail_capacity >= 5);
    entry_output(&output, &mut position, 0..17);
    assert_eq!(position, output.len());
    let mut expected = nested_setup(23, 17);
    expected.extend([33 * ENTRY, 5 * ENTRY]);
    setup(cycle, &expected);
    assert_eq!(cycle.operations.len(), 2);
    assert_eq!(cycle.phases, 4);
    let middle = only_allocate(&cycle.operations[0], middle_capacity * ENTRY);
    let tail = only_allocate(&cycle.operations[1], tail_capacity * ENTRY);
    assert_eq!(cycle.operations[0].live_at_entry, cycle.backing);
    assert_eq!(
        cycle.operations[0].live_at_return,
        union(&cycle.backing, &[middle])
    );
    assert_eq!(
        cycle.operations[1].live_at_entry,
        cycle.operations[0].live_at_return
    );
    assert_eq!(
        cycle.operations[1].live_at_return,
        union(&cycle.backing, &[middle, tail])
    );
    let nested = inner_owners(cycle);
    let final_outer = cycle.backing[35];
    let live = union(&nested, &[final_outer]);
    publication(cycle, &live);
    let mut cleanup = vec![cycle.backing[0].0, middle.0, tail.0, cycle.backing[36].0];
    cleanup.extend(nested.iter().map(|&(ordinal, _)| ordinal));
    cleanup.push(final_outer.0);
    assert_eq!(cycle.cleanup_order, cleanup);
    assert_eq!((observed.allocations, observed.releases), (39, 39));
    eprintln!(
        "vec-transfer nested entries=17 inner-owners=34 full-payload-bytes=340 exact-maps=39 exact-releases=39 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

fn validate_fault_cycle(
    cycle: &Cycle,
    kind: usize,
    capacity: usize,
    donor_capacity: usize,
    result_capacity: usize,
    failing: bool,
) {
    let mut expected = nested_setup(
        if kind == 0 { 3 } else { 23 },
        if kind == 0 { 3 } else { 17 },
    );
    if kind == 0 {
        expected.extend(nested_setup(21, 14));
    }
    setup(cycle, &expected);
    assert_eq!(cycle.phases, if failing { 4 } else { 3 });
    assert_eq!(cycle.operations.len(), if failing { 2 } else { 1 });
    let nested = inner_owners(cycle);
    let operation = cycle.operations.last().unwrap();
    assert_eq!(operation.live_at_entry, cycle.backing);
    assert_eq!(operation.attempts.len(), 1);
    let (ordinal, size, success) = operation.attempts[0];
    assert!(success);
    let result = (ordinal, size);
    let source = cycle.backing[0];
    let mut cleanup = Vec::new();
    let live = if kind == 0 {
        assert!(capacity >= 17);
        assert_eq!((donor_capacity, result_capacity), (21, 0));
        assert_eq!(size, capacity * ENTRY);
        assert_eq!(
            operation.actions,
            [
                Action::Allocate {
                    ordinal,
                    size,
                    success: true
                },
                Action::Release {
                    ordinal: source.0,
                    size: source.1
                }
            ]
        );
        let donor = cycle.backing[7];
        assert_eq!(operation.live_at_return, union(&nested, &[donor, result]));
        cleanup.push(donor.0);
        cleanup.extend(nested.iter().map(|&(id, _)| id));
        cleanup.push(result.0);
        union(&nested, &[result])
    } else {
        assert_eq!((capacity, donor_capacity), (23, 0));
        assert!(result_capacity >= if kind == 1 { 10 } else { 9 });
        only_allocate(operation, result_capacity * ENTRY);
        assert_eq!(operation.live_at_return, union(&cycle.backing, &[result]));
        let first_ids: Vec<_> = if kind == 1 {
            (0..7).collect()
        } else {
            (0..4).chain(13..17).collect()
        };
        let last_ids: Vec<_> = if kind == 1 {
            (7..17).collect()
        } else {
            (4..13).collect()
        };
        for id in first_ids {
            cleanup.extend([nested[id * 2].0, nested[id * 2 + 1].0]);
        }
        cleanup.push(source.0);
        for id in last_ids {
            cleanup.extend([nested[id * 2].0, nested[id * 2 + 1].0]);
        }
        cleanup.push(result.0);
        union(&cycle.backing, &[result])
    };
    publication(cycle, &live);
    assert_eq!(cycle.cleanup_order, cleanup);
    if failing {
        let failed = &cycle.operations[0];
        assert_eq!(failed.live_at_entry, cycle.backing);
        assert_eq!(failed.live_at_return, cycle.backing);
        assert_eq!(failed.attempts.len(), 1);
        let (denied, extent, succeeded) = failed.attempts[0];
        assert!(!succeeded);
        assert_eq!(extent, size);
        assert_eq!(
            failed.actions,
            [Action::Allocate {
                ordinal: denied,
                size: extent,
                success: false
            }],
            "failure has no owner mutation or cleanup"
        );
    }
}
fn fault_output(output: &[u8], observed: &Effects, failing: Option<usize>) {
    assert_eq!(observed.cycles.len(), 3);
    let mut position = 0;
    for (kind, cycle) in observed.cycles.iter().enumerate() {
        let [tag, capacity, donor_capacity, result_capacity] = header(output, &mut position);
        assert_eq!(tag, kind);
        let order: Vec<_> = if kind == 2 {
            (0..4).chain(13..17).chain(4..13).collect()
        } else {
            (0..17).collect()
        };
        entry_output(output, &mut position, order);
        validate_fault_cycle(
            cycle,
            kind,
            capacity,
            donor_capacity,
            result_capacity,
            failing == Some(kind),
        );
    }
    assert_eq!(position, output.len());
    assert_eq!((observed.allocations, observed.releases), (109, 109));
}
#[test]
fn vector_transfer_allocation_errors_preserve_existing_views_and_recover_same_owners() {
    let started = Instant::now();
    let executable = executable("faults.lani");
    let compile = started.elapsed();
    let (output, baseline, native) = run(&executable, Some(0), None);
    fault_output(&output, &baseline, None);
    eprintln!(
        "vec-transfer fault-baseline operations=append,split,extract nested-owners-per-case=34 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
    for selected in 0..3 {
        let original = &baseline.cycles[selected];
        let baseline_op = &original.operations[0];
        let (ordinal, size, success) = baseline_op.attempts[0];
        assert!(success);
        let (output, observed, elapsed) =
            run(&executable, Some((selected + 1) as u8), Some(ordinal));
        fault_output(&output, &observed, Some(selected));
        let cycle = &observed.cycles[selected];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        let failed = &cycle.operations[0];
        assert_eq!(failed.attempts, [(ordinal, size, false)]);
        let boundary=baseline_op.actions.iter().position(|action|matches!(action,Action::Allocate { ordinal: current,.. } if *current==ordinal)).unwrap();
        assert_eq!(
            failed.actions[..boundary],
            baseline_op.actions[..boundary],
            "complete normalized prefix before selected reached denial"
        );
        eprintln!(
            "vec-transfer reached-denial={ordinal} operation={selected} old-views-preserved=true same-process-recovery=true exact-maps=109 exact-releases=109 native-seconds={:.6}",
            elapsed.as_secs_f64()
        );
    }
}

#[test]
fn vector_transfer_scale_checks_complete_packed_and_composite_values_after_linear_range_work() {
    let started = Instant::now();
    let executable = executable("scale.lani");
    let compile = started.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert_eq!(observed.cycles.len(), 4);
    let mut position = 0;
    let mut values = 0;
    for ((count, element), cycle) in [(4096, 4), (4096, 16), (262144, 4), (262144, 16)]
        .into_iter()
        .zip(&observed.cycles)
    {
        let [actual, layout, middle_capacity, tail_capacity] = header(&output, &mut position);
        assert_eq!((actual, layout), (count, element));
        assert!(middle_capacity >= count / 2 && tail_capacity >= count / 4);
        setup(cycle, &[(count + 17) * element]);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 4);
        let middle = only_allocate(&cycle.operations[0], middle_capacity * element);
        let tail = only_allocate(&cycle.operations[1], tail_capacity * element);
        assert_eq!(cycle.operations[0].live_at_entry, cycle.backing);
        assert_eq!(
            cycle.operations[0].live_at_return,
            union(&cycle.backing, &[middle])
        );
        assert_eq!(
            cycle.operations[1].live_at_entry,
            cycle.operations[0].live_at_return
        );
        assert_eq!(
            cycle.operations[1].live_at_return,
            union(&cycle.backing, &[middle, tail])
        );
        publication(cycle, &cycle.backing);
        assert_eq!(cycle.cleanup_order, [middle.0, tail.0, cycle.backing[0].0]);
        for id in 0..count {
            assert_eq!(&output[position..position + 4], (id as u32).to_le_bytes());
            position += 4;
            if element == 16 {
                assert_eq!(
                    &output[position..position + 8],
                    ((id as u64) * 1_000_003 + 17).to_le_bytes()
                );
                position += 8;
            }
        }
        values += count;
    }
    assert_eq!(position, output.len());
    assert_eq!((observed.allocations, observed.releases), (12, 12));
    eprintln!(
        "vec-transfer scale sizes=4096,262144 layouts=packed-i32,descending-record complete-values={values} output-bytes={} exact-maps=12 exact-releases=12 native-seconds={:.6} compile-seconds={:.6}",
        output.len(),
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}
