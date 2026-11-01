//! Borrowed TOML byte readers, atomic caller buffers and owned-output lifetimes.
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
    let entry = root.join("tests/fixtures/extended_library").join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![
            root.join("extended"),
            root.join("tests/fixtures/extended_library"),
        ],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TOML streaming", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("TOML streaming {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_toml_streaming", name, None);
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
            cycle.as_mut().unwrap().publications.push(owners(&live));
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
    let input = common::TempArtifact::new("laniusc_toml_streaming", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_toml_streaming", "trace", None);
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
        "TOML streaming finite owner lifecycle",
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
#[test]
fn toml_borrowed_encoding_and_atomic_buffer_native_admission() {
    let started = std::time::Instant::now();
    let executable = executable("toml_streaming_admission.lani");
    let compile = started.elapsed();
    let started = std::time::Instant::now();
    let (output, observed) = run(&executable, None, None);
    let expected = b"\"a\"=\"\\u0000\xc3\xa9\"\n\"b\"=[1,{\"x\"=true}]\n";
    assert_eq!(output, expected);
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    assert_eq!(cycle.phases, 2);
    assert_eq!(cycle.operations.len(), 1);
    let operation = &cycle.operations[0];
    assert_eq!(operation.attempts.len(), 1);
    let (ordinal, extent, success) = operation.attempts[0];
    assert!(success);
    assert_eq!(extent, expected.len());
    let mut retained = cycle.backing.clone();
    retained.push((ordinal, extent));
    retained.sort_unstable();
    assert_eq!(operation.live_at_return, retained);
    assert_eq!(cycle.cleanup_phases, [vec![(ordinal, extent)]]);
    assert!(!cycle.publications.is_empty());
    assert!(
        cycle
            .publications
            .iter()
            .all(|owners| owners == &vec![(ordinal, extent)])
    );
    eprintln!(
        "toml-streaming admission wire={} exact-maps={} exact-releases={} native={:.6}s compile={:.6}s",
        output.len(),
        observed.allocations,
        observed.releases,
        started.elapsed().as_secs_f64(),
        compile.as_secs_f64()
    );
}

#[test]
fn toml_streaming_ranges_work_caps_copied_states_and_atomic_guards_execute() {
    let started = std::time::Instant::now();
    let executable = executable("toml_streaming_contracts.lani");
    let compile = started.elapsed();
    let started = std::time::Instant::now();
    let (output, observed) = run(&executable, None, None);
    assert!(output.is_empty());
    assert_eq!(observed.cycles.len(), 9);
    assert_eq!(observed.cycles.iter().map(|c| c.phases).sum::<usize>(), 10);
    assert!(
        observed
            .cycles
            .iter()
            .all(|c| c.operations.is_empty() && c.publications.is_empty())
    );
    assert_eq!(observed.cycles[0].cleanup_phases, [vec![]]);
    eprintln!(
        "toml-streaming contracts cycles=9 pure-phases=10 exact-maps={} exact-releases={} native={:.6}s compile={:.6}s",
        observed.allocations,
        observed.releases,
        started.elapsed().as_secs_f64(),
        compile.as_secs_f64()
    );
}
const PATTERN: &[u8] = b"a\"\\\t\xc3\xa9\xf0\x9f\x99\x82/bcdef";
fn canonical(count: usize) -> Vec<u8> {
    assert_eq!(PATTERN.len(), 16);
    let mut result = br#""payload"="#.to_vec();
    result.push(b'"');
    for byte in PATTERN.iter().copied().cycle().take(count) {
        match byte {
            b'"' | b'\\' => result.extend([b'\\', byte]),
            0..=31 | 127 => result.extend(format!("\\u{byte:04x}").bytes()),
            _ => result.push(byte),
        }
    }
    result.extend(b"\"\n\"rows\"=[true,1,{\"x\"=\"v\"},07:32:00.12]\n");
    assert_eq!(result.len(), count / 16 * 23 + 51);
    result
}
fn backing(cycle: &Cycle, count: usize, borrowed: bool) {
    let mut actual = cycle
        .backing
        .iter()
        .map(|&(_, size)| size)
        .collect::<Vec<_>>();
    // TOML Node: Kind + two three-word Strings + integer/float/bool +
    // eight link/count/depth/state/context words = 18 native words, 144 bytes.
    // The eight real nodes occupy Vec capacity eight. Bare keys and temporal
    // source tokens are exact substring owners; quoted 'v' and formatted 1
    // start with String's four-byte reservation. Scalar-built payloads reach
    // these two power-of-two capacities. These are source-derived extents,
    // not page-rounded RSS and not a public growth schedule promise.
    let mut expected = vec![count, 7, 4, 1, 4, 4, 15, 8 * 18 * 8];
    if borrowed {
        expected.extend([4105, canonical(count).len() + 13]);
    }
    actual.sort_unstable();
    expected.sort_unstable();
    assert_eq!(actual, expected);
}
#[test]
fn toml_borrowed_readers_and_caller_encoding_preserve_live_document_without_allocation() {
    let started = std::time::Instant::now();
    let executable = executable("toml_streaming_resources.lani");
    let compile = started.elapsed();
    let started = std::time::Instant::now();
    let (output, observed) = run(&executable, Some(0), None);
    assert_eq!(observed.cycles.len(), 2);
    let mut expected = Vec::new();
    for (count, cycle) in [4096, 262144].into_iter().zip(&observed.cycles) {
        let wire = canonical(count);
        backing(cycle, count, true);
        assert!(cycle.operations.is_empty() && cycle.cleanup_phases.is_empty());
        assert_eq!(cycle.phases, 2 + wire.len().div_ceil(4093));
        assert!(!cycle.publications.is_empty());
        assert!(
            cycle
                .publications
                .iter()
                .all(|owners| owners == &cycle.backing),
            "all stream/caller-buffer publication retains the exact original document and caller owners"
        );
        expected.extend_from_slice(&wire);
        expected.extend_from_slice(&wire);
    }
    assert_eq!(
        output, expected,
        "every streamed and direct encoded byte at both sizes"
    );
    eprintln!(
        "toml-streaming borrowed sizes=4096,262144 output={} no-output-allocation=true exact-maps={} exact-releases={} native={:.6}s compile={:.6}s",
        output.len(),
        observed.allocations,
        observed.releases,
        started.elapsed().as_secs_f64(),
        compile.as_secs_f64()
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
fn toml_owned_encoding_reached_collector_failures_preserve_document_and_recover() {
    let started = std::time::Instant::now();
    let executable = executable("toml_streaming_resources.lani");
    let compile = started.elapsed();
    let started = std::time::Instant::now();
    let expected = canonical(262144);
    let (output, baseline) = run(&executable, Some(1), None);
    let baseline_time = started.elapsed();
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 1);
    let original = &baseline.cycles[0];
    backing(original, 262144, false);
    assert_eq!(original.operations.len(), 1);
    assert_eq!(original.phases, 3);
    let result = successful_output(original, &original.operations[0]);
    assert_eq!(result.1, expected.len());
    assert_eq!(original.cleanup_phases, [vec![result]]);
    assert!(!original.publications.is_empty());
    assert!(
        original
            .publications
            .iter()
            .all(|owners| owners == &vec![result])
    );
    let operation = &original.operations[0];
    assert!(operation.attempts.len() >= 2);
    for site in [0, operation.attempts.len() - 1] {
        let ordinal = operation.attempts[site].0;
        let started = std::time::Instant::now();
        let (output, observed) = run(&executable, Some(2), Some(ordinal));
        assert_eq!(output, expected);
        assert_eq!(observed.cycles.len(), 1);
        let cycle = &observed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 4);
        denial_prefix(operation, &cycle.operations[0], site);
        assert_eq!(
            cycle.operations[0].live_at_return, cycle.backing,
            "failed collector owns no leftover output"
        );
        let recovered = successful_output(cycle, &cycle.operations[1]);
        assert_eq!(recovered.1, expected.len());
        assert_eq!(cycle.cleanup_phases, [vec![recovered]]);
        assert!(!cycle.publications.is_empty());
        assert!(
            cycle
                .publications
                .iter()
                .all(|owners| owners == &vec![recovered]),
            "every output write follows source retirement"
        );
        assert_eq!(
            cycle.operations[1]
                .attempts
                .iter()
                .map(|&(_, n, ok)| (n, ok))
                .collect::<Vec<_>>(),
            operation
                .attempts
                .iter()
                .map(|&(_, n, ok)| (n, ok))
                .collect::<Vec<_>>()
        );
        eprintln!(
            "toml-streaming owned reached-denial mmap={ordinal} site={site} original-owners={} recovered={} maps={} releases={} native={:.6}s",
            cycle.backing.len(),
            output.len(),
            observed.allocations,
            observed.releases,
            started.elapsed().as_secs_f64()
        );
    }
    eprintln!(
        "toml-streaming owned baseline maps={} releases={} native={:.6}s compile={:.6}s",
        baseline.allocations,
        baseline.releases,
        baseline_time.as_secs_f64(),
        compile.as_secs_f64()
    );
}
