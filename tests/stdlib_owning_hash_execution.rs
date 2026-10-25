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
    let fixtures = root.join("tests/fixtures/stdlib_foundation/owning_hash");
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
    .unwrap_or_else(|error| panic!("owning hash {name}: {error:?}"));
    let file = common::TempArtifact::new("owning_hash", name, None);
    file.write_bytes(bytes); // Keeps the strict shared native executable checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn traced(exe: &common::TempArtifact, refuse_after_setup: bool) -> (Output, String) {
    let trace = common::TempArtifact::new("owning_hash", "mapping_trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if refuse_after_setup {
        // owners.lani completes exactly 15 mappings before cursor operations.
        command.args(["-e", "inject=mmap:error=ENOMEM:when=16+"]);
    }
    command.arg(exe.path());
    let output = common::process_output_with_timeout(
        "owning hash mapping trace",
        &mut command,
        Duration::from_secs(5),
    );
    (output, fs::read_to_string(trace.path()).unwrap())
}

fn ledger(trace: &str) -> Vec<usize> {
    let mut live = BTreeMap::<String, usize>::new();
    let mut attempts = Vec::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let size = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            assert!(address.starts_with("0x"), "unexpected allocation: {trace}");
            assert!(live.insert(address.to_owned(), size).is_none(), "{trace}");
            attempts.push(size);
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size = size.trim().parse().unwrap();
            assert_eq!(live.remove(address.trim()), Some(size), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
        } else {
            panic!("unexpected mapping event: {line}");
        }
    }
    assert!(live.is_empty(), "unreleased owners: {trace}");
    attempts
}

fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn direct_and_imported_iterators_recover_collision_chains_and_reuse_sources() {
    let file = executable("contracts.lani");
    let (output, trace) = traced(&file, false);
    checked(&output);
    assert!(output.stdout.is_empty());
    assert_eq!(
        ledger(&trace).len(),
        4,
        "only original and reused-source map/set tables allocate: {trace}"
    );
}

#[test]
fn independent_strings_transfer_rejected_owners_resume_and_cleanup_without_allocating() {
    let file = executable("owners.lani");
    let (output, trace) = traced(&file, false);
    checked(&output);
    assert!(output.stdout.is_empty());
    let baseline = ledger(&trace);
    assert_eq!(baseline.len(), 15, "three tables + twelve Strings: {trace}");
    let map_table = baseline[0];
    let set_table = baseline[7];
    assert!(map_table > 6 && set_table > 6);
    assert_eq!(
        baseline,
        vec![
            map_table, 4, 6, 4, 6, 4, 6, set_table, 4, 4, 4, set_table, 4, 4, 4
        ],
        "table layout remains private; requests distinguish real independent leaf owners"
    );
    let (output, trace) = traced(&file, true);
    checked(&output);
    assert!(output.stdout.is_empty());
    assert_eq!(ledger(&trace), baseline, "allocation after setup: {trace}");
    assert!(!trace.contains("INJECTED"), "cursor allocated: {trace}");
}

#[test]
fn no_key_traits_destroy_only_helpers_empty_reserved_and_zst_tables_execute() {
    let file = executable("empty_zero_sized.lani");
    let (output, trace) = traced(&file, false);
    checked(&output);
    assert_eq!(output.stdout, b"xxx", "three explicit ZST owner releases");
    assert_eq!(
        ledger(&trace).len(),
        4,
        "two reserved empty no-trait tables and two nonempty ZST tables: {trace}"
    );
}

type Values = BTreeMap<u64, (u64, u64)>;

#[derive(Debug)]
struct Case {
    record: [u64; 6],
    values: Values,
}

fn sequence(kind: u64, commands: &[u64]) -> Values {
    let mut values = Values::new();
    for (index, &op) in commands.iter().enumerate() {
        let id = op % 5;
        let value = (
            100 + index as u64,
            if kind == 0 {
                (-4_294_967_297_i64 - index as i64) as u64
            } else {
                0
            },
        );
        match op / 5 {
            0 if kind == 1 => {
                values.entry(id).or_insert(value);
            }
            0 | 1 => {
                values.insert(id, value);
            }
            2 => {
                values.remove(&id);
            }
            _ => panic!("unknown setup command"),
        }
    }
    values
}

fn add_cases(cases: &mut Vec<Case>, commands: &[u64]) {
    let packed = commands
        .iter()
        .enumerate()
        .fold(0, |packed, (index, op)| packed | (op << (4 * index)));
    for kind in 0..2 {
        let values = sequence(kind, commands);
        for pulls in 0..=values.len() as u64 + 1 {
            for inserted in [0, 4] {
                let variants = if pulls >= values.len() as u64 { 2 } else { 1 };
                for finish in 0..variants {
                    cases.push(Case {
                        record: [kind, packed, commands.len() as u64, pulls, inserted, finish],
                        values: values.clone(),
                    });
                }
            }
        }
    }
}

