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

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/iterator_transfer/faults.lani");
    let stdlib = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("iterator transfer allocation failures", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("faults.lani: {error}"));
    let exe = common::TempArtifact::new("laniusc_iterator_transfer", "faults", None);
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

fn run(exe: &common::TempArtifact, deque: bool, when: Option<usize>) -> Ledger {
    let trace = common::TempArtifact::new("laniusc_iterator_transfer", "fault_trace", None);
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
    if deque {
        command.arg("deque");
    }
    let output = common::process_output_with_timeout(
        "iterator transfer growth denial",
        &mut command,
        Duration::from_secs(10),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "deque={deque}, when={when:?}: {output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        [u8::from(when.is_some())],
        "exactly the injected growth is rejected and recovered: {output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let result = ledger(&events);
    assert_eq!(
        result.denied,
        usize::from(when.is_some()),
        "injection must be reached exactly once: {events}"
    );
    result
}

#[test]
fn every_vec_and_deque_transfer_growth_failure_preserves_prefix_views_and_rejected_items() {
    let exe = executable();
    for deque in [false, true] {
        let baseline = run(&exe, deque, None);
        assert_eq!(baseline.attempts, baseline.successful);
        assert!(
            baseline.attempts >= 5,
            "exercise at least three destination growth allocations"
        );
        // Allocation 1 owns String bytes; allocation 2 reserves the initial
        // two-entry destination. All later mmap calls are observed growths.
        for when in 3..=baseline.attempts {
            let injected = run(&exe, deque, Some(when));
            assert_eq!(
                injected.successful, baseline.successful,
                "manual retry recovers the denied growth"
            );
            assert_eq!(injected.attempts, baseline.attempts + 1);
        }
        eprintln!(
            "deque={deque}: denied and recovered {} observed growth positions",
            baseline.attempts - 2
        );
    }
}
