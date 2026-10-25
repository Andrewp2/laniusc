//! Typed borrowed consumers, exact effects, shallow owners and sequence models.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_consumers")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("iterator consumers {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_iterator_consumer", name, None);
    // Retain the existing strict ELF/native transfer checker.
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn typed_consumer_effects_nested_values_and_single_owner_cleanup_execute() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_iterator_consumer", "ownership_trace", None);
    let output = common::process_output_with_timeout(
        "typed iterator consumers",
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
    let mut live = BTreeMap::new();
    let mut allocations = Vec::new();
    let mut releases = Vec::new();
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim().to_owned();
            assert!(address.starts_with("0x"), "{events}");
            assert!(live.insert(address.clone(), length).is_none(), "{events}");
            allocations.push(address);
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            assert_eq!(
                live.remove(address.trim()),
                Some(length),
                "exact manual release: {events}"
            );
            releases.push(address.trim().to_owned());
        } else {
            panic!("unexpected consumer memory call: {events}");
        }
    }
    assert_eq!(
        allocations.len(),
        1,
        "only the independently retained String may allocate: {events}"
    );
    assert_eq!(
        releases, allocations,
        "one release after the last alias use: {events}"
    );
    assert!(live.is_empty(), "{events}");
}

fn folded(initial: u64, values: &[u64]) -> u64 {
    values
        .iter()
        .fold(initial, |acc, value| acc * 11 + value + 1)
}

#[derive(Default)]
struct Model {
    input: Vec<u8>,
    expected: Vec<u64>,
    cases: Vec<(usize, [u64; 5])>,
}
impl Model {
    fn add(&mut self, command: [u64; 5]) {
        self.input
            .extend(command.into_iter().flat_map(u64::to_le_bytes));
        let [op, length, target, polarity, initial] = command;
        let values: Vec<_> = (0..length).collect();
        let selected = |value: u64| (value == target) == (polarity == 1);
        // Derive the consumed prefix from a finite sequence, independently of
        // cursor fields and the production consumer loops.
        let decisive = match op {
            0 | 1 | 2 | 5 => values.iter().position(|value| selected(*value)),
            3 => values.iter().position(|value| !selected(*value)),
            4 => None,
            _ => panic!("unexpected operation"),
        };
        let consumed = decisive.map_or(values.len(), |index| index + 1);
        let eof = decisive.is_none();
        let primary_calls = consumed as u64 + u64::from(eof);
        let mut trace = Vec::new();
        let callback = match op {
            0..=3 => 2,
            4 => 3,
            5 => 4,
            _ => unreachable!(),
        };
        for _ in 0..consumed {
            trace.extend([1, callback]);
        }
        if eof {
            trace.push(1);
        }
        let result = match op {
            0 | 1 => decisive.map_or([0, 0, 0, 0], |index| {
                [
                    1,
                    if op == 0 {
                        values[index]
                    } else {
                        values[index] * 3 + 17
                    },
                    0,
                    0,
                ]
            }),
            2 => [2, u64::from(decisive.is_some()), 0, 0],
            3 => [2, u64::from(decisive.is_none()), 0, 0],
            4 => [3, folded(initial, &values), 0, 0],
            5 => decisive.map_or([4, folded(initial, &values), 0, 0], |index| {
                [
                    5,
                    values[index],
                    folded(initial, &values[..index]),
                    u64::MAX - values[index],
                ]
            }),
            _ => unreachable!(),
        };
        self.expected.extend(result);
        self.expected
            .extend([consumed as u64, primary_calls, consumed as u64]);

        let resumed = values.get(consumed).copied();
        self.expected
            .extend(resumed.map_or([0, 0], |value| [1, value]));
        let after_direct = consumed + usize::from(resumed.is_some());
        self.expected
            .extend([after_direct as u64, primary_calls + 1]);
        trace.push(1);
        let remainder = &values[after_direct..];
        self.expected.extend([
            folded(initial + 13, remainder),
            remainder.len() as u64,
            length,
            primary_calls + 1 + remainder.len() as u64 + 1,
        ]);
        for _ in remainder {
            trace.extend([1, 3]);
        }
        trace.push(1);
        self.expected.push(trace.len() as u64);
        self.expected.extend(trace);
        self.cases.push((self.expected.len(), command));
    }
}

#[test]
fn consumer_results_short_circuits_and_resumption_match_independent_models() {
    let mut model = Model::default();
    for op in [0, 1, 2, 3, 5] {
        for length in 0..=6 {
            for target in 0..=length + 1 {
                for polarity in [0, 1] {
                    for initial in [0, 7] {
                        model.add([op, length, target, polarity, initial]);
                    }
                }
            }
        }
    }
    for length in 0..=6 {
        for initial in [0, 7] {
            model.add([4, length, 0, 0, initial]);
        }
    }
    let input = common::TempArtifact::new("laniusc_iterator_consumer", "model_input", None);
    input.write_bytes(&model.input);
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "iterator consumer sequence models",
        Command::new(executable.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(10),
    );
    successful(&output);
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
            "consumer command {command:?}"
        );
        start = *end;
    }
    eprintln!(
        "{} independent consumer commands passed in one native execution",
        model.cases.len()
    );
}
