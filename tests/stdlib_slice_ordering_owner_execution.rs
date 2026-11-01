//! Finite compound-owner and comparison-growth gates for slice ordering.
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

fn executable(fixture: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/slice_ordering/{fixture}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("slice ordering ownership/counts", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("slice ordering {fixture}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_slice_ordering", "executable", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

// Observe only the actual raw executable's mapping/release calls and explicit
// phase markers. This is a finite fixture ledger, not a resource-type checker.
fn mappings(
    events: &str,
    expected_mappings: usize,
    expected_phases: usize,
    owner_backing_last: bool,
) {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut allocated = 0;
    let mut released = Vec::new();
    let mut pure = false;
    let mut phases = 0;
    let mut finished = false;
    for line in events.lines() {
        if line.starts_with("write(2, ") {
            assert!(line.ends_with(" = 1"), "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !finished, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !finished, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(line.contains("\"D\", 1)"), "{events}");
                assert!(
                    !pure && !finished && live.is_empty(),
                    "explicit cleanup before D: {events}"
                );
                finished = true;
            }
            continue;
        }
        assert!(
            !pure,
            "algorithms/comparators must neither allocate nor release: {line}"
        );
        assert!(!finished, "no effects after cleanup checkpoint: {events}");
        if line.starts_with("write(1, ") {
            assert!(line.ends_with(", 24) = 24"), "count report: {events}");
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once(" = ").unwrap().1.trim();
            let address = result.split_whitespace().next().unwrap();
            assert!(
                address.starts_with("0x"),
                "unexpected failed allocation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), (allocated, size)).is_none(),
                "duplicate live mapping: {events}"
            );
            allocated += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (identity, actual_size) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(size, actual_size, "exact matching owner extent: {events}");
            assert_eq!(result.trim(), "= 0", "{events}");
            released.push(identity);
        } else {
            panic!("unexpected allocation service or output: {line}");
        }
    }
    assert!(finished && !pure && live.is_empty(), "{events}");
    assert_eq!(phases, expected_phases, "{events}");
    assert_eq!(allocated, expected_mappings, "{events}");
    assert_eq!(released.len(), expected_mappings, "{events}");
    if owner_backing_last {
        assert_eq!(
            released.last(),
            Some(&0),
            "all nested Strings retire before owner backing: {events}"
        );
    }
}

fn run(fixture: &str, expected_phases: usize, expected_mappings: usize) -> Vec<u8> {
    let executable = executable(fixture);
    let trace = common::TempArtifact::new("laniusc_slice_ordering", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,mremap,munmap,brk,write",
            "-e",
            "signal=none",
        ])
        .arg(executable.path());
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "slice ordering owned/count lifecycle",
        &mut command,
        Duration::from_secs(30),
    );
    let elapsed = started.elapsed();
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let mut markers = b"Pp".repeat(expected_phases);
    markers.push(b'D');
    assert_eq!(output.stderr, markers, "{output:?}");
    let events = fs::read_to_string(trace.path()).unwrap();
    mappings(
        &events,
        expected_mappings,
        expected_phases,
        fixture == "owners",
    );
    eprintln!(
        "slice-ordering fixture={fixture} native_whole_lifecycle_ms={}",
        elapsed.as_millis()
    );
    output.stdout
}

#[test]
fn nested_string_records_keep_one_owner_after_custom_sort_partition_and_heterogeneous_search() {
    assert!(run("owners", 7, 29).is_empty());
}

#[test]
fn compound_record_scale_has_bounded_comparisons_searches_and_legacy_ord_calls() {
    let bytes = run("scale", 5, 2);
    assert_eq!(bytes.len(), 24);
    let report: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|part| u32::from_le_bytes(part.try_into().unwrap()))
        .collect();
    let [n, custom, sortedness, partition, legacy, query_max]: [u32; 6] =
        report.try_into().unwrap();
    assert_eq!(n, 32768);
    assert!(custom > 0 && custom <= 8 * n * (n.ilog2() + 1));
    assert!(sortedness > 0 && sortedness <= n);
    assert!(partition > 0 && partition <= n);
    let legacy_len = n + 2;
    let legacy_ceil_log2 = u32::BITS - (legacy_len - 1).leading_zeros();
    assert!(legacy > 0 && legacy <= 8 * legacy_len * (legacy_ceil_log2 + 1));
    assert!(query_max > 0 && query_max <= 2 * (n.ilog2() + 2));
    eprintln!(
        "slice-ordering records={n} custom_compares={custom} sortedness_compares={sortedness} partition_compares={partition} legacy_lt_calls={legacy} max_query_compares={query_max}"
    );
}
