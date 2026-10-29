//! Real borrowed form backing, two-buffer ownership and reached storage failures.
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
        .join("tests/fixtures/extended_form_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![
            root.join("extended"),
            root.join("tests/fixtures/extended_form_resources"),
        ],
    };
    let bytes = common::run_gpu_codegen_with_timeout("form resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("form resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_form_resources", name, None);
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
fn effects(events: &str, stderr: &[u8], configured: bool, mutable_backing: &[usize]) -> Effects {
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
                        || mutable_backing.contains(&allocation),
                    "only append may replace the original Form buffers: {events}"
                );
                operation.actions.push(action);
            } else if !sealed {
                cycle.as_mut().unwrap().setup.push(action);
            } else {
                assert!(cleanup, "{events}");
                cycle.as_mut().unwrap().cleanup_order.push(allocation);
            }
        } else if line.starts_with("write(1,") {
            assert!(sealed && operation.is_none() && cycle.is_some(), "{events}");
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
    mutable_backing: &[usize],
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_form_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_form_resources", "trace", None);
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
        "form finite owner lifecycle",
        &mut command,
        Duration::from_secs(15),
    );
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
    let observed = effects(&events, &output.stderr, mode.is_some(), mutable_backing);
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed)
}

fn expected_wire(count: usize) -> Vec<u8> {
    fn component(bytes: &[u8], output: &mut Vec<u8>) {
        for &byte in bytes {
            if byte.is_ascii_alphanumeric() || b"*-._".contains(&byte) {
                output.push(byte);
            } else if byte == b' ' {
                output.push(b'+');
            } else {
                output.extend(format!("%{byte:02X}").bytes());
            }
        }
    }
    let mut output = Vec::new();
    for index in 0..count {
        if index != 0 {
            output.push(b'&');
        }
        component(&[b'k', b'A' + (index % 26) as u8], &mut output);
        output.push(b'=');
        component(
            &[b' ', 0, 255, b'%', b'Q', b'0' + (index % 10) as u8],
            &mut output,
        );
    }
    output
}
fn sizes(backing: &[(usize, usize)]) -> Vec<usize> {
    backing.iter().map(|&(_, size)| size).collect()
}
fn allocations(operation: &Operation) -> Vec<(usize, usize)> {
    assert!(operation.attempts.iter().all(|&(_, _, success)| success));
    operation
        .attempts
        .iter()
        .map(|&(ordinal, size, _)| (ordinal, size))
        .collect()
}
fn joined(left: &[(usize, usize)], right: &[(usize, usize)]) -> Vec<(usize, usize)> {
    let mut result = left.to_vec();
    result.extend_from_slice(right);
    result.sort_unstable();
    result
}
fn source_setup(cycle: &Cycle, expected: &[usize]) {
    assert_eq!(sizes(&cycle.backing), expected);
    assert_eq!(cycle.setup.len(), expected.len());
    assert!(
        cycle
            .setup
            .iter()
            .all(|action| matches!(action, Action::Allocate { success: true, .. }))
    );
}
fn denied_prefix(baseline: &Operation, failed: &Operation, site: usize) -> usize {
    let (ordinal, size, success) = baseline.attempts[site];
    assert!(success);
    assert_eq!(failed.attempts.len(), site + 1);
    let boundary = baseline
        .actions
        .iter()
        .position(|action| {
            matches!(action,
        Action::Allocate { ordinal: current, .. } if *current == ordinal)
        })
        .unwrap();
    assert_eq!(
        &failed.actions[..boundary],
        &baseline.actions[..boundary],
        "complete normalized effect prefix before the reached denial"
    );
    assert_eq!(
        failed.actions[boundary],
        Action::Allocate {
            ordinal,
            size,
            success: false
        }
    );
    boundary + 1
}
fn successful_parse(cycle: &Cycle, operation: &Operation) -> Vec<(usize, usize)> {
    let document = allocations(operation);
    assert_eq!(sizes(&document), [257 * 8, 257 * 3 * 8]);
    assert_eq!(
        operation.actions.len(),
        2,
        "exact parse has only two reservations"
    );
    assert_eq!(operation.live_at_entry, cycle.backing);
    assert_eq!(operation.live_at_return, joined(&cycle.backing, &document));
    let mut retained = vec![cycle.backing[1]];
    retained.extend_from_slice(&document);
    retained.sort_unstable();
    assert_eq!(
        cycle.cleanup_phases,
        vec![retained; 5],
        "the full independent Form is read after its original encoded input retires"
    );
    assert_eq!(
        cycle.cleanup_order,
        [
            cycle.backing[0].0,
            document[0].0,
            document[1].0,
            cycle.backing[1].0
        ]
    );
    document
}

