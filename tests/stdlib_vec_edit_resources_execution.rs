//! Explicit nested cleanup, zero-byte logical effects, and bounded typed compaction.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_vec_edit_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("tests/fixtures/stdlib_vec_edit_resources")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("owned vector edit resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("owned vector edit {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_vec_edit_resources", name, None);
    output.write_bytes(bytes); // Shared writer admits the ELF and validates every x86 jump.
    fs::set_permissions(output.path(), fs::Permissions::from_mode(0o700)).unwrap();
    output
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
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Vec<(usize, usize)> {
    let mut result: Vec<_> = live.values().copied().collect();
    result.sort_unstable();
    result
}
#[derive(Default, Debug)]
struct Phase {
    before: Vec<(usize, usize)>,
    after: Vec<(usize, usize)>,
    released: Vec<usize>,
    callbacks: Vec<u8>,
}
#[derive(Default, Debug)]
struct Cycle {
    setup: Vec<(usize, usize)>,
    phases: Vec<Phase>,
    cleanup: Vec<usize>,
    publications: Vec<(usize, bool, Vec<(usize, usize)>)>,
}
#[derive(Default, Debug)]
struct Effects {
    cycles: Vec<Cycle>,
    allocations: usize,
    releases: usize,
    published: usize,
}

fn effects(events: &str, stderr: &[u8]) -> Effects {
    let mut observed = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut cycle: Option<Cycle> = None;
    let mut phase: Option<Phase> = None;
    let (mut sealed, mut cleanup, mut done) = (false, false, false);
    let (mut entries, mut exits) = (0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASPpCEDdqrs"
                .iter()
                .find(|&&byte| line.contains(&format!("\"{}\", 1)", char::from(byte))))
                .unwrap_or_else(|| panic!("unknown marker {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(cycle.is_none() && phase.is_none() && live.is_empty());
                    cycle = Some(Cycle::default());
                    sealed = false;
                    cleanup = false;
                }
                b'S' => {
                    assert!(cycle.is_some() && !sealed && !cleanup && phase.is_none());
                    sealed = true;
                }
                b'P' => {
                    assert!(cycle.is_some() && sealed && !cleanup && phase.is_none());
                    phase = Some(Phase {
                        before: owners(&live),
                        ..Phase::default()
                    });
                }
                b'p' => {
                    let mut finished = phase.take().unwrap();
                    finished.after = owners(&live);
                    cycle.as_mut().unwrap().phases.push(finished);
                }
                b'd' | b'q' | b'r' | b's' => {
                    phase
                        .as_mut()
                        .expect("instrumentation only inside edit")
                        .callbacks
                        .push(marker);
                }
                b'C' => {
                    assert!(sealed && !cleanup && phase.is_none());
                    cleanup = true;
                }
                b'E' => {
                    assert!(
                        sealed && cleanup && phase.is_none() && live.is_empty(),
                        "retire every owner explicitly: {events}"
                    );
                    observed.cycles.push(cycle.take().unwrap());
                    sealed = false;
                    cleanup = false;
                }
                b'D' => {
                    assert!(cycle.is_none() && phase.is_none() && live.is_empty());
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        if line.starts_with("execve(") {
            assert!(cycle.is_none() && !done && entries == 0 && live.is_empty());
            assert_eq!(result(line), "0");
            entries += 1;
        } else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty());
            exits += 1;
        } else if line.starts_with("mmap(") {
            assert!(
                cycle.is_some() && !sealed && !cleanup && phase.is_none(),
                "editing must not allocate: {line}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
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
            let pointer = address(result(line));
            let end = pointer.checked_add(size as u64).unwrap();
            assert!(
                live.iter()
                    .all(|(&start, &(_, length))| end <= start || pointer >= start + length as u64),
                "overlapping live allocation: {line}"
            );
            observed.allocations += 1;
            let owner = (observed.allocations, size);
            assert!(live.insert(pointer, owner).is_none());
            cycle.as_mut().unwrap().setup.push(owner);
        } else if line.starts_with("munmap(") {
            assert!(
                sealed && (phase.is_some() || cleanup),
                "release must belong to an edit or final cleanup: {line}"
            );
            let (pointer, extent) = arguments(line).split_once(',').unwrap();
            let extent: usize = extent.trim().parse().unwrap();
            let (ordinal, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown/already destroyed owner: {line}"));
            assert_eq!(extent, actual, "exact full-width live owner extent: {line}");
            assert_eq!(result(line), "0");
            observed.releases += 1;
            if let Some(phase) = phase.as_mut() {
                phase.released.push(ordinal);
            } else {
                cycle.as_mut().unwrap().cleanup.push(ordinal);
            }
        } else if line.starts_with("write(1,") {
            assert!(
                sealed && phase.is_none() && !done,
                "publication outside callbacks/edit: {line}"
            );
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let written: usize = result(line).parse().unwrap();
            assert!(written > 0 && written <= requested);
            observed.published += written;
            let current = cycle.as_mut().unwrap();
            current
                .publications
                .push((current.phases.len(), cleanup, owners(&live)));
        } else {
            panic!("unexpected host effect: {line}");
        }
    }
    assert!(done && live.is_empty() && phase.is_none() && cycle.is_none());
    assert_eq!((entries, exits), (1, 1));
    assert_eq!(observed.allocations, observed.releases);
    assert_eq!(markers, stderr);
    observed
}
fn run(executable: &common::TempArtifact) -> (Vec<u8>, Effects, Duration) {
    let trace = common::TempArtifact::new("laniusc_vec_edit_resources", "trace", None);
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "owned vector edit resource lifecycle",
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(15),
    );
    let native = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    let observed = effects(&events, &output.stderr);
    assert_eq!(observed.published, output.stdout.len());
    (output.stdout, observed, native)
}
fn word(output: &mut Vec<u8>, value: i32) {
    output.extend(value.to_le_bytes());
}
fn nested_state(output: &mut Vec<u8>, stage: i32, ids: &[usize]) {
    word(output, stage);
    word(output, ids.len() as i32);
    for &id in ids {
        word(output, id as i32);
        output.extend((id as i64 * 1_000_003 + 17).to_le_bytes());
        output.extend((0..8).map(|i| ((id * 29 + i * 17 + 3) % 256) as u8));
        output.extend((0..12).map(|i| (65 + (id * 7 + i * 3) % 26) as u8));
    }
}
fn survivors(initial: &[(usize, usize)], released: &[usize]) -> Vec<(usize, usize)> {
    initial
        .iter()
        .copied()
        .filter(|(id, _)| !released.contains(id))
        .collect()
}

#[test]
fn vector_owned_edits_destroy_nested_owners_once_and_reuse_original_backing() {
    let started = Instant::now();
    let executable = executable("nested.lani");
    let compile = started.elapsed();
    let (actual, observed, native) = run(&executable);
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    // Entry = three scalar fields + Vec(3 words) + String(3 words) + reference.
    // Native records reserve eight bytes per word; this is not C i32 packing.
    let mut sizes = vec![257 * 10 * 8, 9 * 10 * 8];
    for _ in 0..30 {
        sizes.extend([8, 12]);
    }
    assert_eq!(
        cycle.setup,
        sizes
            .iter()
            .enumerate()
            .map(|(i, &size)| (i + 1, size))
            .collect::<Vec<_>>()
    );
    let mut tape = Vec::<i32>::new();
    let original: Vec<_> = (0..24).collect();
    let mut retained = Vec::new();
    let mut removed = Vec::new();
    for id in 0..24 {
        tape.push(1000 + id as i32);
        if id % 3 != 0 {
            retained.push(id);
        } else {
            tape.push(-1 - id as i32);
            removed.push(id);
        }
    }
    let mut phases = vec![removed];
    let mut dedup = Vec::new();
    let mut rejected = Vec::new();
    for &id in &retained {
        if let Some(&last) = dedup.last() {
            tape.push(10000 + last as i32 * 100 + id as i32);
            if last / 4 == id / 4 {
                tape.push(-1 - id as i32);
                rejected.push(id);
                continue;
            }
        }
        dedup.push(id);
    }
    phases.push(rejected);
    let short = dedup[..3].to_vec();
    for ids in [
        dedup[3..].iter().rev().copied().collect::<Vec<_>>(),
        short.iter().rev().copied().collect(),
    ] {
        for &id in &ids {
            tape.push(-1 - id as i32);
        }
        phases.push(ids);
    }
    phases.push(vec![]);
    let refill: Vec<_> = (24..30).collect();
    let mut second = Vec::<usize>::new();
    let mut rejected = Vec::new();
    for &id in &refill {
        if let Some(&last) = second.last() {
            tape.push(10000 + last as i32 * 100 + id as i32);
            if last / 4 == id / 4 {
                tape.push(-1 - id as i32);
                rejected.push(id);
                continue;
            }
        }
        second.push(id);
    }
    phases.push(rejected);
    let final_drops: Vec<_> = second.iter().rev().copied().collect();
    for &id in &final_drops {
        tape.push(-1 - id as i32);
    }
    phases.push(final_drops);
    let mut expected = Vec::new();
    for (stage, ids) in [
        &original,
        &retained,
        &dedup,
        &short,
        &vec![],
        &refill,
        &second,
        &vec![],
    ]
    .into_iter()
    .enumerate()
    {
        nested_state(&mut expected, stage as i32, ids);
    }
    word(&mut expected, tape.len() as i32);
    for value in tape {
        word(&mut expected, value);
    }
    assert_eq!(actual, expected);
    assert_eq!(cycle.phases.len(), phases.len());
    let mut all_released = Vec::new();
    let mut snapshots = vec![cycle.setup.clone()];
    for (phase, ids) in cycle.phases.iter().zip(phases) {
        assert!(phase.callbacks.is_empty());
        assert_eq!(phase.before, survivors(&cycle.setup, &all_released));
        let releases: Vec<_> = ids.iter().flat_map(|id| [3 + id * 2, 4 + id * 2]).collect();
        assert_eq!(phase.released, releases);
        all_released.extend(releases);
        assert_eq!(phase.after, survivors(&cycle.setup, &all_released));
        snapshots.push(phase.after.clone());
    }
    assert_eq!(cycle.phases.last().unwrap().after, cycle.setup[..2]);
    assert_eq!(cycle.cleanup, [1, 2]);
    for (stage, cleanup, live) in &cycle.publications {
        if *cleanup {
            assert!(live.is_empty());
        } else {
            assert_eq!(live, &snapshots[*stage]);
        }
    }
    assert_eq!((observed.allocations, observed.releases), (62, 62));
    eprintln!(
        "vec-edit nested entries=30 inner-owners=60 retained-capacity=257 phases=7 exact-maps=62 exact-releases=62 full-output-bytes={} native-seconds={:.6} compile-seconds={:.6}",
        actual.len(),
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

#[test]
fn vector_owned_edits_zero_sized_values_have_logical_counts_and_no_allocations() {
    let started = Instant::now();
    let executable = executable("zero_sized.lani");
    let compile = started.elapsed();
    let (actual, observed, native) = run(&executable);
    let mut expected = Vec::new();
    for value in [17, 11, i32::MAX] {
        word(&mut expected, value);
    }
    assert_eq!(actual, expected);
    assert_eq!(observed.cycles.len(), 1);
    let cycle = &observed.cycles[0];
    assert!(cycle.setup.is_empty() && cycle.cleanup.is_empty());
    let retain: Vec<_> = (1..=17)
        .flat_map(|i| {
            if i % 3 == 0 {
                vec![b'r', b'd']
            } else {
                vec![b'r']
            }
        })
        .collect();
    let dedup: Vec<_> = (1..=11)
        .flat_map(|i| {
            if i % 2 != 0 {
                vec![b's', b'd']
            } else {
                vec![b's']
            }
        })
        .collect();
    let equal: Vec<_> = (0..8).flat_map(|_| [b'q', b'd']).chain([b'd']).collect();
    let tapes = [retain, dedup, vec![b'd'; 4], vec![b'd'; 2], equal, vec![]];
    assert_eq!(cycle.phases.len(), tapes.len());
    for (phase, tape) in cycle.phases.iter().zip(tapes) {
        assert_eq!(phase.callbacks, tape);
        assert!(phase.before.is_empty() && phase.after.is_empty() && phase.released.is_empty());
    }
    assert!(
        cycle
            .publications
            .iter()
            .all(|(_, _, live)| live.is_empty())
    );
    assert_eq!((observed.allocations, observed.releases), (0, 0));
    eprintln!(
        "vec-edit ZST predicate-calls=17 stateful-comparisons=11 equality-comparisons=8 destructor-calls=26 max-count-noop={} phases=6 maps=0 native-seconds={:.6} compile-seconds={:.6}",
        i32::MAX,
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

fn scale_state(output: &mut Vec<u8>, count: i32, stage: i32, ids: &[i32]) {
    word(output, count);
    word(output, stage);
    word(output, ids.len() as i32);
    for &id in ids {
        word(output, id);
        word(output, id / 8);
        output.extend((i64::from(id) * 1_000_003 + 17).to_le_bytes());
    }
}
#[test]
fn vector_owned_edits_large_multiword_compaction_preserves_every_survivor_without_growth() {
    let started = Instant::now();
    let executable = executable("scale.lani");
    let compile = started.elapsed();
    let (actual, observed, native) = run(&executable);
    assert_eq!(observed.cycles.len(), 2);
    let mut expected = Vec::new();
    let mut total_values = 0;
    for (index, count) in [4096, 65536].into_iter().enumerate() {
        let retained: Vec<i32> = (0..count).filter(|id| id % 3 != 0).collect();
        let dedup: Vec<i32> = (0..count / 8)
            .map(|group| {
                let start = group * 8;
                if start % 3 == 0 { start + 1 } else { start }
            })
            .collect();
        let short = dedup[..(count / 16) as usize].to_vec();
        let refill: Vec<i32> = (count..count + 3).collect();
        for (stage, ids) in [&retained, &dedup, &short, &vec![], &refill, &vec![]]
            .into_iter()
            .enumerate()
        {
            scale_state(&mut expected, count, stage as i32 + 1, ids);
            total_values += ids.len();
        }
        for value in [count, retained.len() as i32 - 1, count + 3] {
            word(&mut expected, value);
        }
        let cycle = &observed.cycles[index];
        let backing = vec![(index + 1, (count as usize * 4 + 17) * 4 * 8)];
        assert_eq!(cycle.setup, backing);
        assert_eq!(cycle.phases.len(), 6);
        for phase in &cycle.phases {
            assert_eq!(phase.before, backing);
            assert_eq!(phase.after, backing);
            assert!(phase.released.is_empty() && phase.callbacks.is_empty());
        }
        for (_, cleanup, live) in &cycle.publications {
            assert!(!cleanup);
            assert_eq!(live, &backing);
        }
        assert_eq!(cycle.cleanup, [index + 1]);
    }
    assert_eq!(actual, expected);
    assert_eq!((observed.allocations, observed.releases), (2, 2));
    eprintln!(
        "vec-edit scale sizes=4096,65536 full-record-observations={total_values} full-output-bytes={} phases=12 exact-maps=2 exact-releases=2 native-seconds={:.6} compile-seconds={:.6}",
        actual.len(),
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}
