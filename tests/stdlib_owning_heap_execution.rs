//! Owning heap priority, recovery, cleanup authority and exact mapping lifetimes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/owning_heap");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("owning heap {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let file = common::TempArtifact::new("owning_heap", name, None);
    file.write_bytes(bytes); // Preserve the shared strict native ELF checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn traced(exe: &common::TempArtifact, deny_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("owning_heap", "mapping_trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "4s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"]);
    if let Some(index) = deny_at {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command.arg(exe.path());
    let output = common::process_output_with_timeout(
        "bounded owning heap trace",
        &mut command,
        Duration::from_secs(6),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    (output, fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    requests: Vec<usize>,
    releases: Vec<usize>,
    events: Vec<(bool, usize)>,
}

fn ledger(trace: &str) -> Ledger {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut requests = Vec::new();
    let mut releases = Vec::new();
    let mut events = Vec::new();
    for line in trace.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            requests.push(size);
            let id = requests.len();
            let address = line.rsplit_once(" = ").unwrap().1.trim();
            assert!(
                address.starts_with("0x"),
                "unexpected allocation/fault: {trace}"
            );
            assert!(
                live.insert(address.to_owned(), (size, id)).is_none(),
                "{trace}"
            );
            events.push((true, id));
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (allocated, id) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("release must name one live owner: {trace}"));
            assert_eq!(allocated, size, "release exact mapping length: {trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
            releases.push(id);
            events.push((false, id));
        } else {
            panic!("unexpected cursor memory operation: {line}");
        }
    }
    assert!(
        live.is_empty(),
        "all mappings released exactly once: {trace}"
    );
    Ledger {
        requests,
        releases,
        events,
    }
}

fn payload(words: &[u64], expected_id: u64, seed: u64) -> i64 {
    assert_eq!(words.len(), 6);
    assert_eq!(words[0], expected_id);
    let priority = ((expected_id * 7 + seed * 3) % 5) as i64 - 2;
    assert_eq!(words[1] as i64, priority);
    assert_eq!(words[2], u64::MAX - expected_id);
    assert_eq!(words[3] as i64, -4_294_967_297 - expected_id as i64);
    assert_eq!(words[4], 8_589_934_593 + expected_id);
    assert_eq!(
        words[5],
        if expected_id % 3 == 0 {
            0
        } else if expected_id % 2 == 0 {
            2
        } else {
            1
        }
    );
    priority
}

fn pop_oracle(words: &[u64], pending: &mut BTreeSet<u64>, seed: u64, max: bool) {
    let id = words[0];
    let priority = payload(words, id, seed);
    assert!(
        pending.contains(&id),
        "one representative per transfer: {id}"
    );
    let expected = pending
        .iter()
        .map(|&other| ((other * 7 + seed * 3) % 5) as i64 - 2);
    let highest = if max { expected.max() } else { expected.min() }.unwrap();
    assert_eq!(
        priority, highest,
        "canonical priority, ties deliberately unordered"
    );
    assert!(pending.remove(&id));
}

#[test]
fn bounded_priority_multisets_preserve_ties_and_recover_for_reinsertion() {
    let exe = executable("model.lani");
    let (output, trace) = traced(&exe, None);
    assert_eq!(output.stdout.len() % 8, 0);
    let words: Vec<_> = output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect();
    let width = words[0] as usize;
    assert!(width > 0);
    let mut position = 1;
    let mut requests = Vec::new();
    let mut events = Vec::new();
    let mut cases = 0;
    let mut items = 0;
    for mode in 0..2_u64 {
        for seed in 0..4_u64 {
            for length in 0..18_u64 {
                let prefix = match seed {
                    0 => 0,
                    1 => length / 2,
                    2 => length,
                    _ => u64::from(length != 0),
                };
                assert_eq!(
                    &words[position..position + 4],
                    &[mode, seed, length, prefix]
                );
                position += 4;
                let mut pending: BTreeSet<_> = (0..length).collect();
                for _ in 0..prefix {
                    pop_oracle(
                        &words[position..position + 6],
                        &mut pending,
                        seed,
                        mode == 1,
                    );
                    position += 6;
                    items += 1;
                }
                assert!(pending.insert(length));
                while !pending.is_empty() {
                    pop_oracle(
                        &words[position..position + 6],
                        &mut pending,
                        seed,
                        mode == 1,
                    );
                    position += 6;
                    items += 1;
                }
                requests.extend([width * (length as usize + 3), width]);
                let id = cases * 2 + 1;
                // Only original setup and independent source reuse allocate;
                // recovery/reinsert/pulls/finish add no mapping operation.
                events.extend([(true, id), (true, id + 1), (false, id + 1), (false, id)]);
                cases += 1;
            }
        }
    }
    assert_eq!((cases, items, position), (144, 1368, words.len()));
    let actual = ledger(&trace);
    assert_eq!(actual.requests, requests, "{trace}");
    assert_eq!(
        actual.events, events,
        "no hidden cursor allocation: {trace}"
    );
}