#[test]
fn borrowed_form_views_and_encoder_preserve_real_backing_without_allocation() {
    let executable = executable("borrowed.lani");
    let (output, observed) = run(&executable, None, None, &[]);
    assert_eq!(observed.cycles.len(), 2);
    let mut expected = Vec::new();
    for (count, cycle) in [256, 16_384].into_iter().zip(&observed.cycles) {
        // PairSpan is three scalar native words. core::mem sizes each record
        // word at eight bytes, including i32 fields; u8 backing stays packed.
        source_setup(
            cycle,
            &[count * 14 + 7, count * 8 + 7, (count + 2) * 3 * 8, 4105],
        );
        assert!(cycle.operations.is_empty() && cycle.cleanup_phases.is_empty());
        let bytes = expected_wire(count);
        assert_eq!(cycle.phases, 4 + bytes.len().div_ceil(4093));
        assert_eq!(
            cycle.cleanup_order,
            cycle
                .backing
                .iter()
                .map(|&(ordinal, _)| ordinal)
                .collect::<Vec<_>>()
        );
        expected.extend(bytes);
    }
    assert_eq!(
        output, expected,
        "complete canonical wires from immutable borrowed bytes/spans"
    );
    assert_eq!((observed.allocations, observed.releases), (8, 8));
    eprintln!(
        "form-borrowed pairs=256,16384 scratch=4093 output-bytes={} exact-maps=8 exact-releases=8 no-output-allocation=true",
        output.len()
    );
}

#[test]
fn owned_form_parse_releases_partial_buffers_and_recovers_after_both_reached_failures() {
    let executable = executable("parse.lani");
    let expected = expected_wire(257);
    let (output, baseline) = run(&executable, Some(0), None, &[]);
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 1);
    let original = &baseline.cycles[0];
    source_setup(original, &[257 * 14 + 7, 4105]);
    assert_eq!(original.operations.len(), 1);
    assert_eq!(original.phases, 7);
    let operation = &original.operations[0];
    successful_parse(original, operation);
    assert_eq!((baseline.allocations, baseline.releases), (4, 4));
    for site in [0, 1] {
        let ordinal = operation.attempts[site].0;
        let (output, observed) = run(&executable, Some(1), Some(ordinal), &[]);
        assert_eq!(output, expected);
        assert_eq!(observed.cycles.len(), 1);
        let cycle = &observed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 8);
        let failed = &cycle.operations[0];
        assert_eq!(failed.live_at_entry, cycle.backing);
        let tail = denied_prefix(operation, failed, site);
        let cleanup = if site == 0 {
            vec![]
        } else {
            vec![Action::Release {
                ordinal: operation.attempts[0].0,
                size: 257 * 8,
            }]
        };
        assert_eq!(
            failed.actions[tail..],
            cleanup,
            "partial document is destroyed before Err"
        );
        assert_eq!(failed.live_at_return, cycle.backing);
        successful_parse(cycle, &cycle.operations[1]);
        assert_eq!(
            (observed.allocations, observed.releases),
            (4 + site, 4 + site)
        );
        eprintln!(
            "form-parse reached-denial={ordinal} site={site} partial-cleanup=true recovered-pairs=257 exact-maps={} exact-releases={}",
            observed.allocations, observed.releases
        );
    }
}

