//! Independent bounded-transfer models for real associative and heap sinks.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_collection_sinks")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("collection sinks {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_collection_sink", name, None);
    // Keep the shared strict ELF/native transfer checker.
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn memory_ledger(events: &str) -> (Vec<String>, Vec<String>, Vec<bool>) {
    let mut live = BTreeMap::new();
    let mut allocations = Vec::new();
    let mut releases = Vec::new();
    let mut order = Vec::new();
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim().to_owned();
            assert!(
                address.starts_with("0x"),
                "successful source allocation: {events}"
            );
            assert!(live.insert(address.clone(), length).is_none(), "{events}");
            allocations.push(address);
            order.push(true);
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            assert_eq!(
                live.remove(address.trim()),
                Some(length),
                "matching address and size: {events}"
            );
            releases.push(address.trim().to_owned());
            order.push(false);
        } else {
            panic!("unexpected collection memory call: {events}");
        }
    }
    assert!(
        live.is_empty(),
        "every collection owner must be released: {events}"
    );
    (allocations, releases, order)
}

#[test]
fn typed_collection_sinks_preserve_duplicate_payloads_and_owner_lifetimes() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_collection_sink", "contract_memory", None);
    let output = common::process_output_with_timeout(
        "typed collection sinks",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let (allocations, releases, order) = memory_ledger(&events);
    assert_eq!(
        allocations.len(),
        11,
        "six Strings and five collection owners only: {events}"
    );
    assert_eq!(releases.len(), 11, "{events}");
    let expected: Vec<_> = std::iter::repeat_n(true, 6)
        .chain((0..5).flat_map(|_| [true, false]))
        .chain(std::iter::repeat_n(false, 6))
        .collect();
    assert_eq!(
        order, expected,
        "duplicate acceptance must not allocate: {events}"
    );
    assert_eq!(
        &releases[5..],
        &allocations[..6],
        "external Strings are released last in creation order: {events}"
    );
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Item {
    group: u64,
    id: u64,
}

fn flag(id: u64) -> u64 {
    if id % 3 == 0 {
        0
    } else if id % 2 == 0 {
        2
    } else {
        1
    }
}
fn item(output: &mut Vec<u64>, value: Item, map: bool) {
    output.extend([
        value.group,
        value.id,
        u64::MAX - value.id,
        value.id * 17 + 3,
        flag(value.id),
    ]);
    if map {
        output.extend([
            u64::MAX - value.id,
            (1_u64 << 32) + value.id,
            flag(value.id),
        ]);
    }
}
fn group(pattern: u64, index: u64) -> u64 {
    match pattern {
        0 => index,
        1 => index % 3,
        2 => [2, 0, 2, 1, 0, 3][index as usize],
        _ => unreachable!(),
    }
}

struct State {
    kind: u64,
    source: VecDeque<Item>,
    original: Vec<Item>,
    calls: u64,
    unique: BTreeMap<u64, Item>,
    heap: Vec<Item>,
    saved: Vec<Item>,
}
impl State {
    fn new(kind: u64, length: u64, pattern: u64, mask: u64) -> Self {
        let original: Vec<_> = (0..length)
            .map(|index| Item {
                group: group(pattern, index),
                id: index + 1,
            })
            .collect();
        let prefix: Vec<_> = (0..6)
            .filter(|group| mask & (1 << group) != 0)
            .map(|group| Item {
                group,
                id: 100 + group,
            })
            .collect();
        Self {
            kind,
            source: original.iter().copied().collect(),
            original,
            calls: 0,
            unique: if kind < 4 {
                prefix.iter().map(|item| (item.group, *item)).collect()
            } else {
                BTreeMap::new()
            },
            heap: if kind >= 4 { prefix } else { Vec::new() },
            saved: Vec::new(),
        }
    }
    fn snapshot(&self, output: &mut Vec<u64>) {
        if self.kind < 4 {
            output.push(self.unique.len() as u64);
            for value in self.unique.values() {
                item(output, *value, self.kind < 2);
            }
        } else {
            let mut values = self.heap.clone();
            values.sort_by_key(|value| value.id);
            output.push(values.len() as u64);
            for value in values {
                item(output, value, false);
            }
        }
    }
    fn state(&self, output: &mut Vec<u64>) {
        output.extend([(self.original.len() - self.source.len()) as u64, self.calls]);
        self.snapshot(output);
        output.push(self.saved.len() as u64);
        for value in &self.saved {
            item(output, *value, self.kind < 2);
        }
    }
    fn transfer(&mut self, quota: u64, recover: bool, output: &mut Vec<u64>) {
        let window: Vec<_> = self
            .source
            .iter()
            .copied()
            .take(quota.min(self.source.len() as u64) as usize)
            .collect();
        // Logical equality is just group identity. Distinct source payloads
        // therefore expose both preexisting and newly introduced duplicates.
        let mut seen: BTreeSet<_> = self.unique.keys().copied().collect();
        let duplicate = if self.kind < 4 {
            window.iter().position(|item| !seen.insert(item.group))
        } else {
            None
        };
        let accepted = duplicate.unwrap_or(window.len());
        let consumed = accepted + usize::from(duplicate.is_some());
        let observed: Vec<_> = self.source.drain(..consumed).collect();
        self.calls += consumed as u64;
        for &value in &observed[..accepted] {
            if self.kind < 4 {
                assert_eq!(self.unique.insert(value.group, value), None);
            } else {
                self.heap.push(value);
            }
        }
        if let Some(index) = duplicate {
            let rejected = window[index];
            output.extend([1, accepted as u64]);
            item(output, rejected, self.kind < 2);
            self.snapshot(output);
            if recover {
                let old = self
                    .unique
                    .remove(&rejected.group)
                    .expect("duplicate retains an old representative");
                output.push(1);
                item(output, old, self.kind < 2);
                self.saved.push(old);
                assert_eq!(self.unique.insert(rejected.group, rejected), None);
            } else {
                output.push(0);
                self.saved.push(rejected);
            }
        } else {
            let exhausted = self.source.is_empty() && quota > accepted as u64;
            self.calls += u64::from(exhausted);
            output.extend([0, accepted as u64, u64::from(exhausted)]);
        }
        self.state(output);
    }
    fn finish(&self, output: &mut Vec<u64>, mask: u64) {
        let mut final_values: Vec<_> = self
            .unique
            .values()
            .copied()
            .chain(self.saved.iter().copied())
            .chain(self.heap.iter().copied())
            .collect();
        final_values.sort_by_key(|value| value.id);
        let mut original = self.original.clone();
        original.extend(
            (0..6)
                .filter(|group| mask & (1 << group) != 0)
                .map(|group| Item {
                    group,
                    id: 100 + group,
                }),
        );
        original.sort_by_key(|value| value.id);
        assert_eq!(
            final_values, original,
            "every representative remains in its owner or caller storage"
        );
        if self.kind >= 4 {
            output.push(self.heap.len() as u64);
            let mut groups: Vec<_> = self.heap.iter().map(|item| item.group).collect();
            groups.sort_unstable();
            if self.kind == 5 {
                groups.reverse();
            }
            output.extend(groups);
            let mut popped = self.heap.clone();
            popped.sort_by_key(|item| item.id);
            for value in popped {
                item(output, value, false);
            }
        }
        output.push(0);
    }
}

#[derive(Default)]
struct Model {
    input: Vec<u8>,
    expected: Vec<u64>,
    cases: Vec<(usize, [u64; 6])>,
}
impl Model {
    fn add(&mut self, command: [u64; 6]) {
        self.input
            .extend(command.into_iter().flat_map(u64::to_le_bytes));
        let [kind, length, pattern, mask, quota, recovery] = command;
        let mut state = State::new(kind, length, pattern, mask);
        for quota in [quota, 1, 1, 1, 1, 1, 1, u64::MAX, 0] {
            state.transfer(quota, recovery == 1, &mut self.expected);
        }
        assert!(state.source.is_empty());
        state.finish(&mut self.expected, mask);
        self.cases.push((self.expected.len(), command));
    }
}

#[test]
fn collection_sink_sequences_match_independent_duplicate_and_heap_models() {
    let mut model = Model::default();
    for kind in 0..=5 {
        for (length, pattern) in [(0, 0), (1, 0), (3, 0), (6, 0), (3, 1), (6, 1), (6, 2)] {
            for mask in [0, 5] {
                for quota in BTreeSet::from([0, 1, length, length + 1, u64::MAX]) {
                    for recovery in 0..if kind < 4 { 2 } else { 1 } {
                        model.add([kind, length, pattern, mask, quota, recovery]);
                    }
                }
            }
        }
    }
    let input = common::TempArtifact::new("laniusc_collection_sink", "model_input", None);
    input.write_bytes(&model.input);
    let executable = executable("model.lani");
    let trace = common::TempArtifact::new("laniusc_collection_sink", "model_memory", None);
    let output = common::process_output_with_timeout(
        "collection sink sequence models",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(15),
    );
    successful(&output);
    memory_ledger(&std::fs::read_to_string(trace.path()).unwrap());
    assert_eq!(output.stdout.len() % 8, 0, "complete response words");
    let actual: Vec<_> = output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect();
    assert_eq!(
        actual.len(),
        model.expected.len(),
        "complete model response"
    );
    let mut start = 0;
    for (end, command) in &model.cases {
        assert_eq!(
            &actual[start..*end],
            &model.expected[start..*end],
            "collection sink command {command:?}"
        );
        start = *end;
    }
    eprintln!(
        "{} independent collection sink commands, {} bounded transfers, passed in one native execution",
        model.cases.len(),
        model.cases.len() * 9
    );
}
