//! Canonical owning TreeMap/TreeSet cursor transfer, recovery and release.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/owning_tree");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("owning tree {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let exe = common::TempArtifact::new("owning_tree", name, None);
    exe.write_bytes(bytes); // Keep the unchanged strict common ELF checker.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn traced(exe: &common::TempArtifact, seconds: u64) -> (Output, String) {
    let trace = common::TempArtifact::new("owning_tree", "memory_trace", None);
    let mut command = Command::new("timeout");
    command
        .args([
            "--kill-after=1s",
            &format!("{seconds}s"),
            "strace",
            "-qq",
            "-o",
        ])
        .arg(trace.path())
        .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
        .arg(exe.path());
    let output = common::process_output_with_timeout(
        "bounded owning-tree trace",
        &mut command,
        Duration::from_secs(seconds + 2),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    (output, std::fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    attempts: Vec<usize>,
    events: Vec<(bool, usize)>,
    empty_releases: Vec<usize>,
}
fn ledger(trace: &str) -> Ledger {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut attempts = Vec::new();
    let mut events = Vec::new();
    let mut empty_releases = Vec::new();
    for line in trace.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim().to_owned();
            assert!(address.starts_with("0x"), "{trace}");
            attempts.push(length);
            let identity = attempts.len();
            assert!(
                live.insert(address, (length, identity)).is_none(),
                "{trace}"
            );
            events.push((true, identity));
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            assert_eq!(result.trim(), "= 0", "{trace}");
            let (size, identity) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("unowned release: {trace}"));
            assert_eq!(size, length.trim().parse::<usize>().unwrap(), "{trace}");
            events.push((false, identity));
            if live.is_empty() {
                empty_releases.push(identity);
            }
        } else {
            panic!("unexpected allocator operation: {line}\n{trace}");
        }
    }
    assert!(live.is_empty(), "unreleased owners: {trace}");
    Ledger {
        attempts,
        events,
        empty_releases,
    }
}

#[test]
fn mixed_direction_recovery_reuse_representatives_and_minimal_bounds() {
    let exe = executable("contracts.lani");
    let (output, trace) = traced(&exe, 5);
    assert!(output.stdout.is_empty(), "{output:?}");
    // Map/set source reserve + separate source reuse, two NoOrder reserves,
    // and two ZST structural reserves. Cursor steps/recovery never allocate.
    assert_eq!(ledger(&trace).attempts.len(), 8, "{trace}");
}

#[test]
fn independent_string_owners_survive_remaining_cleanup_without_finish_projection() {
    for (name, count, grows) in [("strings.lani", 18, 2), ("helper_only_strings.lani", 11, 0)] {
        let exe = executable(name);
        let (output, trace) = traced(&exe, 5);
        assert!(output.stdout.is_empty(), "{name}: {output:?}");
        let actual = ledger(&trace);
        assert_eq!(actual.attempts.len(), count, "{name}: {trace}");
        assert_eq!(
            actual.attempts.iter().filter(|&&bytes| bytes == 8).count(),
            grows,
            "{name}: {trace}"
        );
    }
}

#[test]
fn rejected_sink_transfer_preserves_rejected_owner_and_exact_resume() {
    let exe = executable("transfer.lani");
    let (output, trace) = traced(&exe, 5);
    assert!(output.stdout.is_empty());
    let actual = ledger(&trace);
    assert_eq!(actual.attempts.len(), 12, "{trace}");
    // Each pre-reserved phase has six allocations, then six releases without
    // any allocating cursor/sink step. Rejected input (#3/#9) is released last.
    assert_eq!(actual.empty_releases, [3, 9], "{trace}");
    assert_eq!(actual.events.len(), 24);
    for phase in actual.events.chunks_exact(12) {
        assert!(phase[..6].iter().all(|event| event.0), "{trace}");
        assert!(phase[6..].iter().all(|event| !event.0), "{trace}");
    }
}

fn map_item(output: &mut Vec<u64>, item: Option<(i32, (i32, u64))>) {
    output.push(u64::from(item.is_some()));
    if let Some((key, (stamp, value))) = item {
        output.extend([key as u64, stamp as u64, value]);
    }
}
fn set_item(output: &mut Vec<u64>, item: Option<(i32, i32)>) {
    output.push(u64::from(item.is_some()));
    if let Some((key, stamp)) = item {
        output.extend([key as u64, stamp as u64]);
    }
}

#[test]
fn ordered_state_model_recovers_valid_balanced_trees_without_allocating_steps() {
    let exe = executable("model.lani");
    let (output, trace) = traced(&exe, 10);
    let actual = ledger(&trace);
    assert_eq!(
        actual.attempts.len(),
        2,
        "only initial map/set reservations: {trace}"
    );
    assert!(
        actual
            .attempts
            .iter()
            .all(|&size| size > 0 && size % 512 == 0)
    );
    let mut map: BTreeMap<i32, (i32, u64)> = (0..256)
        .filter(|key| key % 4 != 1)
        .map(|key| (key, (100 + key, 10000 + key as u64 * 17)))
        .collect();
    let mut set: BTreeMap<i32, i32> = map.iter().map(|(&key, &(stamp, _))| (key, stamp)).collect();
    let mut expected = Vec::<u64>::new();
    let mut state = 113;
    for step in 0..192 {
        state = (state * 73 + 41) % 997;
        match step % 6 {
            0 => {
                map_item(&mut expected, map.pop_first());
                set_item(&mut expected, set.pop_first());
            }
            1 => {
                map_item(&mut expected, map.pop_last());
                set_item(&mut expected, set.pop_last());
            }
            2 => {
                assert!(!map.is_empty() && !set.is_empty());
                expected.extend([map.len() as u64, set.len() as u64]);
            }
            3 => {
                let key = 256 + state % 128;
                map.insert(key, (1000 + step, 20000 + step as u64));
                set.insert(key, 1000 + step);
            }
            4 => {
                let key = state % 384;
                map_item(&mut expected, map.remove_entry(&key));
                set_item(&mut expected, set.remove_entry(&key));
            }
            _ => {
                expected.push(map.len() as u64);
                for (&key, &(stamp, value)) in &map {
                    expected.extend([key as u64, stamp as u64, value]);
                }
                expected.push(set.len() as u64);
                for (&key, &stamp) in &set {
                    expected.extend([key as u64, stamp as u64]);
                }
            }
        }
        expected.extend([map.len() as u64, 512, set.len() as u64, 512]);
    }
    loop {
        let next = map.pop_first();
        let key = set.pop_first();
        let done = next.is_none();
        map_item(&mut expected, next);
        set_item(&mut expected, key);
        if done {
            assert!(set.is_empty());
            break;
        }
    }
    let reported = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse::<u64>().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(
        reported, expected,
        "192 owning-tree operations and full ordered recovery snapshots"
    );
}
