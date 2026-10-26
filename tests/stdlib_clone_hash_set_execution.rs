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
    let fixtures = root.join("tests/fixtures/stdlib_foundation/clone_hash_set");
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
    .unwrap_or_else(|error| panic!("deep HashSet {name}: {error:?}"));
    let file = common::TempArtifact::new("clone_hash_set", name, None);
    file.write_bytes(bytes); // Retains the strict shared native transfer checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("clone_hash_set", "mapping_trace", None);
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
        "deep HashSet mapping trace",
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

fn ledger(trace: &str, messages: bool) -> Ledger {
    let mut live = BTreeMap::<String, usize>::new();
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
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(live.remove(address.trim()), Some(size), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
            if messages && size == 5 {
                released_messages += 1;
                assert!(
                    live.is_empty(),
                    "E released before source/partial/prefix owners: {trace}"
                );
            }
        } else {
            panic!("unexpected mapping event: {line}");
        }
    }
    assert!(live.is_empty(), "unreleased owners: {trace}");
    Ledger {
        attempts,
        failed,
        messages: released_messages,
    }
}

fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn imported_protocols_transfer_string_owners_and_handle_empty_and_zst_sets() {
    let file = executable("contracts.lani");
    let (output, trace) = traced(&file, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0);
    assert!(!actual.attempts.is_empty());

    let file = executable("empty_zero_sized.lani");
    let (output, trace) = traced(&file, None);
    checked(&output, 0);
    assert_eq!(output.stdout, b"cdd", "one ZST clone, two owners released");
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0);
    assert_eq!(
        actual.attempts.len(),
        2,
        "only source and destination nonempty ZST tables allocate: {trace}"
    );
    assert_eq!(actual.attempts[0], actual.attempts[1], "{trace}");
}

fn reported(output: &Output) -> usize {
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .trim()
        .parse()
        .unwrap()
}

fn allocation_paths(table: usize) -> (Vec<usize>, Vec<usize>) {
    let mut sizes = Vec::new();
    let mut tags = Vec::new();
    for wanted in 0..3 {
        for stage in 0..2 {
            sizes.extend([7, table, table]);
            tags.extend([1, 2, 10]);
            for index in 0..wanted {
                sizes.push(7);
                tags.push(100 + index);
            }
            if stage == 1 {
                sizes.push(7);
                tags.push(100 + wanted);
            }
            sizes.push(5);
            tags.push(100 + wanted);
        }
    }
    // Full successful clone reaches all three leaves without a typed rejection.
    sizes.extend([7, table, table, 7, 7, 7]);
    tags.extend([1, 2, 10, 100, 101, 102]);
    (sizes, tags)
}

#[test]
fn collisions_tombstones_generic_owned_errors_and_all_reached_allocations_rollback() {
    let file = executable("owned_errors.lani");
    let (output, trace) = traced(&file, None);
    checked(&output, 0);
    assert_eq!(reported(&output), 0);
    let baseline = ledger(&trace, true);
    assert_eq!(baseline.failed, 0);
    assert_eq!(baseline.messages, 6, "three live ordinals x two stages");
    // The private slot layout is not copied into the oracle. Source reserve4
    // and destination reserve3 use equal public capacities and the same T.
    let table = baseline.attempts[1];
    assert!(table > 7, "table must differ from leaf/error requests");
    let (expected, tags) = allocation_paths(table);
    assert_eq!(expected.len(), 39);
    assert_eq!(baseline.attempts, expected, "{trace}");
    assert!(!trace.contains("INJECTED"), "{trace}");
    for index in 1..=expected.len() {
        let (output, trace) = traced(&file, Some(index));
        checked(&output, 4);
        assert_eq!(reported(&output), tags[index - 1], "OOM{index}");
        let actual = ledger(&trace, true);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
    eprintln!("HashSet: 6 owned errors, a full clone, and all 39 reached OOM positions checked");
}

#[derive(Clone, Debug)]
struct Case {
    record: [u64; 4],
    values: BTreeMap<u64, u64>,
}

fn sequence(packed: u64, count: u64) -> BTreeMap<u64, u64> {
    let mut values = BTreeMap::new();
    for index in 0..count {
        let op = (packed >> (4 * index)) & 15;
        let id = op % 2;
        let representative = 100 + index;
        match op {
            0 | 1 => {
                values.entry(id).or_insert(representative);
            }
            2 | 3 => {
                values.insert(id, representative);
            }
            4 | 5 => {
                values.remove(&id);
            }
            _ => panic!("unknown set operation"),
        }
    }
    values
}

fn model_cases() -> Vec<Case> {
    let mut cases = Vec::new();
    for count in 0..=3u32 {
        for mut base6 in 0..6u64.pow(count) {
            let mut packed = 0;
            for index in 0..count {
                packed |= (base6 % 6) << (4 * index);
                base6 /= 6;
            }
            let values = sequence(packed, u64::from(count));
            cases.push(Case {
                record: [packed, u64::from(count), u64::MAX, 0],
                values: values.clone(),
            });
            for &target in values.keys() {
                cases.push(Case {
                    record: [packed, u64::from(count), target, 0],
                    values: values.clone(),
                });
            }
        }
    }
    let packed = (1 << 4) | (2 << 8); // insert0, insert1, replace0
    let values = sequence(packed, 3);
    for mode in [1, 2] {
        for target in 0..2 {
            cases.push(Case {
                record: [packed, 3, target, mode],
                values: values.clone(),
            });
        }
    }
    for mode in [3, 4] {
        cases.push(Case {
            record: [packed, 3, u64::MAX, mode],
            values: values.clone(),
        });
    }
    cases
}

struct Reply<'a> {
    words: &'a [u64],
    next: usize,
}