fn append_settled(cycle: &Cycle, bytes: (usize, usize), spans: (usize, usize)) {
    assert_eq!((bytes.1, spans.1), (4112, 514 * 3 * 8));
    assert_eq!(
        cycle.operations.last().unwrap().live_at_return,
        joined(&cycle.backing[..3], &[bytes, spans])
    );
    assert!(cycle.cleanup_phases.is_empty());
    assert_eq!(cycle.cleanup_order, [bytes.0, spans.0, 1, 2, 3]);
}
#[test]
fn owned_form_append_keeps_logical_contents_through_sequential_reserve_failures() {
    let executable = executable("append.lani");
    let expected = expected_wire(258);
    let (output, baseline) = run(&executable, Some(0), None, &[4, 5]);
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 1);
    let original = &baseline.cycles[0];
    source_setup(original, &[257 * 14 + 7, 15, 4105, 2056, 257 * 3 * 8]);
    assert_eq!(original.operations.len(), 1);
    assert_eq!(original.phases, 7);
    let operation = &original.operations[0];
    assert_eq!(operation.live_at_entry, original.backing);
    let grown = allocations(operation);
    assert_eq!(sizes(&grown), [4112, 514 * 3 * 8]);
    assert_eq!(
        operation.actions,
        [
            Action::Allocate {
                ordinal: 6,
                size: 4112,
                success: true
            },
            Action::Release {
                ordinal: 4,
                size: 2056
            },
            Action::Allocate {
                ordinal: 7,
                size: 514 * 3 * 8,
                success: true
            },
            Action::Release {
                ordinal: 5,
                size: 257 * 3 * 8
            },
        ]
    );
    append_settled(original, grown[0], grown[1]);
    assert_eq!((baseline.allocations, baseline.releases), (7, 7));
    for site in [0, 1] {
        let ordinal = operation.attempts[site].0;
        let (output, observed) = run(&executable, Some((site + 1) as u8), Some(ordinal), &[4, 5]);
        assert_eq!(output, expected);
        assert_eq!(observed.cycles.len(), 1);
        let cycle = &observed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 8);
        let failed = &cycle.operations[0];
        let tail = denied_prefix(operation, failed, site);
        assert_eq!(
            tail,
            failed.actions.len(),
            "late reserve failure retains the successful byte reservation"
        );
        assert_eq!(failed.live_at_entry, original.backing);
        let retained = if site == 0 {
            original.backing.clone()
        } else {
            joined(&original.backing[..3], &[(5, 257 * 3 * 8), grown[0]])
        };
        assert_eq!(failed.live_at_return, retained);
        let retry = &cycle.operations[1];
        assert_eq!(retry.live_at_entry, retained);
        let recovered = allocations(retry);
        if site == 0 {
            assert_eq!(sizes(&recovered), [4112, 514 * 3 * 8]);
            assert_eq!(
                retry.actions,
                [
                    Action::Allocate {
                        ordinal: 7,
                        size: 4112,
                        success: true
                    },
                    Action::Release {
                        ordinal: 4,
                        size: 2056
                    },
                    Action::Allocate {
                        ordinal: 8,
                        size: 514 * 3 * 8,
                        success: true
                    },
                    Action::Release {
                        ordinal: 5,
                        size: 257 * 3 * 8
                    },
                ]
            );
            append_settled(cycle, recovered[0], recovered[1]);
        } else {
            assert_eq!(sizes(&recovered), [514 * 3 * 8]);
            assert_eq!(
                retry.actions,
                [
                    Action::Allocate {
                        ordinal: 8,
                        size: 514 * 3 * 8,
                        success: true
                    },
                    Action::Release {
                        ordinal: 5,
                        size: 257 * 3 * 8
                    }
                ]
            );
            append_settled(cycle, grown[0], recovered[0]);
        }
        assert_eq!((observed.allocations, observed.releases), (7, 7));
        eprintln!(
            "form-append reached-denial={ordinal} site={site} logical-pairs-preserved=257 recovered-pairs=258 retained-byte-reservation={} exact-maps=7 exact-releases=7",
            site == 1
        );
    }
}

fn successful_output(cycle: &Cycle, operation: &Operation, length: usize) -> (usize, usize) {
    let allocated = allocations(operation);
    assert!(allocated.len() >= 2);
    let output = *allocated.last().unwrap();
    assert_eq!(output.1, length);
    assert_eq!(operation.live_at_entry, cycle.backing);
    assert_eq!(operation.live_at_return, joined(&cycle.backing, &[output]));
    assert_eq!(
        operation
            .actions
            .iter()
            .filter(|action| matches!(action, Action::Release { .. }))
            .count(),
        allocated.len() - 1
    );
    assert_eq!(
        cycle.cleanup_phases,
        [vec![output]],
        "independent ASCII String survives Form/input destruction"
    );
    assert_eq!(cycle.cleanup_order, [2, 3, 1, output.0]);
    output
}
#[test]
fn owned_form_encode_cleans_partial_output_and_recovers_without_changing_document() {
    let executable = executable("encode.lani");
    let expected = expected_wire(16_384);
    let (output, baseline) = run(&executable, Some(0), None, &[]);
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 1);
    let original = &baseline.cycles[0];
    source_setup(original, &[16_384 * 14 + 7, 16_384 * 8, 16_384 * 3 * 8]);
    assert_eq!(original.operations.len(), 1);
    assert_eq!(original.phases, 3);
    let operation = &original.operations[0];
    successful_output(original, operation, expected.len());
    for site in [0, operation.attempts.len() - 1] {
        let ordinal = operation.attempts[site].0;
        let (output, observed) = run(&executable, Some(1), Some(ordinal), &[]);
        assert_eq!(output, expected);
        assert_eq!(observed.cycles.len(), 1);
        let cycle = &observed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 4);
        let failed = &cycle.operations[0];
        let tail = denied_prefix(operation, failed, site);
        let cleanup = if site == 0 {
            vec![]
        } else {
            let (ordinal, size, _) = operation.attempts[site - 1];
            vec![Action::Release { ordinal, size }]
        };
        assert_eq!(
            failed.actions[tail..],
            cleanup,
            "retained output owner is gone before Err"
        );
        assert_eq!(failed.live_at_entry, original.backing);
        assert_eq!(failed.live_at_return, original.backing);
        let retry = &cycle.operations[1];
        successful_output(cycle, retry, expected.len());
        assert_eq!(
            sizes(&allocations(retry)),
            sizes(&allocations(operation)),
            "same-process retry performs a fresh complete collection"
        );
        eprintln!(
            "form-encode reached-denial={ordinal} site={site} source-owners=3 recovered-bytes={} exact-maps={} exact-releases={}",
            output.len(),
            observed.allocations,
            observed.releases
        );
    }
}
