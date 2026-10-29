//! Live owner, pending suffix and allocation-boundary evidence for stream encoding.
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
        .join("tests/fixtures/stdlib_stream_encoding/resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("stream encoding resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("stream encoding resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_stream_encoding_resources", name, None);
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
    live_at_return: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Cycle {
    setup: Vec<Action>,
    backing: Vec<(usize, usize)>,
    operations: Vec<Operation>,
    phases: usize,
    cleanup_phases: Vec<Vec<(usize, usize)>>,
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
                    assert_eq!(
                        owners(&live),
                        cycle.as_ref().unwrap().backing,
                        "each encode starts with only original owners"
                    );
                    operation = Some(Operation::default());
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
                "only setup and owned encode may allocate: {events}"
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
                    "only a reached owned-output denial is admitted: {events}"
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
                        .contains(&(allocation, size)),
                    "encode cannot destroy an original source owner: {events}"
                );
                operation.actions.push(action);
            } else if !sealed {
                cycle.as_mut().unwrap().setup.push(action);
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
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_stream_encoding_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_stream_encoding_resources", "trace", None);
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
        "stream encoding finite owner lifecycle",
        &mut command,
        Duration::from_secs(18),
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
    let observed = effects(&events, &output.stderr, mode.is_some());
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed)
}
fn source(count: usize) -> Vec<u8> {
    (0..count + 7)
        .map(|index| {
            if (3..count + 3).contains(&index) {
                let index = index - 3;
                ((index * 29 + index / 251 + 17) % 256) as u8
            } else {
                ((index * 13 + 191) % 256) as u8
            }
        })
        .collect()
}
#[test]
fn resumable_copy_retains_real_owner_storage_and_pending_bytes() {
    let executable = executable("copy.lani");
    let (output, observed) = run(&executable, None, None);
    let mut expected = Vec::new();
    assert_eq!(observed.cycles.len(), 2);
    for (count, cycle) in [4096, 262_144].into_iter().zip(&observed.cycles) {
        let original = source(count);
        expected.extend_from_slice(&original);
        expected.extend_from_slice(&original);
        assert_eq!(
            cycle
                .backing
                .iter()
                .map(|&(_, size)| size)
                .collect::<Vec<_>>(),
            [count + 7, 4105, count + 7]
        );
        assert_eq!(cycle.setup.len(), 3);
        assert!(cycle.operations.is_empty() && cycle.cleanup_phases.is_empty());
        assert_eq!(cycle.phases, 5);
    }
    assert_eq!(
        output, expected,
        "full source/guards and recovered sink bytes, at both sizes"
    );
    assert_eq!((observed.allocations, observed.releases), (6, 6));
    eprintln!(
        "stream-copy owners sizes=4096,262144 scratch=4093 retained=4076 pure-phases=10 exact-maps=6 exact-releases=6"
    );
}
const PATTERN: &[u8] = b"a\"\\\n\0\xc3\xa9\xf0\x9f\x99\x82/\x08\x0c\t\r";
fn json_bytes(count: usize) -> Vec<u8> {
    assert_eq!(PATTERN.len(), 16);
    let mut output = br#"{"payload":""#.to_vec();
    for byte in PATTERN.iter().copied().cycle().take(count) {
        match byte {
            b'"' | b'\\' => output.extend([b'\\', byte]),
            0..=31 => output.extend(format!("\\u{byte:04x}").bytes()),
            _ => output.push(byte),
        }
    }
    output.extend(br#"","rows":[null,true,false,1.2300e+05,{},[]]}"#);
    assert_eq!(output.len(), 56 + count * 3);
    output
}
fn json_backing(cycle: &Cycle, count: usize) {
    let sizes = cycle
        .backing
        .iter()
        .map(|&(_, size)| size)
        .collect::<Vec<_>>();
    // Original text and the document's independent copy must coexist; the
    // same applies to the original/copy of the preserved number spelling.
    assert_eq!(sizes.iter().filter(|&&size| size == count).count(), 2);
    assert_eq!(sizes.iter().filter(|&&size| size == 10).count(), 2);
    assert!(sizes.contains(&7) && sizes.contains(&4) && sizes.contains(&4105));
    // json::Node has fourteen native words: Kind + bool + two three-word
    // Strings + six i32 link/count/depth fields. core::mem's record layout
    // uses eight bytes per scalar word; nine nodes grow Vec capacity to 16.
    assert!(sizes.contains(&(16 * 14 * 8)));
    assert_eq!(
        sizes.len(),
        8,
        "two sources, two copied values, two keys, nodes, scratch"
    );
}
#[test]
fn json_encoder_borrows_live_document_without_output_allocation() {
    let executable = executable("json.lani");
    let (output, observed) = run(&executable, Some(0), None);
    assert_eq!(observed.cycles.len(), 2);
    let mut expected = Vec::new();
    for (count, cycle) in [4096, 262_144].into_iter().zip(&observed.cycles) {
        let bytes = json_bytes(count);
        json_backing(cycle, count);
        assert!(cycle.operations.is_empty() && cycle.cleanup_phases.is_empty());
        assert_eq!(cycle.phases, 2 + bytes.len().div_ceil(4093));
        expected.extend(bytes);
    }
    assert_eq!(
        output, expected,
        "every escaped UTF-8 byte in original member and number order"
    );
    eprintln!(
        "json-borrowed owners text-bytes=4096,262144 scratch=4093 exact-output={} no-output-allocation=true exact-maps={} exact-releases={}",
        output.len(),
        observed.allocations,
        observed.releases
    );
}
fn successful_output(cycle: &Cycle, operation: &Operation) -> (usize, usize) {
    assert!(!operation.attempts.is_empty());
    assert!(operation.attempts.iter().all(|&(_, _, success)| success));
    let (ordinal, size, _) = *operation.attempts.last().unwrap();
    let mut expected = cycle.backing.clone();
    expected.push((ordinal, size));
    expected.sort_unstable();
    assert_eq!(
        operation.live_at_return, expected,
        "one independent output allocation survives encode"
    );
    assert_eq!(
        operation
            .actions
            .iter()
            .filter(|action| matches!(action, Action::Release { .. }))
            .count(),
        operation.attempts.len() - 1,
        "each superseded output allocation retires"
    );
    (ordinal, size)
}
fn denial_prefix(baseline: &Operation, failed: &Operation, site: usize) {
    let (ordinal, size, success) = baseline.attempts[site];
    assert!(success);
    assert_eq!(failed.attempts.len(), site + 1);
    let boundary = baseline.actions.iter().position(
        |action| matches!(action, Action::Allocate { ordinal: current, .. } if *current == ordinal)
    ).unwrap();
    assert_eq!(
        &failed.actions[..boundary],
        &baseline.actions[..boundary],
        "complete normalized effect prefix before reached denial"
    );
    assert_eq!(
        failed.actions[boundary],
        Action::Allocate {
            ordinal,
            size,
            success: false
        },
        "selected successful baseline site is the actual denied allocation"
    );
    let cleanup: Vec<_> = if site == 0 {
        vec![]
    } else {
        let (ordinal, size, _) = baseline.attempts[site - 1];
        vec![Action::Release { ordinal, size }]
    };
    assert_eq!(
        &failed.actions[boundary + 1..],
        cleanup,
        "all retained temporary output retires before Err"
    );
}
#[test]
fn json_owned_encode_reached_allocation_failures_release_only_temporary_output() {
    let executable = executable("json.lani");
    let expected = json_bytes(262_144);
    let (output, baseline) = run(&executable, Some(1), None);
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 1);
    let original = &baseline.cycles[0];
    json_backing(original, 262_144);
    assert_eq!(original.operations.len(), 1);
    assert_eq!(original.phases, 3);
    let baseline_output = successful_output(original, &original.operations[0]);
    assert_eq!(baseline_output.1, expected.len());
    assert_eq!(
        original.cleanup_phases,
        [vec![baseline_output]],
        "output remains live after every document/source owner retires"
    );
    let operation = &original.operations[0];
    assert!(
        operation.attempts.len() >= 2,
        "fixture must reach initial reservation and growth"
    );

    // Initial and final growth are distinct reached output boundaries. This
    // narrowly covers new adapter cleanup without replaying parser campaigns.
    for site in [0, operation.attempts.len() - 1] {
        let ordinal = operation.attempts[site].0;
        let (output, failed) = run(&executable, Some(2), Some(ordinal));
        assert_eq!(
            output, expected,
            "same-process recovery after mmap {ordinal}"
        );
        assert_eq!(failed.cycles.len(), 1);
        let cycle = &failed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 4);
        denial_prefix(operation, &cycle.operations[0], site);
        assert_eq!(
            cycle.operations[0].live_at_return, cycle.backing,
            "Err retains exactly the source owners"
        );
        let recovered = successful_output(cycle, &cycle.operations[1]);
        assert_eq!(recovered.1, expected.len());
        assert_eq!(cycle.cleanup_phases, [vec![recovered]]);
        assert_eq!(
            cycle.operations[1]
                .attempts
                .iter()
                .map(|&(_, size, success)| (size, success))
                .collect::<Vec<_>>(),
            operation
                .attempts
                .iter()
                .map(|&(_, size, success)| (size, success))
                .collect::<Vec<_>>(),
            "retry starts a complete fresh collection with no retained failed output"
        );
        eprintln!(
            "json-owned reached-denial mmap={ordinal} site={site} preserved-source-owners={} recovered-bytes={} exact-maps={} exact-releases={}",
            cycle.backing.len(),
            output.len(),
            failed.allocations,
            failed.releases
        );
    }
}
