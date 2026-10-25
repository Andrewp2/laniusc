#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/clone_deque");
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
    .unwrap_or_else(|error| panic!("{name}: {error:?}"));
    let exe = common::TempArtifact::new("clone_deque", name, None);
    // Preserve the strict common native ELF/transfer checker.
    exe.write_bytes(bytes);
    fs::set_permissions(exe.path(), fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("clone_deque", "mapping_trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = fail_at {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command.arg(exe.path());
    let output = common::process_output_with_timeout(
        "bounded recursive deque mapping trace",
        &mut command,
        Duration::from_secs(5),
    );
    (output, fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    attempts: Vec<usize>,
    failed: usize,
    messages: usize,
}

fn ledger(trace: &str, owned_messages: bool) -> Ledger {
    let mut live = BTreeMap::<String, usize>::new();
    let mut attempts = Vec::new();
    let mut failed = 0;
    let mut messages = 0;
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
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(live.remove(address.trim()), Some(size), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
            if owned_messages && size == 5 {
                messages += 1;
                assert!(
                    live.is_empty(),
                    "caller released E before source/partial/prefix owners: {trace}"
                );
            }
        } else {
            panic!("unexpected mapping trace event: {line}");
        }
    }
    assert!(live.is_empty(), "unreleased mapping owners: {trace}");
    Ledger {
        attempts,
        failed,
        messages,
    }
}

fn assert_native(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn nested_opt_ins_transfer_actual_owners_and_empty_zst_paths_allocate_nothing() {
    let contracts = executable("contracts.lani");
    let (output, trace) = traced(&contracts, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0, "{trace}");
    assert!(!actual.attempts.is_empty(), "String owners need storage");

    let empty = executable("empty_zero_sized.lani");
    let (output, trace) = traced(&empty, None);
    assert_native(&output, 0);
    // Empty Trap never calls a leaf; three ZST clones and six leaf releases
    // happen exactly once despite repeated cleanup on the reset destination.
    assert_eq!(output.stdout, b"cccdddddd", "{output:?}");
    assert!(
        ledger(&trace, false).attempts.is_empty(),
        "empty/ZST paths allocated: {trace}"
    );
}

#[derive(Default)]
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    cases: Vec<[u64; 4]>,
    ends: Vec<usize>,
}

impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }

    fn case(&mut self, record: [u64; 4]) {
        self.cases.push(record);
        for word in record {
            self.input.extend_from_slice(&word.to_le_bytes());
        }
        let [capacity, length, rotation, fail] = record;
        // Values are the retained interval after `rotation` front removals
        // and fresh back insertions, regardless of the ring representation.
        let logical = (rotation..rotation + length).collect::<Vec<_>>();
        let completed = if fail == u64::MAX { length } else { fail };
        let called = if fail == u64::MAX { length } else { fail + 1 };
        self.word(if fail == u64::MAX { 1 } else { 2 });
        self.word(if fail == u64::MAX { 0 } else { fail });
        self.word(if fail == u64::MAX { 0 } else { rotation + fail });
        self.word(if fail == u64::MAX { length } else { 0 });
        if fail == u64::MAX {
            for &tag in &logical {
                self.word(tag);
            }
        }
        self.word(called);
        for &tag in &logical[..called as usize] {
            self.word(tag);
        }
        self.word(completed);
        // Cleanup order is deliberately unspecified. The set and count of
        // completed owners must match, excluding source and rejected leaf.
        self.word(
            logical[..completed as usize]
                .iter()
                .fold(0, |mask, &tag| mask | (1 << tag)),
        );
        self.word(length);
        self.word(capacity);
        self.word(if length == 0 { 0 } else { rotation });
        for tag in logical {
            self.word(tag);
        }
        self.ends.push(self.expected.len());
    }
}

fn models() -> Models {
    let mut models = Models::default();
    for capacity in 0..=6 {
        for rotation in 0..capacity.max(1) {
            for length in 0..=capacity {
                models.case([capacity, length, rotation, u64::MAX]);
                for fail in 0..length {
                    models.case([capacity, length, rotation, fail]);
                }
            }
        }
    }
    models
}

