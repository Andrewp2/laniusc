#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/clone_binary_heap");
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
    .unwrap_or_else(|error| panic!("heap deep clone {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_clone_binary_heap", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn native(output: &Output, expected: i32) {
    assert_eq!(output.status.code(), Some(expected), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn traced(executable: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_clone_binary_heap", "mapping_trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = fail_at {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command.arg(executable.path());
    let output = common::process_output_with_timeout(
        "heap cloning bounded mapping trace",
        &mut command,
        Duration::from_secs(5),
    );
    (output, std::fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    attempts: Vec<usize>,
    failures: usize,
    messages: usize,
}

fn ledger(trace: &str, owned_messages: bool) -> Ledger {
    let mut live = BTreeMap::<String, usize>::new();
    let mut attempts = Vec::new();
    let mut failures = 0;
    let mut messages = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let size = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            attempts.push(size);
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            if address.starts_with("0x") {
                assert!(live.insert(address.to_owned(), size).is_none(), "{trace}");
            } else {
                assert_eq!(address, "-1", "{trace}");
                assert!(line.contains("ENOMEM"), "{trace}");
                failures += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, tail) = tail.split_once(',').unwrap();
            let size = tail.split_once(')').unwrap().0.trim().parse().unwrap();
            assert_eq!(live.remove(address), Some(size), "{trace}");
            assert!(line.ends_with(" = 0"), "{trace}");
            if owned_messages && size == 5 {
                messages += 1;
                assert!(
                    live.is_empty(),
                    "owned error released before destination/source cleanup: {trace}"
                );
            }
        }
    }
    assert!(
        live.is_empty(),
        "leaked or multiply-owned heap storage: {trace}"
    );
    Ledger {
        attempts,
        failures,
        messages,
    }
}

#[test]
fn strings_nested_records_and_transferred_owners_remain_independent_in_both_orders() {
    let executable = executable("contracts.lani");
    let (output, trace) = traced(&executable, None);
    native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let allocations = ledger(&trace, false);
    assert_eq!(allocations.failures, 0);
    assert!(!allocations.attempts.is_empty());
}

#[test]
fn empty_and_zero_sized_heaps_allocate_nothing_and_destroy_without_ord_or_clone() {
    let executable = executable("empty_zero_sized.lani");
    let (output, trace) = traced(&executable, None);
    native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let allocations = ledger(&trace, false);
    assert!(
        allocations.attempts.is_empty(),
        "empty/ZST path allocated: {trace}"
    );
}

#[test]
fn every_reached_nested_allocation_reports_its_typed_source_storage_position() {
    let executable = executable("allocation_paths.lani");
    let (output, trace) = traced(&executable, None);
    native(&output, 0);
    let fields = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse::<usize>().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(fields.len(), 3, "{output:?}");
    assert!(
        fields[..2]
            .iter()
            .all(|&size| size > 0 && size <= i32::MAX as usize / 3)
    );
    assert_eq!(fields[2], 0);
    let row = 2 * fields[0];
    let heap = 3 * fields[1];
    let expected = vec![4, row, heap, heap, row, 4, 4, row, 4, 4, row, 4, 4];
    let baseline = ledger(&trace, false);
    assert_eq!(baseline.attempts, expected, "{trace}");
    assert_eq!(baseline.failures, 0);
    let tags: [usize; 13] = [1, 2, 3, 10, 20, 100, 101, 21, 102, 103, 22, 104, 105];
    for index in 1..=expected.len() {
        let (output, trace) = traced(&executable, Some(index));
        native(&output, 4);
        let actual = std::str::from_utf8(&output.stdout)
            .unwrap()
            .lines()
            .map(|line| line.parse::<usize>().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(actual.len(), 3, "OOM {index}: {output:?}");
        assert_eq!(actual[..2], fields[..2], "OOM {index}");
        assert_eq!(
            actual[2],
            tags[index - 1],
            "wrong typed failure at OOM {index}"
        );
        let allocations = ledger(&trace, false);
        assert_eq!(
            allocations.attempts,
            expected[..index],
            "OOM {index}: {trace}"
        );
        assert_eq!(allocations.failures, 1, "OOM {index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "{trace}");
    }
    eprintln!(
        "heap clone: all 13 reached nested allocation positions preserve source and balance owners"
    );
}

#[test]
fn owned_errors_survive_prefix_cleanup_at_every_physical_index_stage_and_allocation() {
    let executable = executable("owned_errors.lani");
    let (output, trace) = traced(&executable, None);
    native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let baseline = ledger(&trace, true);
    assert_eq!(
        baseline.messages, 16,
        "both orders, four storage positions, two leaf stages: {trace}"
    );
    assert_eq!(
        baseline.attempts.iter().filter(|&&size| size == 5).count(),
        16
    );
    assert_eq!(baseline.failures, 0);
    for index in 1..=baseline.attempts.len() {
        let (output, trace) = traced(&executable, Some(index));
        native(&output, 4);
        assert!(output.stdout.is_empty(), "OOM {index}: {output:?}");
        let allocations = ledger(&trace, true);
        assert_eq!(
            allocations.attempts,
            baseline.attempts[..index],
            "OOM {index}: {trace}"
        );
        assert_eq!(allocations.failures, 1, "OOM {index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "{trace}");
    }
    eprintln!(
        "heap clone: 16 owned-error paths and all {} reached allocations",
        baseline.attempts.len()
    );
}

#[test]
fn copied_record_priorities_and_duplicate_multiplicities_match_an_independent_model() {
    let executable = executable("model.lani");
    let output = common::short_process_output_with_timeout(
        "heap cloned priority/multiplicity model",
        &mut Command::new(executable.path()),
    );
    native(&output, 0);
    let rows = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_whitespace()
                .map(|part| part.parse::<i32>().unwrap())
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    assert_eq!(rows.len(), 192);
    for order in 0..2 {
        let actual = &rows[order * 96..(order + 1) * 96];
        assert!(
            actual
                .iter()
                .all(|row| row.len() == 3 && row[0] == order as i32)
        );
        let ids = actual.iter().map(|row| row[2]).collect::<BTreeSet<_>>();
        assert_eq!(ids, (0..96).collect::<BTreeSet<_>>());
        for row in actual {
            assert_eq!(
                row[1],
                (row[2] * 37 + 17) % 11 - 5,
                "copied record fields diverged: {row:?}"
            );
        }
        let mut expected = (0..96)
            .map(|id| (id * 37 + 17) % 11 - 5)
            .collect::<Vec<_>>();
        expected.sort_unstable();
        if order == 1 {
            expected.reverse();
        }
        assert_eq!(
            actual.iter().map(|row| row[1]).collect::<Vec<_>>(),
            expected
        );
    }
}
