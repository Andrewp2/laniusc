//! Borrowed query lifetimes and manual owner transfer through collection search.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    process::Command,
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_borrowed_lookup/resources");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let started = Instant::now();
    let bytes = common::run_gpu_codegen_with_timeout("borrowed lookup resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("borrowed lookup resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("laniusc_borrowed_lookup_resources", name, None);
    artifact.write_bytes(bytes); // Shared writer validates x86 jumps before execution.
    fs::set_permissions(artifact.path(), fs::Permissions::from_mode(0o700)).unwrap();
    eprintln!(
        "borrowed-lookup resource={name} compile={:.6}s",
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
fn address(text: &str) -> u64 {
    u64::from_str_radix(text.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
type Owners = Vec<(usize, usize)>;
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Owners {
    let mut values = live.values().copied().collect::<Owners>();
    values.sort_unstable();
    values
}
#[derive(Debug, PartialEq, Eq)]
enum Action {
    Allocate(usize, usize),
    Release(usize, usize),
}
#[derive(Default, Debug)]
struct Operation {
    actions: Vec<Action>,
    callbacks: usize,
    live_at_return: Owners,
}
#[derive(Default, Debug)]
struct Cycle {
    sizes: BTreeMap<usize, usize>,
    operations: Vec<Operation>,
    pure: Vec<Owners>,
    cleanup: Vec<usize>,
    releases: usize,
    output: usize,
}
struct Layout {
    setup: Vec<Option<usize>>,
    published: Vec<usize>,
}
fn selected(cycle: &Cycle, ids: &[usize]) -> Owners {
    ids.iter().map(|id| (*id, cycle.sizes[id])).collect()
}
fn effects(events: &str, stderr: &[u8], layouts: &[Layout]) -> Vec<Cycle> {
    let mut completed = Vec::new();
    let mut current: Option<Cycle> = None;
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut operation: Option<Operation> = None;
    let mut pure: Option<Owners> = None;
    let (mut sealed, mut callback, mut cleanup) = (false, false, false);
    let (mut entries, mut exits) = (0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASCBbFPpRD"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(
                        current.is_none()
                            && live.is_empty()
                            && operation.is_none()
                            && pure.is_none()
                            && completed.len() < layouts.len(),
                        "{events}"
                    );
                    current = Some(Cycle::default());
                    sealed = false;
                    callback = false;
                    cleanup = false;
                }
                b'S' => {
                    assert!(
                        !sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    let cycle = current.as_ref().unwrap();
                    assert_eq!(
                        cycle.sizes.len(),
                        layouts[completed.len()].setup.len(),
                        "{events}"
                    );
                    assert_eq!(
                        owners(&live),
                        cycle
                            .sizes
                            .iter()
                            .map(|(&i, &n)| (i, n))
                            .collect::<Owners>(),
                        "{events}"
                    );
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
                    let op = operation.as_mut().unwrap();
                    assert_eq!(op.callbacks, 0, "one selected callback: {events}");
                    op.callbacks += 1;
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
                    let mut op = operation.take().unwrap();
                    assert_eq!(op.callbacks, 1, "{events}");
                    op.live_at_return = owners(&live);
                    current.as_mut().unwrap().operations.push(op);
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
                    current.as_mut().unwrap().pure.push(before);
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
                    let cycle = current.take().unwrap();
                    assert_eq!(
                        cycle.sizes.len(),
                        cycle.releases,
                        "observed retirement before exit: {events}"
                    );
                    completed.push(cycle);
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            pure.is_none(),
            "borrowed query phase performed a host effect: {line}"
        );
        if line.starts_with("execve(") {
            assert!(
                current.is_none() && completed.is_empty() && entries == 0,
                "{events}"
            );
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
            continue;
        }
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(
                current.is_none() && live.is_empty() && completed.len() == layouts.len(),
                "{events}"
            );
            exits += 1;
            continue;
        }
        let cycle = current
            .as_mut()
            .unwrap_or_else(|| panic!("effect outside explicit lifetime: {line}"));
        if line.starts_with("mmap(") {
            assert!(
                !cleanup && (!sealed || callback),
                "lookup allocation outside callback/setup: {events}"
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
            let ordinal = cycle.sizes.len() + 1;
            if !sealed {
                let expected = layouts[completed.len()]
                    .setup
                    .get(ordinal - 1)
                    .expect("only declared setup owners may allocate");
                if let Some(expected) = expected {
                    assert_eq!(
                        size, *expected,
                        "source-derived packed backing extent: {events}"
                    );
                }
                // None is an observed private table reservation, not an ABI
                // size claim. Its full address/extent must still match release.
            }
            let pointer = address(result(line));
            let end = pointer.checked_add(size as u64).unwrap();
            assert!(
                live.iter()
                    .all(|(&start, &(_, length))| end <= start || pointer >= start + length as u64),
                "overlapping live owners: {events}"
            );
            assert!(live.insert(pointer, (ordinal, size)).is_none(), "{events}");
            assert!(cycle.sizes.insert(ordinal, size).is_none());
            if let Some(op) = operation.as_mut() {
                op.actions.push(Action::Allocate(ordinal, size));
            } else {
                assert!(!sealed, "{events}");
            }
        } else if line.starts_with("munmap(") {
            assert!(
                sealed && (callback || cleanup),
                "lookup retired an owner: {events}"
            );
            let (pointer, size) = arguments(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (ordinal, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown or duplicate release: {line}\n{events}"));
            assert_eq!(
                size, actual,
                "full-width exact address/extent release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            cycle.releases += 1;
            if callback {
                operation
                    .as_mut()
                    .unwrap()
                    .actions
                    .push(Action::Release(ordinal, size));
            } else {
                cycle.cleanup.push(ordinal);
            }
        } else if line.starts_with("write(1,") {
            assert!(cleanup && !callback && operation.is_none(), "{events}");
            assert_eq!(
                owners(&live),
                selected(cycle, &layouts[completed.len()].published),
                "only independent results live at each publication: {events}"
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
            cycle.output += used;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        current.is_none() && live.is_empty() && pure.is_none() && operation.is_none(),
        "{events}"
    );
    assert_eq!(completed.len(), layouts.len(), "{events}");
    assert_eq!((entries, exits), (1, 1), "{events}");
    assert_eq!(stderr, markers);
    completed
}
fn run(executable: &common::TempArtifact, expected: &[u8], layouts: &[Layout]) -> Vec<Cycle> {
    let trace = common::TempArtifact::new("laniusc_borrowed_lookup_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"])
        .arg(executable.path());
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "borrowed lookup owner/scale",
        &mut command,
        Duration::from_secs(15),
    );
    let native = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(
        output.stdout, expected,
        "all published stored owners or scale values"
    );
    let observed = effects(&events, &output.stderr, layouts);
    assert_eq!(
        observed.iter().map(|cycle| cycle.output).sum::<usize>(),
        expected.len()
    );
    eprintln!(
        "borrowed-lookup cycles={} exact-maps={} exact-releases={} pure-phases={} full-output={} native={:.6}s",
        observed.len(),
        observed
            .iter()
            .map(|cycle| cycle.sizes.len())
            .sum::<usize>(),
        observed.iter().map(|cycle| cycle.releases).sum::<usize>(),
        observed.iter().map(|cycle| cycle.pure.len()).sum::<usize>(),
        expected.len(),
        native.as_secs_f64()
    );
    observed
}
fn owner_case(name: &str) {
    let executable = executable(name);
    let layout = Layout {
        setup: vec![Some(5), Some(3), Some(4), Some(5), Some(9), None, None],
        published: vec![1, 4, 8, 9],
    };
    let mut expected = b"bravo".to_vec();
    expected.extend([1, 2, 3, 42]);
    expected.extend(b"seed++bravo");
    let observed = run(&executable, &expected, &[layout]);
    let cycle = &observed[0];
    assert_eq!(cycle.sizes.len(), 9);
    assert_eq!(cycle.operations.len(), 1);
    assert_eq!(
        cycle.operations[0].actions,
        [
            Action::Allocate(8, 8),
            Action::Release(2, 3),
            Action::Allocate(9, 12),
            Action::Release(3, 4)
        ]
    );
    let after = selected(cycle, &[1, 4, 5, 6, 7, 8, 9]);
    assert_eq!(cycle.operations[0].live_at_return, after);
    assert_eq!(
        cycle.pure,
        [
            selected(cycle, &[1, 2, 3, 4, 5, 6, 7]),
            after.clone(),
            after,
            selected(cycle, &[1, 4, 8, 9])
        ]
    );
    assert_eq!(
        cycle.cleanup,
        [5, 6, 7, 1, 8, 9, 4],
        "query backing and tables retire before returned representatives"
    );
    eprintln!(
        "borrowed-lookup resource={name} observed-map-reservation={} observed-set-reservation={} callback-ordinary-error=true query-retired-before-results=true",
        cycle.sizes[&6], cycle.sizes[&7]
    );
}
#[test]
fn hash_borrowed_queries_preserve_and_transfer_real_string_and_value_owners() {
    owner_case("hash.lani");
}
#[test]
fn tree_borrowed_queries_preserve_and_transfer_real_string_and_value_owners() {
    owner_case("tree.lani");
}
#[test]
fn borrowed_point_queries_reuse_fixed_scratch_and_check_every_large_collection_value() {
    let executable = executable("scale.lani");
    let counts = [4096usize, 16384, 4096, 16384];
    let mut expected = Vec::new();
    for count in counts {
        for id in 0..count as u64 {
            expected.extend((4294967296u64 + id * 1000003 + 17).to_le_bytes());
            expected.extend((18446700000000000000u64 - id * 999983).to_le_bytes());
        }
    }
    let layouts = counts.map(|count| Layout {
        setup: vec![None, Some(12), Some(count * 16)],
        published: vec![3],
    });
    let observed = run(&executable, &expected, &layouts);
    for (cycle, count) in observed.iter().zip(counts) {
        assert_eq!(cycle.sizes.len(), 3);
        assert!(cycle.operations.is_empty());
        assert_eq!(
            cycle.pure,
            [selected(cycle, &[1, 2, 3]), selected(cycle, &[3])]
        );
        assert_eq!(cycle.cleanup, [2, 1, 3]);
        assert_eq!(cycle.output, count * 16);
        eprintln!(
            "borrowed-lookup scale-entries={count} observed-table-reservation={}",
            cycle.sizes[&1]
        );
    }
}
