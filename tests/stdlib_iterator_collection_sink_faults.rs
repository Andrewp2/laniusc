//! Deny every observed destination growth and audit explicit allocation owners.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_collection_sink_faults")
        .join(format!("{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}.lani: {error}"));
    let exe = common::TempArtifact::new("laniusc_iterator_collection_sink", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

struct Ledger {
    attempts: usize,
    denied: usize,
    successful: usize,
}

fn ledger(events: &str) -> Ledger {
    let mut live = BTreeMap::new();
    let mut allocated = Vec::new();
    let mut released = Vec::new();
    let mut attempts = 0;
    let mut denied = 0;
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            attempts += 1;
            let size: usize = args.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once(" = ").unwrap().1;
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(
                    live.insert(address.clone(), size).is_none(),
                    "duplicate active owner: {events}"
                );
                allocated.push(address);
            } else {
                assert!(
                    result.starts_with("-1 ENOMEM") && line.contains("INJECTED"),
                    "unexpected allocation failure: {events}"
                );
                denied += 1;
            }
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (fields, result) = args.split_once(')').unwrap();
            let (address, size) = fields.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size),
                "release matches one active address/size: {events}"
            );
            assert_eq!(result.trim(), "= 0", "release succeeds: {events}");
            released.push(address.trim().to_owned());
        } else {
            panic!("unexpected memory event: {events}");
        }
    }
    assert!(
        live.is_empty(),
        "every successful owner is released: {events}"
    );
    assert_eq!(
        allocated.len(),
        released.len(),
        "one release per allocation: {events}"
    );
    assert_eq!(
        released.last(),
        allocated.first(),
        "external String owner outlives all sink storage: {events}"
    );
    Ledger {
        attempts,
        denied,
        successful: allocated.len(),
    }
}

fn run(exe: &common::TempArtifact, duplicate: bool, when: Option<usize>) -> Ledger {
    let trace = common::TempArtifact::new("laniusc_iterator_collection_sink", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,mremap,brk"]);
    if let Some(index) = when {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={index}"));
    }
    command.arg(exe.path());
    if duplicate {
        command.arg("duplicate");
    }
    let output = common::process_output_with_timeout(
        "collection sink growth/duplicate fault",
        &mut command,
        Duration::from_secs(10),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "duplicate={duplicate}, when={when:?}: {output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    let reached = when.is_some() && !duplicate;
    assert_eq!(
        output.stdout,
        [if duplicate { 2 } else { u8::from(reached) }],
        "fixture confirms the intended rejection and cleanup: {output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let observed = ledger(&events);
    assert_eq!(observed.denied, usize::from(reached), "growth injection is reached exactly once; duplicate injection remains armed and unreached: {events}");
    observed
}

fn check(name: &str, duplicates: bool) {
    let exe = executable(name);
    let baseline = run(&exe, false, None);
    assert_eq!(baseline.attempts, baseline.successful);
    assert!(
        baseline.attempts >= 4,
        "exercise multiple observed growth allocations"
    );
    // Allocation 1 owns String bytes; allocation 2 reserves initial collection
    // capacity. All later mmap attempts belong to destination growth.
    for when in 3..=baseline.attempts {
        let injected = run(&exe, false, Some(when));
        assert_eq!(
            injected.successful, baseline.successful,
            "manual retry recovers exactly the denied growth"
        );
        assert_eq!(injected.attempts, baseline.attempts + 1);
    }
    if duplicates {
        for when in [None, Some(3)] {
            let duplicate = run(&exe, true, when);
            assert_eq!(
                duplicate.attempts, 2,
                "a full-capacity duplicate performs no allocation"
            );
            assert_eq!(duplicate.successful, 2);
        }
    }
    eprintln!("{name}: recovered {} observed growth positions; full-capacity duplicate checked={duplicates}", baseline.attempts - 2);
}

#[test]
fn hash_map_transfer_growth_and_full_duplicate_preserve_original_entries() {
    check("hash_map", true);
}
#[test]
fn hash_set_transfer_growth_and_full_duplicate_preserve_original_representatives() {
    check("hash_set", true);
}
#[test]
fn tree_map_transfer_growth_and_full_duplicate_preserve_original_entries() {
    check("tree_map", true);
}
#[test]
fn tree_set_transfer_growth_and_full_duplicate_preserve_original_representatives() {
    check("tree_set", true);
}
#[test]
fn heap_transfer_growth_preserves_contents_priority_and_rejected_items() {
    check("binary_heap", false);
}
