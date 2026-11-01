//! Scoped map updates preserve actual nested owners and separate returned owners.
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
    let fixtures = root.join("tests/fixtures/stdlib_map_update_resources");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let bytes = common::run_gpu_codegen_with_timeout("map update resource ownership", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("map update resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_map_update_resources", name, None);
    file.write_bytes(bytes); // Shared writer validates all x86 jumps before execution.
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
    callbacks: usize,
}
#[derive(Debug, Default)]
struct Effects {
    operations: Vec<Operation>,
    phases: usize,
    cleanup_phases: Vec<Vec<(usize, usize)>>,
    cleanup_order: Vec<usize>,
    allocations: usize,
    releases: usize,
    output: usize,
}
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Vec<(usize, usize)> {
    let mut values = live.values().copied().collect::<Vec<_>>();
    values.sort_unstable();
    values
}
fn effects(events: &str, stderr: &[u8], map_bytes: usize) -> Effects {
    let setup = [10, 9, 3, 4, 2, 4, map_bytes];
    let protected = [1, 2, 5, 6, 7]; // stored/query keys, replacement owners, table
    let mut observed = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut active: Option<Operation> = None;
    let mut pure: Option<Vec<(usize, usize)>> = None;
    let (mut begun, mut sealed, mut callback, mut cleanup, mut done) =
        (false, false, false, false, false);
    let (mut entries, mut exits, mut reads, mut ordinal) = (0, 0, 0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASPpCBbFRD"
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
                        begun && !sealed && !cleanup && active.is_none() && pure.is_none(),
                        "{events}"
                    );
                    assert_eq!(ordinal, setup.len(), "{events}");
                    assert_eq!(
                        owners(&live),
                        setup
                            .iter()
                            .enumerate()
                            .map(|(i, &size)| (i + 1, size))
                            .collect::<Vec<_>>()
                    );
                    sealed = true;
                }
                b'P' => {
                    assert!(
                        sealed && active.is_none() && pure.is_none() && !callback,
                        "{events}"
                    );
                    pure = Some(owners(&live));
                }
                b'p' => {
                    let before = pure.take().unwrap();
                    assert_eq!(before, owners(&live), "{events}");
                    observed.phases += 1;
                    if cleanup {
                        observed.cleanup_phases.push(before);
                    }
                }
                b'C' => {
                    assert!(
                        sealed && !cleanup && !callback && active.is_none() && pure.is_none(),
                        "{events}"
                    );
                    active = Some(Operation::default());
                }
                b'B' => {
                    assert!(
                        sealed && !cleanup && !callback && active.is_some() && pure.is_none(),
                        "{events}"
                    );
                    let operation = active.as_mut().unwrap();
                    assert_eq!(
                        operation.callbacks, 0,
                        "exactly one callback per present update"
                    );
                    operation.callbacks += 1;
                    callback = true;
                }
                b'b' => {
                    assert!(callback && active.is_some() && pure.is_none(), "{events}");
                    callback = false;
                }
                b'F' => {
                    assert!(!callback && pure.is_none(), "{events}");
                    let mut operation = active.take().unwrap();
                    assert_eq!(operation.callbacks, 1, "{events}");
                    operation.live_at_return = owners(&live);
                    observed.operations.push(operation);
                }
                b'R' => {
                    assert!(
                        sealed && !cleanup && !callback && active.is_none() && pure.is_none(),
                        "{events}"
                    );
                    cleanup = true;
                }
                b'D' => {
                    assert!(
                        cleanup
                            && !callback
                            && active.is_none()
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
            "pure map/value observation performed a host effect: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            continue;
        }
        assert!(
            !done,
            "only exit follows explicit complete cleanup: {events}"
        );
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
                "map update allocation outside callback: {events}"
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
                    "source-derived setup extent: {events}"
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
                    "{events}"
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
            if let Some(operation) = active.as_mut() {
                operation.attempts.push((ordinal, size, success));
                operation.actions.push(Action::Allocate {
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
                "only callback or explicit caller cleanup may release: {events}"
            );
            let (pointer, size) = arguments(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (allocation, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown or duplicate owner release: {line}\n{events}"));
            assert_eq!(
                size, actual,
                "exact full-width address/extent release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            observed.releases += 1;
            if callback {
                assert!(
                    !protected.contains(&allocation),
                    "callback cannot retire map or key/context owner: {events}"
                );
                active.as_mut().unwrap().actions.push(Action::Release {
                    ordinal: allocation,
                    size,
                });
            } else {
                observed.cleanup_order.push(allocation);
            }
        } else if line.starts_with("write(1,") {
            assert!(sealed && !callback && active.is_none(), "{events}");
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
        done && !callback && active.is_none() && pure.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!((entries, reads, exits), (1, 1, 1), "{events}");
    assert_eq!(
        observed.allocations, observed.releases,
        "cleanup is observed before exit: {events}"
    );
    assert_eq!(
        stderr, markers,
        "native markers agree with the complete syscall trace"
    );
    observed
}
fn run(
    executable: &common::TempArtifact,
    mode: u8,
    denial: Option<usize>,
    map_bytes: usize,
) -> Effects {
    let input = common::TempArtifact::new("laniusc_map_update_resources", "input", None);
    input.write_bytes([mode]);
    let trace = common::TempArtifact::new("laniusc_map_update_resources", "trace", None);
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
    let output = common::process_output_with_timeout(
        "map update owner lifecycle",
        &mut command,
        Duration::from_secs(12),
    );
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
        "configured denial must be reached: {events}"
    );
    let mut expected = b"stored-keyquery-key".to_vec();
    expected.extend([90, 91]);
    expected.extend(b"new!");
    expected.extend([1, 2, 3, 42]);
    expected.extend("seedé🙂!".as_bytes());
    expected.extend(b"owned-error");
    assert_eq!(
        output.stdout, expected,
        "complete representatives, replacement, displaced owner and independent error"
    );
    let observed = effects(&events, &output.stderr, map_bytes);
    assert_eq!(observed.output, expected.len());
    observed
}
fn expected_live(
    map_bytes: usize,
    vector: usize,
    label: usize,
    report: Option<usize>,
) -> Vec<(usize, usize)> {
    let mut live = vec![(1, 10), (2, 9), (5, 2), (6, 4), (7, map_bytes)];
    live.push((vector, if vector == 3 { 3 } else { 6 }));
    live.push((label, if label == 4 { 4 } else { 11 }));
    if let Some(report) = report {
        live.push((report, 11));
    }
    live.sort_unstable();
    live
}
fn settled(
    observed: &Effects,
    map_bytes: usize,
    updated: usize,
    vector: usize,
    label: usize,
    report: usize,
) {
    let live = expected_live(map_bytes, vector, label, Some(report));
    assert_eq!(observed.operations[updated].live_at_return, live);
    let replacement = &observed.operations[updated + 1];
    assert_eq!(replacement.callbacks, 1);
    assert!(
        replacement.actions.is_empty() && replacement.attempts.is_empty(),
        "replacement returns old owners without allocating or destroying"
    );
    assert_eq!(replacement.live_at_return, live);
    assert_eq!(
        observed.cleanup_phases,
        [vec![(vector, 6), (label, 11), (report, 11)]],
        "displaced value plus independent error survive all map/key/replacement cleanup"
    );
    assert_eq!(
        observed.cleanup_order,
        [1, 5, 6, 7, 2, vector, label, report],
        "one cleanup authority for each owner"
    );
    assert_eq!((observed.allocations, observed.releases), (10, 10));
}
fn exercise(name: &str, map_bytes: usize) {
    let executable = executable(name);
    let baseline = run(&executable, 0, None, map_bytes);
    assert_eq!(baseline.operations.len(), 2);
    assert_eq!(baseline.phases, 4);
    let growth = &baseline.operations[0];
    assert_eq!(
        growth.attempts,
        [(8, 6, true), (9, 11, true), (10, 11, true)]
    );
    assert_eq!(
        growth.actions,
        [
            Action::Allocate {
                ordinal: 8,
                size: 6,
                success: true
            },
            Action::Release {
                ordinal: 3,
                size: 3
            },
            Action::Allocate {
                ordinal: 9,
                size: 11,
                success: true
            },
            Action::Release {
                ordinal: 4,
                size: 4
            },
            Action::Allocate {
                ordinal: 10,
                size: 11,
                success: true
            },
        ]
    );
    settled(&baseline, map_bytes, 0, 8, 9, 10);
    // Select only reached descriptor growth sites from this successful
    // callback baseline. The separate error allocation is not under test.
    for site in [0, 1] {
        let (ordinal, size, _) = growth.attempts[site];
        let observed = run(&executable, (site + 1) as u8, Some(ordinal), map_bytes);
        assert_eq!(observed.operations.len(), 3);
        assert_eq!(observed.phases, 5);
        let failed = &observed.operations[0];
        let boundary = growth.actions.iter().position(|action| matches!(action, Action::Allocate { ordinal: current, .. } if *current == ordinal)).unwrap();
        assert_eq!(
            &failed.actions[..boundary],
            &growth.actions[..boundary],
            "complete normalized effect prefix before reached denial"
        );
        assert_eq!(
            &failed.actions[boundary..],
            [Action::Allocate {
                ordinal,
                size,
                success: false
            }],
            "failed reservation retains the current valid value"
        );
        assert_eq!(failed.attempts.len(), site + 1);
        if site == 0 {
            assert_eq!(failed.live_at_return, expected_live(map_bytes, 3, 4, None));
            assert_eq!(
                observed.operations[1].attempts,
                [(9, 6, true), (10, 11, true), (11, 11, true)]
            );
            settled(&observed, map_bytes, 1, 9, 10, 11);
        } else {
            assert_eq!(failed.live_at_return, expected_live(map_bytes, 8, 4, None));
            assert_eq!(
                observed.operations[1].attempts,
                [(10, 11, true), (11, 11, true)]
            );
            settled(&observed, map_bytes, 1, 8, 10, 11);
        }
        eprintln!(
            "map-update resource={name} reached-denial={ordinal} callback-site={site} exact-maps=10 exact-releases=10 current-value-installed=true same-process-recovery=true"
        );
    }
    eprintln!(
        "map-update resource={name} baseline-map-bytes={map_bytes} separate-error=true displaced-owner-survives-map=true"
    );
}
#[test]
fn hash_map_updates_preserve_owned_descriptors_and_recover_callback_allocation_failures() {
    // Key = two scalar words + String(Vec's three words) = 5 words.
    // V = Pair<Vec<u8>,String> = 6 words; Entry = 11 words.
    // Slot = one enum tag + cached hash + Entry = 13 words. Eight buckets.
    // core::mem uses eight-byte record words, not C-style packed i32 fields.
    exercise("hash.lani", 8 * 13 * 8);
}
#[test]
fn tree_map_updates_preserve_owned_descriptors_and_recover_callback_allocation_failures() {
    // Entry = the same eleven words; Node adds five scalar link/height/free
    // fields. Four pre-reserved nodes, with eight bytes per native word.
    exercise("tree.lani", 4 * 16 * 8);
}