#[test]
fn all_short_ring_heads_lengths_and_leaf_failures_match_logical_owner_model() {
    let models = models();
    let exe = executable("logical_model.lani");
    let input = common::TempArtifact::new("clone_deque", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "logical deque order and partial-prefix ownership model",
        Command::new(exe.path()).stdin(fs::File::open(input.path()).unwrap()),
        Duration::from_secs(10),
    );
    assert_native(&output, 0);
    if output.stdout != models.expected {
        let first = output
            .stdout
            .iter()
            .zip(&models.expected)
            .position(|(actual, expected)| actual != expected)
            .unwrap_or(output.stdout.len().min(models.expected.len()));
        let case = models.ends.partition_point(|end| *end <= first);
        panic!(
            "model case {case} {:?}, first different byte {first}; actual {} bytes, expected {}",
            models.cases.get(case),
            output.stdout.len(),
            models.expected.len()
        );
    }
    eprintln!("{} logical ring/ownership cases passed", models.cases.len());
}

fn numbers(output: &Output) -> Vec<usize> {
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse().unwrap())
        .collect()
}

#[test]
fn every_nested_allocation_failure_preserves_source_and_returns_exact_error_index() {
    let exe = executable("allocation_paths.lani");
    let (output, trace) = traced(&exe, None);
    assert_native(&output, 0);
    let widths = numbers(&output);
    assert_eq!(widths.len(), 3, "two runtime layouts and semantic tag");
    assert!(
        widths[..2]
            .iter()
            .all(|&size| size > 0 && size <= i32::MAX as usize / 3)
    );
    assert_eq!(widths[2], 0);
    let row = 2 * widths[0];
    let deque = 3 * widths[1];
    // Three source mappings; outer reserve precedes every row/leaf clone.
    // Record widths come from size_of in the actual native program.
    let expected = vec![4, row, deque, deque, row, 4, 4, row, 4, 4, row, 4, 4];
    let baseline = ledger(&trace, false);
    assert_eq!(baseline.attempts, expected, "{trace}");
    assert_eq!(baseline.failed, 0, "{trace}");
    assert!(!trace.contains("INJECTED"), "{trace}");
    let tags = [1, 2, 3, 10, 20, 100, 101, 21, 102, 103, 22, 104, 105];
    for index in 1..=expected.len() {
        let (output, trace) = traced(&exe, Some(index));
        assert_native(&output, 4);
        assert_eq!(
            numbers(&output),
            vec![widths[0], widths[1], tags[index - 1]],
            "wrong typed error nesting/index at mmap{index}"
        );
        let actual = ledger(&trace, false);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
    eprintln!("nested deque: all 13 reached allocation failures checked");
}

#[test]
fn generic_error_payload_keeps_its_owner_across_rollback_and_every_reached_oom() {
    let exe = executable("owned_errors.lani");
    let (output, trace) = traced(&exe, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let baseline = ledger(&trace, true);
    assert_eq!(baseline.failed, 0, "{trace}");
    assert_eq!(baseline.messages, 6, "all 3 indices x 2 stages: {trace}");
    let leaf_storage = baseline.attempts[1];
    assert!(leaf_storage > 5 && leaf_storage % 3 == 0, "{trace}");
    let mut expected = Vec::new();
    for index in 0..3 {
        for stage in 0..2 {
            // Original, source storage, destination reserve, completed leaves
            // plus optional failing partial, then the independent error String.
            expected.extend([4, leaf_storage, leaf_storage]);
            expected.extend(std::iter::repeat_n(4, index + stage));
            expected.push(5);
        }
    }
    assert_eq!(baseline.attempts, expected, "{trace}");
    assert_eq!(expected.len(), 33);
    for index in 1..=expected.len() {
        let (output, trace) = traced(&exe, Some(index));
        assert_native(&output, 4);
        assert!(output.stdout.is_empty(), "OOM{index}: {output:?}");
        let actual = ledger(&trace, true);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
    eprintln!("owned E: 6 index/stage cases and all 33 reached allocation failures checked");
}