fn model_cases() -> Vec<Case> {
    let mut cases = Vec::new();
    let operations = [0, 1, 5, 6, 10, 11];
    for count in 0..=3 {
        for mut packed in 0..6usize.pow(count) {
            let mut commands = Vec::new();
            for _ in 0..count {
                commands.push(operations[packed % 6]);
                packed /= 6;
            }
            add_cases(&mut cases, &commands);
        }
    }
    // Three colliding keys expose a consumed slot inside a wrapped probe chain.
    // The full-occupied table with a prior deletion also permits recovery to
    // require a same-capacity tombstone rehash on subsequent insertion.
    add_cases(&mut cases, &[0, 1, 2]);
    add_cases(&mut cases, &[0, 1, 2, 3, 11]);
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

    fn entries(&mut self) -> Values {
        let count = self.word();
        assert!(count <= 5, "more entries than bounded key domain");
        let mut values = Values::new();
        for _ in 0..count {
            let id = self.word();
            let value = (self.word(), self.word());
            assert!(values.insert(id, value).is_none(), "key yielded twice");
        }
        values
    }

    fn item(&mut self) -> Option<(u64, (u64, u64))> {
        let present = self.word();
        let id = self.word();
        let value = (self.word(), self.word());
        match present {
            0 => {
                assert_eq!((id, value), (0, (0, 0)), "invalid empty payload");
                None
            }
            1 => Some((id, value)),
            _ => panic!("invalid Option tag"),
        }
    }
}

fn check_case(reply: &mut Reply<'_>, case: &Case) {
    let [kind, _, _, pulls, inserted, finish] = case.record;
    let capacity = reply.word();
    let occupied = reply.word();
    assert_eq!(reply.entries(), case.values, "setup representatives");
    assert!(occupied >= case.values.len() as u64 && occupied <= capacity);
    let mut remaining = case.values.clone();
    for _ in 0..pulls {
        if remaining.is_empty() {
            assert!(reply.item().is_none(), "exhausted cursor revived");
        } else {
            let (id, value) = reply.item().expect("cursor ended with live entries");
            assert_eq!(
                remaining.remove(&id),
                Some(value),
                "transferred owner identity"
            );
        }
        assert_eq!(reply.word(), remaining.len() as u64, "live count");
    }
    assert_eq!(
        reply.word(),
        remaining.len() as u64,
        "finish rejection count"
    );
    let finished = remaining.is_empty() && finish == 1;
    let recovered_capacity = if finished { 0 } else { capacity };
    assert_eq!(
        reply.word(),
        recovered_capacity,
        "capacity after finish attempt"
    );
    assert_eq!(
        reply.word(),
        recovered_capacity,
        "recovery retains capacity"
    );
    assert_eq!(
        reply.word(),
        if finished { 0 } else { occupied },
        "occupied retained"
    );
    assert_eq!(reply.entries(), remaining, "recovered owners");
    for id in 0..5 {
        assert_eq!(
            reply.item(),
            remaining.get(&id).map(|value| (id, *value)),
            "recovered probe chain for key{id}"
        );
    }
    let new_value = (
        999,
        if kind == 0 {
            (-9_223_372_036_854_775_807_i64) as u64
        } else {
            0
        },
    );
    let old = remaining.insert(inserted, new_value);
    assert_eq!(
        reply.item(),
        old.map(|value| (inserted, value)),
        "displaced owner"
    );
    let final_capacity = reply.word();
    let final_occupied = reply.word();
    assert!(final_capacity >= remaining.len() as u64);
    assert!(final_occupied >= remaining.len() as u64 && final_occupied <= final_capacity);
    assert_eq!(reply.entries(), remaining, "mutation after recovery");
    assert_eq!(
        reply.entries(),
        remaining,
        "each final owner transfers once"
    );
}

#[test]
fn bounded_map_and_set_sequences_match_unordered_value_and_lifecycle_models() {
    let cases = model_cases();
    let file = executable("model.lani");
    let input = common::TempArtifact::new("owning_hash", "model_input", None);
    input.write_bytes(
        cases
            .iter()
            .flat_map(|case| case.record.iter().flat_map(|word| word.to_le_bytes()))
            .collect::<Vec<_>>(),
    );
    let output = common::process_output_with_timeout(
        "owning map/set sequence and recovery model",
        Command::new(file.path()).stdin(fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    checked(&output);
    assert!(output.stdout.len().is_multiple_of(8));
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
            check_case(&mut reply, case)
        }));
        if let Err(error) = result {
            eprintln!("owning hash case {index}: {case:?}");
            std::panic::resume_unwind(error);
        }
    }
    assert_eq!(reply.next, words.len(), "unexpected trailing reply");
    eprintln!(
        "{} owning map/set sequence/lifecycle cases passed",
        cases.len()
    );
}