impl Reply<'_> {
    fn word(&mut self) -> u64 {
        let value = *self
            .words
            .get(self.next)
            .unwrap_or_else(|| panic!("truncated model reply at word {}", self.next));
        self.next += 1;
        value
    }

    fn entries(&mut self) -> Vec<(u64, u64)> {
        let count = self.word();
        assert!(count <= 2, "more owners than the two-key model permits");
        (0..count).map(|_| (self.word(), self.word())).collect()
    }
}

fn values(entries: &[(u64, u64)]) -> BTreeMap<u64, u64> {
    let result = entries.iter().copied().collect::<BTreeMap<_, _>>();
    assert_eq!(result.len(), entries.len(), "duplicate stored key");
    result
}

fn check_case(reply: &mut Reply<'_>, case: &Case) {
    let [_, _, target, mode] = case.record;
    let capacity = reply.word();
    let before = reply.entries();
    assert_eq!(values(&before), case.values, "source representatives");
    assert!(capacity >= before.len() as u64);
    // Public iteration supplies only the ordinal definition, never the value
    // model. Contents and representatives come from independent set commands.
    let stop = if mode >= 3 {
        Some(1)
    } else {
        before.iter().position(|(id, _)| *id == target)
    };
    let status = if stop.is_none() {
        1
    } else if mode == 0 {
        2
    } else {
        3
    };
    assert_eq!(reply.word(), status, "result class");
    assert_eq!(reply.word(), stop.unwrap_or(0) as u64, "live ordinal");
    let error_rep = if status == 2 {
        before[stop.unwrap()].1
    } else {
        0
    };
    assert_eq!(reply.word(), error_rep, "error payload representative");
    let copy = reply.entries();
    if status == 1 {
        assert_eq!(values(&copy), case.values, "deep clone representatives");
    } else {
        assert!(copy.is_empty(), "failed result returned owners");
    }
    let calls = reply.entries();
    let called = stop.map_or(before.len(), |index| index + 1);
    assert_eq!(
        calls,
        before[..called],
        "leaf calls follow live-entry order"
    );
    let completed = if status == 2 { stop.unwrap() } else { called };
    assert_eq!(reply.word(), completed as u64, "released owner count");
    let mask = before[..completed]
        .iter()
        .fold(0, |mask, (id, _)| mask | (1 << id));
    assert_eq!(reply.word(), mask, "released owner set");
    assert_eq!(reply.word(), capacity, "source capacity preserved");
    assert_eq!(reply.entries(), before, "source traversal preserved");
}

#[test]
fn bounded_sequences_preserve_representatives_and_changed_identity_releases_every_owner() {
    let cases = model_cases();
    let file = executable("model.lani");
    let input = common::TempArtifact::new("clone_hash_set", "model_input", None);
    let bytes = cases
        .iter()
        .flat_map(|case| case.record.iter().flat_map(|word| word.to_le_bytes()))
        .collect::<Vec<_>>();
    input.write_bytes(bytes);
    let output = common::process_output_with_timeout(
        "HashSet sequence/value/rollback model",
        Command::new(file.path()).stdin(fs::File::open(input.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&output, 0);
    assert!(output.stdout.len().is_multiple_of(8), "partial reply word");
    let words = output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect::<Vec<_>>();
    let mut reply = Reply {
        words: &words,
        next: 0,
    };
    for (index, case) in cases.iter().enumerate() {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            check_case(&mut reply, case);
        }));
        if let Err(error) = result {
            eprintln!("HashSet model case {index}: {case:?}");
            std::panic::resume_unwind(error);
        }
    }
    assert_eq!(reply.next, words.len(), "unexpected trailing reply");
    eprintln!(
        "{} HashSet sequence/failure/identity cases passed",
        cases.len()
    );
}