#[test]
fn string_owners_transfer_once_through_recovery_rejection_and_resume() {
    let exe = executable("owners.lani");
    let (output, trace) = traced(&exe, None);
    let width: usize = std::str::from_utf8(&output.stdout)
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    assert!(width > 0);
    let actual = ledger(&trace);
    let mut expected = vec![width * 5];
    expected.extend([4; 5]);
    expected.extend([width, 4, width * 4]);
    expected.extend([4; 4]);
    expected.push(width * 4);
    assert_eq!(
        actual.requests, expected,
        "only ten String owners and four backings: {trace}"
    );
    assert_eq!(
        &actual.releases[..4],
        &[8, 7, 3, 5],
        "reused source and yielded owners: {trace}"
    );
    assert_eq!(
        actual.releases[4..7]
            .iter()
            .copied()
            .collect::<BTreeSet<_>>(),
        [2, 4, 6].into_iter().collect(),
        "remaining owners released without a priority-order promise: {trace}"
    );
    assert_eq!(
        &actual.releases[7..],
        &[1, 12, 9, 10, 11, 13, 14],
        "rejected owner, source backing, accepted owners, sink backing: {trace}"
    );
    let mut expected_events: Vec<_> = (1..=8).map(|id| (true, id)).collect();
    expected_events.extend(actual.releases[..8].iter().map(|&id| (false, id)));
    expected_events.extend((9..=14).map(|id| (true, id)));
    expected_events.extend(actual.releases[8..].iter().map(|&id| (false, id)));
    assert_eq!(
        actual.events, expected_events,
        "cursor steps never allocate: {trace}"
    );
}

#[test]
fn no_ord_lifecycle_destroy_only_cleanup_reserved_empty_and_zero_size_execute() {
    let exe = executable("lifecycle.lani");
    for deny_at in [None, Some(8)] {
        let (output, trace) = traced(&exe, deny_at);
        let newline = output
            .stdout
            .iter()
            .position(|&byte| byte == b'\n')
            .unwrap();
        let width: usize = std::str::from_utf8(&output.stdout[..newline])
            .unwrap()
            .parse()
            .unwrap();
        assert!(width > 0);
        assert_eq!(
            &output.stdout[newline + 1..],
            b"ZZZZZZZZZ",
            "every logical ZST released once"
        );
        let actual = ledger(&trace);
        assert_eq!(
            actual.requests,
            [24, 40, width * 2, width * 3, 4, 4, 4],
            "{trace}"
        );
        assert_eq!(
            actual.releases,
            [1, 2, 3, 7, 6, 5, 4],
            "Destroy-only owners precede their backing: {trace}"
        );
        assert_eq!(
            actual.events,
            [
                (true, 1),
                (false, 1),
                (true, 2),
                (false, 2),
                (true, 3),
                (false, 3),
                (true, 4),
                (true, 5),
                (true, 6),
                (true, 7),
                (false, 7),
                (false, 6),
                (false, 5),
                (false, 4)
            ],
            "the armed eighth mmap remains unreachable: {trace}"
        );
    }
}

#[test]
fn priority_pull_and_deep_cleanup_require_the_actual_ord_and_destroy_bounds() {
    for (name, call) in [
        (
            "missing_ord.lani",
            "pull<alloc::binary_heap::IntoIter<Item>>",
        ),
        (
            "missing_destroy.lani",
            "alloc::clone_binary_heap::destroy_binary_heap_iter<Item>",
        ),
        (
            "wrong_destroy_item.lani",
            "alloc::clone_binary_heap::destroy_binary_heap_iter<Item>",
        ),
    ] {
        let error = match compile(name) {
            Err(error) => error,
            Ok(bytes) => panic!(
                "{name}: incompatible bound produced {} ELF bytes",
                bytes.len()
            ),
        };
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("actual source call rejection");
        assert!(label.path.ends_with(name), "{label:?}");
        assert!(
            label.source_line.as_deref().unwrap_or("").contains(call),
            "{label:?}"
        );
    }
}
