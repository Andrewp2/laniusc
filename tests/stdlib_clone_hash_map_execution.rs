//! Explicit deep HashMap ownership, typed rollback and reached allocation faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/clone_hash_map");
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
    let bytes = compile(name).unwrap_or_else(|error| panic!("deep HashMap {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_clone_hash_map", name, None);
    file.write_bytes(bytes); // Includes the existing strict x86 jump checker.
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

struct Ledger {
    attempts: Vec<usize>,
    failed: usize,
    messages: usize,
}

fn ledger(trace: &str, messages: bool) -> Ledger {
    let mut live = BTreeMap::new();
    let mut attempts = Vec::new();
    let mut failed = 0;
    let mut released_messages = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let size: usize = line.split(',').nth(1).unwrap().trim().parse().unwrap();
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
                failed += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, tail) = tail.split_once(',').unwrap();
            let size: usize = tail.split_once(')').unwrap().0.trim().parse().unwrap();
            assert_eq!(live.remove(address), Some(size), "{trace}");
            assert!(line.ends_with(" = 0"), "{trace}");
            if messages && size == 5 {
                released_messages += 1;
                assert!(
                    live.is_empty(),
                    "owned error released before source/destination cleanup: {trace}"
                );
            }
        }
    }
    assert!(live.is_empty(), "unreleased owners: {trace}");
    Ledger {
        attempts,
        failed,
        messages: released_messages,
    }
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_clone_hash_map", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = fail_at {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command.arg(exe.path());
    let output =
        common::process_output_with_timeout("deep HashMap", &mut command, Duration::from_secs(5));
    let events = std::fs::read_to_string(trace.path()).unwrap();
    (output, events)
}

fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn string_keys_and_nested_values_clone_independently_through_imported_traits() {
    let file = executable("contracts.lani");
    let (output, events) = traced(&file, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let mappings = ledger(&events, false);
    assert_eq!(mappings.failed, 0);
    assert!(!mappings.attempts.is_empty());
}

#[test]
fn collisions_tombstones_owned_errors_and_changed_keys_preserve_exact_stages_and_cleanup() {
    let file = executable("owned_errors.lani");
    let (output, events) = traced(&file, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let mappings = ledger(&events, true);
    assert_eq!(mappings.failed, 0);
    // Three live-entry ordinals; two key stages and 2x2 value leaf/stage
    // combinations per ordinal. Eight changed-key cases have no message owner.
    assert_eq!(mappings.messages, 18, "{events}");
    assert_eq!(
        mappings.attempts.iter().filter(|&&size| size == 5).count(),
        18,
        "{events}"
    );
    eprintln!(
        "HashMap rollback: 18 owned Key/Value errors, 6 Eq/hash changes and 2 defensive duplicate/replacement cases"
    );
}

fn reported(output: &Output) -> Vec<usize> {
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse().unwrap())
        .collect()
}

#[test]
fn every_reached_allocation_reports_exact_outer_key_or_nested_value_error() {
    let file = executable("allocations.lani");
    let (output, events) = traced(&file, None);
    checked(&output, 0);
    let baseline = ledger(&events, false);
    let widths = reported(&output);
    assert_eq!(widths.len(), 3);
    assert!(widths[0] > 0 && widths[1] > 0);
    assert_eq!(widths[2], 0);
    assert_eq!(baseline.failed, 0);
    assert_eq!(baseline.attempts.len(), 14, "{events}");
    // The native slot representation stays private. Source/destination use
    // identical K/V types and eight buckets, so their table requests agree.
    let table_bytes = baseline.attempts[4];
    assert!(table_bytes >= 8 * (widths[0] + widths[1]));
    let expected = vec![
        4,
        4,
        7,
        2 * widths[0],
        table_bytes,
        table_bytes,
        4,
        2 * widths[0],
        7,
        7,
        4,
        2 * widths[0],
        7,
        7,
    ];
    assert_eq!(baseline.attempts, expected, "{events}");
    let tags = [1, 2, 3, 4, 5, 10, 100, 200, 300, 301, 101, 201, 302, 303];
    for index in 1..=expected.len() {
        let (output, events) = traced(&file, Some(index));
        checked(&output, 4);
        let actual = reported(&output);
        assert_eq!(actual.len(), 3, "OOM{index}: {output:?}");
        assert_eq!(&actual[..2], &widths[..2], "OOM{index}");
        assert_eq!(
            actual[2],
            tags[index - 1],
            "wrong typed error for allocation {index}"
        );
        let mappings = ledger(&events, false);
        assert_eq!(mappings.failed, 1, "OOM{index}: {events}");
        assert_eq!(mappings.attempts, expected[..index], "OOM{index}: {events}");
        assert_eq!(events.matches("INJECTED").count(), 1, "{events}");
    }
    eprintln!(
        "HashMap deep clone: all 14 reached allocation failures checked, including exact Key/Value/Element nesting"
    );
}

#[test]
fn empty_maps_skip_poison_leaves_and_nonempty_zero_sized_maps_own_tables() {
    let file = executable("empty_zero_sized.lani");
    let (output, events) = traced(&file, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let mappings = ledger(&events, false);
    assert_eq!(mappings.failed, 0);
    assert_eq!(
        mappings.attempts.len(),
        2,
        "only the source and cloned nonempty ZST tables allocate: {events}"
    );
    assert_eq!(mappings.attempts[0], mappings.attempts[1]);
}
