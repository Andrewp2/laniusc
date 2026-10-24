//! Owning cursor lifecycle and true nested-owner allocation failures.
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
        .join("tests/fixtures/stdlib_foundation/owning_iterator_faults")
        .join(format!("{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}.lani: {error}"));
    let exe = common::TempArtifact::new("laniusc_owning_iterator", name, None);
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
    Ledger {
        attempts,
        denied,
        successful: allocated.len(),
    }
}

fn run(
    exe: &common::TempArtifact,
    reuse: bool,
    when: Option<usize>,
    expected: &[u8],
    denied: usize,
) -> Ledger {
    let trace = common::TempArtifact::new("laniusc_owning_iterator", "trace", None);
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
    if reuse {
        command.arg("reuse");
    }
    let output = common::process_output_with_timeout(
        "owning cursor allocation ownership",
        &mut command,
        Duration::from_secs(10),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "reuse={reuse}, when={when:?}: {output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout, expected,
        "fixture completed its intended ownership path: {output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let result = ledger(&events);
    assert_eq!(
        result.denied, denied,
        "exact reached or deliberately unreached injection: {events}"
    );
    result
}

#[test]
fn owning_cursor_mixed_ends_finish_restore_and_destroy_do_not_allocate_after_setup() {
    let exe = executable("lifecycle");
    for when in [None, Some(15)] {
        let result = run(&exe, false, when, &[], 0);
        assert_eq!(
            result.attempts, 14,
            "only two initial collection buffers and twelve unique String owners"
        );
        assert_eq!(result.successful, 14);
    }
}

#[test]
fn zero_sized_owning_cursors_destroy_logical_items_and_never_allocate() {
    let exe = executable("zero_sized");
    for when in [None, Some(1)] {
        let result = run(&exe, false, when, &[90; 9], 0);
        assert_eq!(
            result.attempts, 0,
            "including MAX reserve, empty recovery and finish"
        );
        assert_eq!(result.successful, 0);
    }
}

fn growth(name: &str) {
    let exe = executable(name);
    let baseline = run(&exe, false, None, &[0], 0);
    // Source buffer + seventeen individually owned Strings + initial sink.
    // Capacities are captured from each actual owner inside the fixture.
    assert!(
        baseline.attempts > 19,
        "workload must reach destination growth"
    );
    assert_eq!(baseline.successful, baseline.attempts);
    for when in 20..=baseline.attempts {
        let failed = run(&exe, false, Some(when), &[1], 1);
        assert_eq!(
            failed.successful, baseline.successful,
            "returned String retried before resuming"
        );
        assert_eq!(failed.attempts, baseline.attempts + 1);
    }
    let reused = run(&exe, true, None, &[0], 0);
    assert_eq!(
        reused.attempts, 19,
        "eighteen original owners and one independent source reuse reserve"
    );
    let failed_reuse = run(&exe, true, Some(19), &[1], 1);
    assert_eq!(failed_reuse.attempts, 19);
    assert_eq!(
        failed_reuse.successful, 18,
        "failed source reuse preserves the owning cursor and its eighteen owners"
    );
    eprintln!("{name}: recovered {} observed destination growth positions and one independent original-source reuse failure", baseline.attempts - 19);
}

#[test]
fn owning_vec_strings_recover_each_destination_growth_and_original_source_reuse_failure() {
    growth("vec_growth");
}

#[test]
fn owning_deque_strings_recover_each_destination_growth_and_original_source_reuse_failure() {
    growth("deque_growth");
}
