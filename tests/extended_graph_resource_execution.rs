//! Directed graph resource cleanup, honest backing and reserved analytic scale.
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
        .join("tests/fixtures/extended_graph_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("graph resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("graph resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_graph_resources", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    let before = line.rsplit_once('=').unwrap().0.trim_end();
    before.strip_suffix(')').unwrap().split_once('(').unwrap().1
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
#[derive(Debug, Default)]
struct Operation {
    attempts: Vec<(usize, bool)>,
    live_at_return: usize,
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
fn effects(events: &str, stderr: &[u8], config: bool) -> Effects {
    let mut report = Effects::default();
    let mut live = BTreeMap::<u64, usize>::new();
    let mut active: Option<Operation> = None;
    let mut pure = false;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
    let mut reads = 0;
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
                    operation.live_at_return = live.len();
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
                        "all actual owners retired before D: {events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "pure graph/admission/check phase reached host service: {line}"
        );
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
                config
                    && reads == 0
                    && report.setup.is_empty()
                    && active.is_none()
                    && report.operations.is_empty(),
                "one configuration read: {events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields[0], "NULL", "{events}");
            let length: usize = fields[1].parse().unwrap();
            assert!(length > 0, "{events}");
            let value = result(line);
            let pointer = value.split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            if success {
                assert!(!value.contains("INJECTED"), "{events}");
                assert!(
                    live.insert(address(pointer), length).is_none(),
                    "distinct live owner: {events}"
                );
                report.allocations += 1;
            } else {
                assert!(
                    pointer == "-1" && value.contains("ENOMEM") && value.contains("INJECTED"),
                    "real reached allocation error: {events}"
                );
            }
            if let Some(operation) = active.as_mut() {
                operation.attempts.push((length, success));
            } else {
                assert!(
                    success && report.phases == 0 && report.operations.is_empty(),
                    "all setup reserved before work: {events}"
                );
                report.setup.push(length);
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
        } else if line.starts_with("mprotect(") {
            assert!(
                active.is_none()
                    && report.phases == 0
                    && report.protections == 0
                    && report.setup == [8192]
                    && live.len() == 1,
                "one pre-phase page protection: {events}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            let (&pointer, &length) = live.iter().next().unwrap();
            assert_eq!(length, 8192);
            assert_eq!(pointer % 4096, 0);
            assert_eq!(address(fields[0]), pointer + 4096);
            assert_eq!(&fields[1..], &["4096", "PROT_NONE"]);
            assert_eq!(result(line), "0", "{events}");
            report.protections += 1;
        } else if line.starts_with("write(1,") {
            assert!(
                active.is_none(),
                "publish only returned observations: {events}"
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
        (1, 1, usize::from(config)),
        "{events}"
    );
    assert_eq!(report.allocations, report.releases, "{events}");
    assert_eq!(
        stderr, markers,
        "native markers agree with full trace: {events}"
    );
    report
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
    seconds: u64,
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_graph_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_graph_resources", "trace", None);
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
        "graph resource finite native lifecycle",
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
        "exactly one reached selected fault: {events}"
    );
    let effects = effects(&events, &output.stderr, mode.is_some());
    (output.stdout, effects)
}
fn words(bytes: &[u8]) -> Vec<i32> {
    assert_eq!(bytes.len() % 4, 0);
    bytes
        .chunks_exact(4)
        .map(|value| i32::from_le_bytes(value.try_into().unwrap()))
        .collect()
}

#[test]
fn graph_selected_allocation_failures_preserve_inputs_and_retire_partial_owners() {
    let executable = executable("owners.lani");
    let sizes: [&[usize]; 5] = [
        &[96, 28, 20],
        &[28, 20],
        &[24, 24, 24],
        &[24, 24, 24],
        &[24, 24, 24],
    ];
    let live = [2, 2, 2, 1, 0];
    let schedules = [
        (0, None),
        (1, None),
        (2, None),
        (3, None),
        (4, None),
        (0, Some(1)),
        (0, Some(3)),
        (1, Some(2)),
        (2, Some(1)),
        (2, Some(3)),
        (3, Some(1)),
        (3, Some(3)),
    ];
    for (mode, failure) in schedules {
        let (output, effects) = run(&executable, Some(mode), failure, 10);
        let status = if failure.is_some() {
            1
        } else if mode == 4 {
            2
        } else {
            0
        };
        assert_eq!(
            words(&output),
            [i32::from(mode), status, 6, if mode == 4 { 4 } else { 5 }]
        );
        assert!(effects.setup.is_empty());
        assert_eq!(effects.operations.len(), 1);
        assert_eq!(effects.protections, 0);
        let expected: Vec<_> = sizes[usize::from(mode)]
            .iter()
            .copied()
            .take(failure.unwrap_or(usize::MAX))
            .enumerate()
            .map(|(index, size)| (size, failure != Some(index + 1)))
            .collect();
        assert_eq!(effects.operations[0].attempts, expected);
        assert_eq!(
            effects.operations[0].live_at_return,
            if failure.is_some() {
                0
            } else {
                live[usize::from(mode)]
            }
        );
        assert_eq!(effects.phases, if status == 0 { 2 } else { 1 });
        eprintln!(
            "graph-owner mode={mode} fault={failure:?} status={status} mappings={} exact-releases={}",
            effects.allocations, effects.releases
        );
    }
}

fn expected(kind: u8, node: usize) -> (i32, i32) {
    if kind == 0 {
        return (node as i32, if node == 0 { -1 } else { node as i32 - 1 });
    }
    if kind == 1 {
        return (
            if node == 0 { 0 } else { 1 },
            if node == 0 { -1 } else { 0 },
        );
    }
    let (level, column) = (node / 256, node % 256);
    if column > level {
        return (-1, -1);
    }
    (
        level as i32,
        if node == 0 {
            -1
        } else {
            ((level - 1) * 256 + column.saturating_sub(1)) as i32
        },
    )
}
#[test]
fn graph_reserved_65536_node_shapes_match_analytic_paths_and_order() {
    let executable = executable("scale.lani");
    for kind in 0..=2 {
        let (output, effects) = run(&executable, Some(kind), None, 30);
        let values = words(&output);
        let edges = if kind == 2 { 130560 } else { 65535 };
        let reached = if kind == 2 { 32896 } else { 65536 };
        let maximum = if kind == 0 {
            65535
        } else if kind == 1 {
            1
        } else {
            255
        };
        assert_eq!(
            &values[..6],
            &[i32::from(kind), 65536, edges, reached, maximum, 196608]
        );
        assert_eq!(values.len(), 6 + 3 * 65536);
        for (node, row) in values[6..].chunks_exact(3).enumerate() {
            let (distance, parent) = expected(kind, node);
            assert_eq!(
                row,
                &[distance, parent, node as i32],
                "shape={kind} node={node}"
            );
        }
        assert_eq!(effects.setup, [65537 * 4, edges as usize * 4, 196608 * 4]);
        assert_eq!(effects.phases, 2);
        assert_eq!(effects.protections, 0);
        assert_eq!(effects.operations.len(), 2);
        for operation in &effects.operations {
            assert_eq!(
                operation.attempts,
                [(65536 * 4, true); 3],
                "all final/workspaces reserved once, no traversal growth"
            );
        }
        assert_eq!(effects.operations[0].live_at_return, 5);
        assert_eq!(effects.operations[1].live_at_return, 6);
        assert_eq!((effects.allocations, effects.releases), (9, 9));
        eprintln!(
            "graph-scale shape={kind} nodes=65536 edges={edges} reachable={reached} max-distance={maximum} algorithm-allocations=3+3 mappings=9 releases=9"
        );
    }
}

#[test]
fn graph_guarded_adjacency_and_metadata_rejection_respect_honest_extents() {
    let executable = executable("boundaries.lani");
    let (output, effects) = run(&executable, None, None, 10);
    assert!(output.is_empty());
    assert_eq!(effects.setup, [8192]);
    assert!(effects.operations.is_empty());
    assert_eq!(
        (
            effects.allocations,
            effects.releases,
            effects.protections,
            effects.phases
        ),
        (1, 1, 1, 3)
    );
    eprintln!("graph-boundaries pure-phases=3 guarded-mappings=1 protections=1 exact-releases=1");
}
#[test]
fn graph_logical_views_retain_the_actual_backing_precondition() {
    for name in ["offset_overclaim.lani", "target_overclaim.lani"] {
        let executable = executable(name);
        let output = common::process_output_with_timeout(
            name,
            &mut Command::new(executable.path()),
            Duration::from_secs(5),
        );
        assert_eq!(
            output.status.code(),
            Some(101),
            "physical caller-precondition trap {name}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
