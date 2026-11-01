//! Manual owner transfer and callback effects for canonical lazy outcomes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_lazy_outcomes_resources");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let started = Instant::now();
    let bytes = common::run_gpu_codegen_with_timeout("lazy outcome resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("lazy outcome resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_lazy_outcomes_resources", name, None);
    artifact.write_bytes(bytes); // Shared writer checks x86 jumps before execution.
    fs::set_permissions(artifact.path(), fs::Permissions::from_mode(0o700)).unwrap();
    eprintln!(
        "lazy-outcomes resource={name} compile={:.6}s",
        started.elapsed().as_secs_f64()
    );
    artifact
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
type Owners = Vec<(usize, usize)>;
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Owners {
    let mut result = live.values().copied().collect::<Vec<_>>();
    result.sort_unstable();
    result
}
#[derive(Debug, Clone, PartialEq, Eq)]
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
    live_at_return: Owners,
    callbacks: usize,
}
#[derive(Debug, Default)]
struct Effects {
    operations: Vec<Operation>,
    pure: Vec<Owners>,
    cleanup: Vec<usize>,
    allocations: usize,
    releases: usize,
    output: usize,
}
fn effects(events: &str, stderr: &[u8], setup_count: usize, published: &Owners) -> Effects {
    // Every owner is exactly Vec<u8>(8) plus String's packed Vec<u8>(12).
    // The Pair/Owner records themselves are values, with no backing allocation.
    let setup = (0..setup_count).flat_map(|_| [8, 12]).collect::<Vec<_>>();
    let expected_setup = setup
        .iter()
        .enumerate()
        .map(|(i, &n)| (i + 1, n))
        .collect::<Owners>();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut observed = Effects::default();
    let mut operation: Option<Operation> = None;
    let mut pure: Option<Owners> = None;
    let (mut begun, mut sealed, mut callback, mut cleanup, mut done) =
        (false, false, false, false, false);
    let (mut ordinal, mut entries, mut reads, mut exits) = (0, 0, 0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASCBbFPpRD"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(!begun && live.is_empty(), "{events}");
                    begun = true;
                }
                b'S' => {
                    assert!(
                        begun && !sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    assert_eq!(ordinal, setup.len(), "{events}");
                    assert_eq!(owners(&live), expected_setup, "{events}");
                    sealed = true;
                }
                b'C' => {
                    assert!(
                        sealed && !cleanup && !callback && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    operation = Some(Operation::default());
                }
                b'B' => {
                    assert!(
                        sealed && !cleanup && !callback && operation.is_some() && pure.is_none(),
                        "{events}"
                    );
                    let current = operation.as_mut().unwrap();
                    assert_eq!(
                        current.callbacks, 0,
                        "callback must run exactly once: {events}"
                    );
                    current.callbacks += 1;
                    callback = true;
                }
                b'b' => {
                    assert!(
                        callback && operation.is_some() && pure.is_none(),
                        "{events}"
                    );
                    callback = false;
                }
                b'F' => {
                    assert!(!callback && pure.is_none(), "{events}");
                    let mut current = operation.take().unwrap();
                    assert_eq!(current.callbacks, 1, "{events}");
                    current.live_at_return = owners(&live);
                    observed.operations.push(current);
                }
                b'P' => {
                    assert!(
                        sealed && operation.is_none() && pure.is_none() && !callback,
                        "{events}"
                    );
                    pure = Some(owners(&live));
                }
                b'p' => {
                    let before = pure.take().unwrap();
                    assert_eq!(before, owners(&live), "{events}");
                    observed.pure.push(before);
                }
                b'R' => {
                    assert!(
                        sealed && !cleanup && !callback && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    cleanup = true;
                }
                b'D' => {
                    assert!(
                        cleanup
                            && !callback
                            && operation.is_none()
                            && pure.is_none()
                            && live.is_empty(),
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
            "pure outcome dispatch or observation performed a host effect: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows observed cleanup: {events}");
        if line.starts_with("execve(") {
            assert!(!begun && entries == 0, "{events}");
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(!begun && reads == 0 && ordinal == 0, "{events}");
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            assert!(
                begun && !cleanup && (!sealed || callback),
                "allocation outside callback or setup: {events}"
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
            if !sealed {
                assert_eq!(
                    Some(&size),
                    setup.get(ordinal - 1),
                    "source-derived extent: {events}"
                );
            }
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
                    "overlapping live owners: {events}"
                );
                assert!(live.insert(pointer, (ordinal, size)).is_none(), "{events}");
                observed.allocations += 1;
            } else {
                assert!(
                    callback
                        && pointer == "-1"
                        && returned.contains("ENOMEM")
                        && returned.contains("INJECTED"),
                    "{events}"
                );
            }
            if let Some(current) = operation.as_mut() {
                current.attempts.push((ordinal, size, success));
                current.actions.push(Action::Allocate {
                    ordinal,
                    size,
                    success,
                });
            } else {
                assert!(!sealed && success, "{events}");
            }
        } else if line.starts_with("munmap(") {
            assert!(
                sealed && (callback || cleanup),
                "release outside callback or caller cleanup: {events}"
            );
            let (pointer, size) = arguments(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (allocation, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown or duplicate release: {line}\n{events}"));
            assert_eq!(
                size, actual,
                "full-width exact address/extent release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            observed.releases += 1;
            if callback {
                operation.as_mut().unwrap().actions.push(Action::Release {
                    ordinal: allocation,
                    size,
                });
            } else {
                observed.cleanup.push(allocation);
            }
        } else if line.starts_with("write(1,") {
            assert!(cleanup && !callback && operation.is_none(), "{events}");
            assert_eq!(
                &owners(&live),
                published,
                "only independent output owners survive at every publication: {events}"
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
            observed.output += used;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        done && !callback && operation.is_none() && pure.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!((entries, reads, exits), (1, 1, 1), "{events}");
    assert_eq!(
        observed.allocations, observed.releases,
        "releases are observed before exit: {events}"
    );
    assert_eq!(
        stderr, markers,
        "marker bytes agree with complete syscall trace"
    );
    observed
}
fn run(
    executable: &common::TempArtifact,
    mode: u8,
    denial: Option<usize>,
    setup: usize,
    output_id: u8,
    published: Owners,
) -> Effects {
    let input = common::TempArtifact::new("laniusc_lazy_outcomes_resources", "input", None);
    input.write_bytes([mode]);
    let trace = common::TempArtifact::new("laniusc_lazy_outcomes_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = denial {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "lazy outcome owner effects",
        &mut command,
        Duration::from_secs(12),
    );
    let native = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode} denial={denial:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(denial.is_some()),
        "denial must be reached: {events}"
    );
    let mut expected = (0..8)
        .map(|i| output_id.wrapping_mul(17).wrapping_add(i))
        .collect::<Vec<_>>();
    expected.extend(b"owner-value!");
    assert_eq!(
        output.stdout, expected,
        "complete independent nested owner after input retirement"
    );
    let observed = effects(&events, &output.stderr, setup, &published);
    assert_eq!(observed.output, expected.len());
    eprintln!(
        "lazy-outcomes mode={mode} reached-denial={denial:?} exact-maps={} exact-releases={} pure-phases={} full-output={} native={:.6}s",
        observed.allocations,
        observed.releases,
        observed.pure.len(),
        observed.output,
        native.as_secs_f64()
    );
    observed
}
fn allocate(ordinal: usize, size: usize, success: bool) -> Action {
    Action::Allocate {
        ordinal,
        size,
        success,
    }
}
fn release(ordinal: usize, size: usize) -> Action {
    Action::Release { ordinal, size }
}

#[test]
fn lazy_outcomes_transfer_nested_owners_and_leave_discarded_resources_to_the_caller() {
    let executable = executable("owners.lani");
    let observed = run(&executable, 0, None, 6, 11, vec![(13, 8), (14, 12)]);
    assert_eq!(observed.operations.len(), 2);
    assert_eq!(
        observed.operations[0].actions,
        [
            allocate(13, 8, true),
            allocate(14, 12, true),
            release(1, 8),
            release(2, 12)
        ]
    );
    assert_eq!(
        observed.operations[0].live_at_return,
        (3..=14)
            .map(|n| (n, if n % 2 == 1 { 8 } else { 12 }))
            .collect::<Owners>()
    );
    assert_eq!(
        observed.operations[1].actions,
        [release(3, 8), release(4, 12)]
    );
    let surviving = (5..=14)
        .map(|n| (n, if n % 2 == 1 { 8 } else { 12 }))
        .collect::<Owners>();
    assert_eq!(observed.operations[1].live_at_return, surviving);
    assert_eq!(
        observed.pure,
        [
            surviving.clone(),
            surviving.clone(),
            surviving.clone(),
            surviving,
            vec![(13, 8), (14, 12)]
        ]
    );
    assert_eq!(
        observed.cleanup,
        [5, 6, 9, 10, 7, 8, 11, 12, 13, 14],
        "discarded fallback/filter owners and surviving values each retire exactly once"
    );
    assert_eq!((observed.allocations, observed.releases), (14, 14));
}

#[test]
fn lazy_outcomes_return_callback_allocation_failure_owners_for_same_process_retry() {
    let executable = executable("failure.lani");
    let baseline = run(&executable, 0, None, 1, 17, vec![(3, 8), (4, 12)]);
    assert_eq!(baseline.operations.len(), 1);
    let operation = &baseline.operations[0];
    assert_eq!(operation.attempts, [(3, 8, true), (4, 12, true)]);
    assert_eq!(
        operation.actions,
        [
            allocate(3, 8, true),
            allocate(4, 12, true),
            release(1, 8),
            release(2, 12)
        ]
    );
    assert_eq!(operation.live_at_return, [(3, 8), (4, 12)]);
    assert_eq!(baseline.pure, [vec![(3, 8), (4, 12)]]);
    assert_eq!(baseline.cleanup, [3, 4]);
    assert_eq!(baseline.allocations, 4);
    // Select the reached second callback allocation. This witnesses partial
    // construction cleanup; it is not a fictitious library allocation site.
    let (ordinal, size, success) = operation.attempts[1];
    assert!(success);
    let failed = run(&executable, 1, Some(ordinal), 1, 17, vec![(5, 8), (6, 12)]);
    assert_eq!(failed.operations.len(), 2);
    let boundary = operation
        .actions
        .iter()
        .position(|action| matches!(action, Action::Allocate { ordinal: n, .. } if *n == ordinal))
        .unwrap();
    assert_eq!(
        &failed.operations[0].actions[..boundary],
        &operation.actions[..boundary],
        "complete normalized baseline prefix before denial"
    );
    assert_eq!(
        &failed.operations[0].actions[boundary..],
        [allocate(ordinal, size, false), release(3, 8)],
        "callback retires its partial result, then returns the original owner"
    );
    assert_eq!(failed.operations[0].live_at_return, [(1, 8), (2, 12)]);
    assert_eq!(
        failed.operations[1].actions,
        [
            allocate(5, 8, true),
            allocate(6, 12, true),
            release(1, 8),
            release(2, 12)
        ]
    );
    assert_eq!(failed.operations[1].live_at_return, [(5, 8), (6, 12)]);
    assert_eq!(failed.pure, [vec![(1, 8), (2, 12)], vec![(5, 8), (6, 12)]]);
    assert_eq!(failed.cleanup, [5, 6]);
    assert_eq!((failed.allocations, failed.releases), (5, 5));
}
