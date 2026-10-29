//! Component ownership, every reached allocation failure, and deep iterative traversal.
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
        .join("tests/fixtures/extended_graph_components_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("graph components resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("graph components resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_graph_components_resources", name, None);
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
fn effects(events: &str, stderr: &[u8]) -> Effects {
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
    assert_eq!((entries, exits, reads), (1, 1, 1), "{events}");
    assert_eq!(report.allocations, report.releases, "{events}");
    assert_eq!(stderr, markers, "trace/native marker agreement: {events}");
    report
}
fn run(
    executable: &common::TempArtifact,
    mode: u8,
    failure: Option<usize>,
    seconds: u64,
) -> (Vec<i32>, Effects) {
    let input = common::TempArtifact::new("laniusc_graph_components_resources", "input", None);
    input.write_bytes([mode | if failure.is_some() { 16 } else { 0 }]);
    let trace = common::TempArtifact::new("laniusc_graph_components_resources", "trace", None);
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
        "graph components finite native lifecycle",
        &mut command,
        Duration::from_secs(seconds),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode} failure={failure:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some()),
        "one reached fault: {events}"
    );
    let effects = effects(&events, &output.stderr);
    assert_eq!(output.stdout.len() % 4, 0);
    let values = output
        .stdout
        .chunks_exact(4)
        .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    (values, effects)
}
fn owner_output(mode: u8, failure: bool, values: &[i32]) -> usize {
    let unit = values[5] as usize;
    assert!(unit >= 8 && unit <= 256);
    let empty = mode >= 2;
    let condensed = mode % 2 == 1;
    let mut expected = vec![
        i32::from(mode),
        i32::from(failure),
        if empty { 0 } else { 8 },
        if empty { 0 } else { 4 },
        if condensed && !empty { 5 } else { 0 },
        unit as i32,
    ];
    if !empty {
        expected.extend([0, 1, 1, 0, 1, 2, 3, 3]);
    }
    if condensed {
        if empty {
            expected.push(0);
        } else {
            expected.extend([0, 2, 4, 5, 5, 1, 2, 2, 3, 3]);
        }
    }
    assert_eq!(values, expected);
    unit
}
fn sizes(mode: u8, unit: usize) -> Vec<usize> {
    match mode {
        0 => vec![32; 6],
        1 => {
            let mut values = vec![32; 6];
            values.extend([13 * unit, 6 * unit, 20, 20]);
            values
        }
        2 => vec![],
        3 => vec![4],
        _ => unreachable!(),
    }
}
fn successful(operation: &Operation, expected: &[usize]) {
    assert_eq!(
        operation
            .attempts
            .iter()
            .map(|&(_, size, success)| (size, success))
            .collect::<Vec<_>>(),
        expected
            .iter()
            .map(|&size| (size, true))
            .collect::<Vec<_>>()
    );
}
fn retained(operation: &Operation, setup: &[usize], mode: u8) {
    let mut expected: Vec<_> = setup
        .iter()
        .enumerate()
        .map(|(index, &size)| (index + 1, size))
        .collect();
    if mode < 2 {
        let &(ordinal, size, _) = &operation.attempts[0];
        expected.push((ordinal, size));
    }
    if mode % 2 == 1 {
        let count = if mode == 3 { 1 } else { 2 };
        for &(ordinal, size, _) in operation.attempts.iter().rev().take(count) {
            expected.push((ordinal, size));
        }
    }
    expected.sort_unstable();
    assert_eq!(
        operation.live_at_return, expected,
        "only source and returned owners survive operation"
    );
}
#[test]
fn graph_components_all_reached_allocation_failures_preserve_sources_and_retire_owners() {
    let executable = executable("owners.lani");
    let mut denied = 0;
    for mode in 0..=3 {
        let (values, baseline) = run(&executable, mode, None, 10);
        let unit = owner_output(mode, false, &values);
        let setup = if mode < 2 { vec![36, 52] } else { vec![4] };
        assert_eq!(baseline.setup, setup);
        assert_eq!(baseline.operations.len(), 1);
        assert_eq!(baseline.phases, 4);
        let expected = sizes(mode, unit);
        let operation = &baseline.operations[0];
        successful(operation, &expected);
        retained(operation, &setup, mode);
        // Select every actual mmap in the accepted baseline operation. Sizes are
        // checked against current buffer reservations, never used to guess sites.
        for (site, &(ordinal, _, _)) in operation.attempts.iter().enumerate() {
            let (failed_values, failed) = run(&executable, mode, Some(ordinal), 10);
            assert_eq!(owner_output(mode, true, &failed_values), unit);
            assert_eq!(failed.setup, setup);
            assert_eq!(failed.operations.len(), 2);
            assert_eq!(failed.phases, 5);
            let interrupted = &failed.operations[0];
            assert_eq!(interrupted.attempts.len(), site + 1);
            assert_eq!(
                interrupted.live_at_return,
                setup
                    .iter()
                    .enumerate()
                    .map(|(index, &size)| (index + 1, size))
                    .collect::<Vec<_>>()
            );
            let boundary = operation.actions.iter().position(|action| matches!(action, Action::Allocate { ordinal: value, .. } if *value == ordinal)).unwrap();
            assert_eq!(
                &interrupted.actions[..boundary],
                &operation.actions[..boundary],
                "same real syscall argument/owner sequence before selected failure"
            );
            assert_eq!(
                interrupted.actions[boundary],
                Action::Allocate {
                    ordinal,
                    size: expected[site],
                    success: false
                }
            );
            successful(&failed.operations[1], &expected);
            retained(&failed.operations[1], &setup, mode);
            denied += 1;
        }
        eprintln!(
            "graph-components-owner mode={mode} baseline-sites={} reached-denials={} baseline-maps={} exact-releases={}",
            operation.attempts.len(),
            operation.attempts.len(),
            baseline.allocations,
            baseline.releases
        );
    }
    assert_eq!(denied, 17);
    eprintln!(
        "graph-components-resources baselines=4 reached-denials=17 same-process-recoveries=17"
    );
}
#[test]
fn graph_components_65536_node_shapes_match_complete_analytic_mapping_and_canonical_dags() {
    let executable = executable("scale.lani");
    for kind in 0..=2 {
        let (values, effects) = run(&executable, kind, None, 30);
        let edges = [65535, 65536, 66046][usize::from(kind)];
        let components = [65536, 1, 256][usize::from(kind)];
        let dag_edges = components - 1;
        let words = 2 * 65536 + components + 1 + dag_edges;
        let unit = values[6] as usize;
        assert!(unit >= 8 && unit <= 256);
        assert_eq!(
            &values[..7],
            &[
                i32::from(kind),
                65536,
                edges,
                components,
                dag_edges,
                words,
                unit as i32
            ]
        );
        assert_eq!(values.len(), 7 + words as usize);
        for (node, pair) in values[7..7 + 2 * 65536].chunks_exact(2).enumerate() {
            let expected = match kind {
                0 => node as i32,
                1 => 0,
                2 => (node / 256) as i32,
                _ => unreachable!(),
            };
            assert_eq!(pair, [expected, expected], "shape={kind} node={node}");
        }
        let start = 7 + 2 * 65536;
        for (node, &actual) in values[start..start + components as usize + 1]
            .iter()
            .enumerate()
        {
            assert_eq!(
                actual,
                (node as i32).min(dag_edges),
                "shape={kind} offset={node}"
            );
        }
        for (edge, &actual) in values[start + components as usize + 1..].iter().enumerate() {
            assert_eq!(actual, edge as i32 + 1, "shape={kind} edge={edge}");
        }
        assert_eq!(effects.setup, [65537 * 4, edges as usize * 4, 262145 * 4]);
        assert_eq!(effects.phases, 3);
        assert_eq!(effects.operations.len(), 2);
        successful(&effects.operations[0], &[65536 * 4; 6]);
        let mut condensation = vec![65536 * 4; 6];
        condensation.push(edges as usize * unit);
        let cross = match kind {
            0 => 65535,
            1 => 0,
            2 => 510,
            _ => unreachable!(),
        };
        if cross > 0 {
            condensation.push(cross * unit);
        }
        condensation.push((components as usize + 1) * 4);
        if dag_edges > 0 {
            condensation.push(dag_edges as usize * 4);
        }
        successful(&effects.operations[1], &condensation);
        let setup: Vec<_> = effects
            .setup
            .iter()
            .enumerate()
            .map(|(index, &size)| (index + 1, size))
            .collect();
        let mut after_strong = setup.clone();
        after_strong.push((effects.operations[0].attempts[0].0, 65536 * 4));
        after_strong.sort_unstable();
        assert_eq!(effects.operations[0].live_at_return, after_strong);
        let mut after_condensed = after_strong;
        after_condensed.push((effects.operations[1].attempts[0].0, 65536 * 4));
        for &(ordinal, size, _) in effects.operations[1]
            .attempts
            .iter()
            .rev()
            .take(if dag_edges > 0 { 2 } else { 1 })
        {
            after_condensed.push((ordinal, size));
        }
        after_condensed.sort_unstable();
        assert_eq!(effects.operations[1].live_at_return, after_condensed);
        assert_eq!(
            (effects.allocations, effects.releases),
            (3 + 6 + condensation.len(), 3 + 6 + condensation.len())
        );
        eprintln!(
            "graph-components-scale shape={kind} nodes=65536 edges={edges} components={components} canonical-edges={dag_edges} mapping-observations=131072 mappings={} exact-releases={}",
            effects.allocations, effects.releases
        );
    }
}
