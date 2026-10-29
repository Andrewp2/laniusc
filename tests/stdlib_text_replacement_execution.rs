//! Literal UTF-8 matcher and independent owned replacement contracts.
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
        .join("tests/fixtures/stdlib_text_replacement")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let result = common::TempArtifact::new("laniusc_text_replacement", name, None);
    result.write_bytes(bytes);
    fs::set_permissions(result.path(), fs::Permissions::from_mode(0o700)).unwrap();
    result
}
fn returned(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn args(line: &str) -> &str {
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
    Allocate(usize, usize, bool),
    Release(usize, usize),
}
#[derive(Debug, Default)]
struct Operation {
    actions: Vec<Action>,
    before: Vec<(usize, usize)>,
    after: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Cycle {
    setup: Vec<Action>,
    backing: Vec<(usize, usize)>,
    operations: Vec<Operation>,
    phases: usize,
    publications: Vec<Vec<(usize, usize)>>,
    cleanup: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Effects {
    cycles: Vec<Cycle>,
    allocations: usize,
    releases: usize,
    output: usize,
}
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Vec<(usize, usize)> {
    let mut result = live.values().copied().collect::<Vec<_>>();
    result.sort_unstable();
    result
}
fn ledger(events: &str, stderr: &[u8], configured: bool) -> Effects {
    let mut observed = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut markers = Vec::new();
    let (mut cycle, mut operation): (Option<Cycle>, Option<Operation>) = (None, None);
    let (mut sealed, mut pure, mut cleanup, mut done) = (false, false, false, false);
    let (mut entries, mut exits, mut reads, mut ordinal) = (0, 0, 0, 0);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done);
            assert_eq!(returned(line), "1");
            let marker = *b"ASPpCFRED"
                .iter()
                .find(|&&byte| line.contains(&format!("\"{}\", 1)", char::from(byte))))
                .unwrap();
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(cycle.is_none() && live.is_empty() && operation.is_none() && !pure);
                    cycle = Some(Cycle::default());
                    sealed = false;
                    cleanup = false;
                }
                b'S' => {
                    assert!(cycle.is_some() && !sealed && !cleanup);
                    cycle.as_mut().unwrap().backing = owners(&live);
                    sealed = true;
                }
                b'P' => {
                    assert!(sealed && !pure && operation.is_none());
                    pure = true;
                }
                b'p' => {
                    assert!(pure);
                    pure = false;
                    cycle.as_mut().unwrap().phases += 1;
                }
                b'C' => {
                    assert!(sealed && !pure && !cleanup && operation.is_none());
                    operation = Some(Operation {
                        before: owners(&live),
                        ..Operation::default()
                    });
                }
                b'F' => {
                    assert!(sealed && !pure && !cleanup);
                    let mut completed = operation.take().unwrap();
                    completed.after = owners(&live);
                    cycle.as_mut().unwrap().operations.push(completed);
                }
                b'R' => {
                    assert!(sealed && !pure && !cleanup && operation.is_none());
                    cleanup = true;
                }
                b'E' => {
                    assert!(cleanup && !pure && live.is_empty() && operation.is_none());
                    observed.cycles.push(cycle.take().unwrap());
                    sealed = false;
                }
                b'D' => {
                    assert!(cycle.is_none() && live.is_empty() && !pure && operation.is_none());
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "borrowed/preflight checking performed host work: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty());
            exits += 1;
            continue;
        }
        assert!(!done);
        if line.starts_with("execve(") {
            assert!(cycle.is_none() && entries == 0);
            assert_eq!(returned(line), "0");
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(configured && reads == 0 && ordinal == 0 && cycle.is_none());
            assert!(args(line).ends_with(", 1"));
            assert_eq!(returned(line), "1");
            reads += 1;
        } else if line.starts_with("mmap(") {
            assert!(cycle.is_some() && !cleanup && (!sealed || operation.is_some()));
            let fields = args(line).split(',').map(str::trim).collect::<Vec<_>>();
            assert_eq!(fields.len(), 6);
            assert_eq!(fields[0], "NULL");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ]
            );
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0);
            ordinal += 1;
            let pointer = returned(line).split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            if success {
                assert!(!returned(line).contains("INJECTED"));
                let start = address(pointer);
                let end = start.checked_add(size as u64).unwrap();
                assert!(
                    live.iter().all(
                        |(&other, &(_, length))| end <= other || start >= other + length as u64
                    )
                );
                assert!(live.insert(start, (ordinal, size)).is_none());
                observed.allocations += 1;
            } else {
                assert!(
                    operation.is_some()
                        && pointer == "-1"
                        && returned(line).contains("ENOMEM")
                        && returned(line).contains("INJECTED")
                );
            }
            let action = Action::Allocate(ordinal, size, success);
            if let Some(operation) = operation.as_mut() {
                operation.actions.push(action);
            } else {
                assert!(success);
                cycle.as_mut().unwrap().setup.push(action);
            }
        } else if line.starts_with("munmap(") {
            assert!(cycle.is_some() && (operation.is_some() || cleanup));
            let (pointer, size) = args(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (id, actual) = live
                .remove(&address(pointer))
                .expect("exact live cleanup address");
            assert_eq!(size, actual);
            assert_eq!(returned(line), "0");
            observed.releases += 1;
            if let Some(operation) = operation.as_mut() {
                operation.actions.push(Action::Release(id, size));
            } else {
                cycle.as_mut().unwrap().cleanup.push((id, size));
            }
        } else if line.starts_with("write(1,") {
            assert!(sealed && operation.is_none());
            cycle.as_mut().unwrap().publications.push(owners(&live));
            let count: usize = args(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = returned(line).parse().unwrap();
            assert!(used > 0 && used <= count);
            observed.output += used;
        } else {
            panic!("unexpected host effect: {line}");
        }
    }
    assert!(done && live.is_empty() && cycle.is_none());
    assert_eq!((entries, exits, reads), (1, 1, usize::from(configured)));
    assert_eq!(observed.allocations, observed.releases);
    assert_eq!(stderr, markers);
    observed
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
) -> (Vec<u8>, Effects, Duration) {
    let input = common::TempArtifact::new("laniusc_text_replacement", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_text_replacement", "trace", None);
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
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "literal text replacement",
        &mut command,
        Duration::from_secs(15),
    );
    let native = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some())
    );
    let observed = ledger(&events, &output.stderr, mode.is_some());
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed, native)
}
#[test]
fn literal_match_indices_and_owned_replacement_native_admission() {
    let started = Instant::now();
    let executable = executable("admission.lani");
    let compile = started.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert!(output.is_empty());
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    assert!(cycle.setup.is_empty());
    assert_eq!(cycle.phases, 2);
    assert_eq!(cycle.operations.len(), 1);
    assert_eq!(
        cycle.operations[0].actions,
        [Action::Allocate(1, 4, true), Action::Allocate(2, 3, true)]
    );
    assert_eq!(cycle.cleanup, [(1, 4), (2, 3)]);
    assert_eq!((observed.allocations, observed.releases), (2, 2));
    eprintln!(
        "literal-text admission matching+replace+replacen exact-maps=2 exact-releases=2 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

#[test]
fn literal_match_indices_scalar_boundaries_strides_copies_and_generic_composition_execute() {
    let started = Instant::now();
    let executable = executable("matcher.lani");
    let compile = started.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert!(output.is_empty());
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    assert!(
        cycle.setup.is_empty()
            && cycle.backing.is_empty()
            && cycle.operations.is_empty()
            && cycle.cleanup.is_empty()
    );
    assert_eq!(cycle.phases, 1);
    assert_eq!((observed.allocations, observed.releases), (0, 0));
    eprintln!(
        "literal-text matcher packed+descending generic-take+copies fused=true host-effects=0 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

#[test]
fn literal_owned_replacement_exact_limits_u64_counts_and_valid_backed_overflow_execute() {
    let started = Instant::now();
    let executable = executable("owned.lani");
    let compile = started.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert!(output.is_empty());
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    assert_eq!(
        cycle.setup,
        [
            Action::Allocate(1, 32768, true),
            Action::Allocate(2, 65536, true)
        ]
    );
    assert_eq!(cycle.backing, [(1, 32768), (2, 65536)]);
    let lengths = [3, 2, 4, 5, 4, 3, 3, 3, 3, 0, 0, 1, 0, 13, 10, 6, 11, 0, 8];
    assert_eq!(cycle.operations.len(), lengths.len());
    assert_eq!(cycle.phases, 17);
    let mut ordinal = 3;
    for (operation, length) in cycle.operations.iter().zip(lengths) {
        assert_eq!(operation.before, cycle.backing);
        assert_eq!(operation.after, cycle.backing);
        if length == 0 {
            assert!(
                operation.actions.is_empty(),
                "empty results allocate nothing"
            );
        } else {
            assert_eq!(
                operation.actions,
                [
                    Action::Allocate(ordinal, length, true),
                    Action::Release(ordinal, length)
                ]
            );
            ordinal += 1;
        }
    }
    assert_eq!(cycle.cleanup, [(2, 65536), (1, 32768)]);
    assert_eq!((observed.allocations, observed.releases), (17, 17));
    eprintln!(
        "literal-text owned cases=19 nonempty-results=15 empty-results=4 conceptual-overflow-bytes=2147483648 exact-maps=17 exact-releases=17 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

fn resource_expected() -> Vec<u8> {
    let pattern = "aéaé\0🙂aaaab ccc\tx\r\nDEF€GH";
    assert_eq!(pattern.len(), 32);
    let source = pattern.repeat(128);
    let mut result = source.replace('é', "🙂").into_bytes();
    result.extend_from_slice(source.as_bytes()); // Count-zero independent copy.
    result.extend_from_slice(source.as_bytes()); // No-match independent copy.
    result.extend_from_slice(pattern.repeat(8192).replace('é', "🙂").as_bytes());
    assert_eq!(result.len(), 307712);
    result
}
fn resource_observations(observed: &Effects, failure: bool) {
    assert_eq!(observed.cycles.len(), 2);
    for (index, (cycle, blocks)) in observed.cycles.iter().zip([128, 8192]).enumerate() {
        let source_id = if index == 0 { 1 } else { 5 };
        let source = (source_id, blocks * 32 + 29);
        assert_eq!(cycle.setup, [Action::Allocate(source.0, source.1, true)]);
        assert_eq!(cycle.backing, [source]);
        let failing = failure && index == 1;
        assert_eq!(cycle.phases, if failing { 5 } else { 4 });
        let lengths = if index == 0 {
            vec![blocks * 36, blocks * 32, blocks * 32]
        } else {
            vec![blocks * 36]
        };
        assert_eq!(cycle.operations.len(), lengths.len() + usize::from(failing));
        if failing {
            let denied = &cycle.operations[0];
            assert_eq!(denied.before, [source]);
            assert_eq!(denied.after, [source]);
            assert_eq!(denied.actions, [Action::Allocate(6, blocks * 36, false)]);
        }
        let mut live = vec![source];
        let mut outputs = Vec::new();
        for (operation, length) in cycle
            .operations
            .iter()
            .skip(usize::from(failing))
            .zip(lengths)
        {
            assert_eq!(operation.before, live);
            let id = source_id + outputs.len() + 1 + usize::from(failing);
            assert_eq!(operation.actions, [Action::Allocate(id, length, true)]);
            outputs.push((id, length));
            live.push((id, length));
            assert_eq!(operation.after, live);
        }
        assert!(!cycle.publications.is_empty());
        for publication in &cycle.publications {
            assert_eq!(
                publication, &outputs,
                "every actual write follows source retirement with exactly the independent results live"
            );
        }
        let mut cleanup = vec![source];
        cleanup.extend_from_slice(&outputs);
        assert_eq!(cycle.cleanup, cleanup);
    }
    assert_eq!((observed.allocations, observed.releases), (6, 6));
}

#[test]
fn literal_matching_and_replacement_preserve_aliased_owners_and_recover_reached_allocation_failure()
{
    let started = Instant::now();
    let executable = executable("resources.lani");
    let compile = started.elapsed();
    let (output, baseline, native) = run(&executable, Some(0), None);
    assert_eq!(output, resource_expected());
    resource_observations(&baseline, false);
    let operation = &baseline.cycles[1].operations[0];
    let Action::Allocate(ordinal, size, true) = operation.actions[0] else {
        panic!("baseline must reach result reservation");
    };
    let (output, observed, recovery) = run(&executable, Some(1), Some(ordinal));
    assert_eq!(output, resource_expected());
    resource_observations(&observed, true);
    assert_eq!(observed.cycles[1].setup, baseline.cycles[1].setup);
    assert_eq!(observed.cycles[1].operations[0].before, operation.before);
    assert_eq!(
        observed.cycles[1].operations[0].actions,
        [Action::Allocate(ordinal, size, false)]
    );
    eprintln!(
        "literal-text resources source-bytes=4096,262144 full-output-bytes=307712 baseline+recovery=2 reached-denial={ordinal} old-views-preserved=true exact-maps-per-process=6 exact-releases-per-process=6 native-seconds={:.6} recovery-native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        recovery.as_secs_f64(),
        compile.as_secs_f64()
    );
}
