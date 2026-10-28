//! Bidirectional sequence models, callback order and explicit owner recovery.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, VecDeque},
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/reverse_iterators")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("reverse {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_reverse_iterator", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn success(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn trace(executable: &common::TempArtifact) -> (Output, String) {
    let events = common::TempArtifact::new("laniusc_reverse_iterator", "allocations", None);
    let output = common::process_output_with_timeout(
        "bidirectional allocation contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    success(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    (output, fs::read_to_string(events.path()).unwrap())
}

#[test]
fn compound_values_ranges_callbacks_and_empty_chain_transitions_execute_without_allocation() {
    for name in ["contracts.lani", "extra_contracts.lani"] {
        let executable = executable(name);
        let (_, events) = trace(&executable);
        assert!(
            events.is_empty(),
            "{name}: allocation-free adapters and callbacks: {events}"
        );
    }
}

#[test]
fn collection_reverse_cursors_transfer_and_recover_owners_without_hidden_clone_or_drop() {
    let executable = executable("collections.lani");
    let (_, events) = trace(&executable);
    let mut live = BTreeMap::<String, usize>::new();
    let mut allocations = 0;
    let mut releases = 0;
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim();
            assert!(
                address.starts_with("0x"),
                "successful source allocation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), size).is_none(),
                "one live owner: {events}"
            );
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let actual = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("one live mapping: {events}"));
            assert_eq!(actual, size.trim().parse::<usize>().unwrap(), "{events}");
            assert_eq!(result.trim(), "= 0", "{events}");
            releases += 1;
        } else {
            panic!("unexpected allocation service: {line}");
        }
    }
    assert_eq!(
        allocations, 7,
        "three Strings and four collection backings: {events}"
    );
    assert_eq!(
        releases, 7,
        "every explicit owner released exactly once: {events}"
    );
    assert!(live.is_empty(), "no retained allocation: {events}");
}

#[derive(Default)]
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    ends: Vec<usize>,
    commands: Vec<[u64; 6]>,
}
impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }

    fn case(&mut self, command: [u64; 6]) {
        for field in command {
            self.input.extend_from_slice(&field.to_le_bytes());
        }
        let [mode, length, right_length, pre, calls, schedule] = command;
        let mut left: VecDeque<i32> = (0..length as i32)
            .map(|value| if mode == 1 { value - 2 } else { value })
            .collect();
        let mut right: VecDeque<i32> = (10..10 + right_length as i32).collect();
        let mut events = Vec::<u64>::new();
        for _ in 0..pre {
            let value = left.pop_front().unwrap();
            if mode >= 2 {
                events.push((100 + value) as u64);
            }
        }
        // The reference stores the remaining sequence in VecDeque. It does
        // not recreate the production cursor fields or Chain state machine.
        let reversed = matches!(mode, 2 | 8 | 9 | 10);
        let chained = matches!(mode, 7 | 10);
        let filtered = matches!(mode, 5 | 6 | 9);
        let mapped = matches!(mode, 4 | 8);
        for call in 0..calls {
            let from_back = ((schedule >> call) & 1 != 0) ^ reversed;
            let output = loop {
                let queue = if chained {
                    if from_back {
                        if right.is_empty() {
                            &mut left
                        } else {
                            &mut right
                        }
                    } else if left.is_empty() {
                        &mut right
                    } else {
                        &mut left
                    }
                } else {
                    &mut left
                };
                let consumed = if from_back {
                    queue.pop_back()
                } else {
                    queue.pop_front()
                };
                let Some(value) = consumed else { break None };
                if mode >= 2 {
                    events.push((if from_back { 200 } else { 100 } + value) as u64);
                    if mapped {
                        events.push((300 + value) as u64);
                    }
                    if matches!(mode, 5 | 9) {
                        events.push((400 + value) as u64);
                    }
                    if mode == 6 {
                        events.push((500 + value) as u64);
                    }
                }
                if filtered && value % 2 != 0 {
                    continue;
                }
                break Some(if mapped {
                    value * 3 + 7
                } else if mode == 6 {
                    value * 2 + 1
                } else {
                    value
                });
            };
            self.word(u64::from(output.is_some()));
            self.word(output.map_or(0, |value| value as u64));
            self.word(left.len() as u64);
            self.word(right.len() as u64);
        }
        self.word(events.len() as u64);
        for event in events {
            self.word(event);
        }
        self.ends.push(self.expected.len());
        self.commands.push(command);
    }
}

#[test]
fn independent_remaining_sequence_models_cover_mixed_ends_partial_inputs_and_double_reverse() {
    let mut models = Models::default();
    for mode in 0..=10 {
        let max_left = if matches!(mode, 7 | 10) { 3 } else { 4 };
        let max_right = if matches!(mode, 7 | 10) { 3 } else { 0 };
        for left in 0..=max_left {
            for right in 0..=max_right {
                for pre in 0..=left {
                    // All five-pull front/back schedules, plus longer traces
                    // that cross both side boundaries and repeat joint EOF.
                    for schedule in 0..32 {
                        models.case([mode, left, right, pre, 5, schedule]);
                    }
                    for schedule in [0, 255, 0xaa, 0x55] {
                        models.case([mode, left, right, pre, 8, schedule]);
                    }
                }
            }
        }
    }
    let executable = executable("model.lani");
    let input = common::TempArtifact::new("laniusc_reverse_iterator", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "bidirectional independent sequence models",
        Command::new(executable.path()).stdin(fs::File::open(input.path()).unwrap()),
        Duration::from_secs(25),
    );
    success(&output);
    if output.stdout != models.expected {
        let difference = output
            .stdout
            .iter()
            .zip(&models.expected)
            .position(|(actual, expected)| actual != expected)
            .unwrap_or(output.stdout.len().min(models.expected.len()));
        let case = models.ends.partition_point(|end| *end <= difference);
        panic!(
            "case {case} {:?}, first differing byte {difference}; actual bytes {}, expected {}",
            models.commands.get(case),
            output.stdout.len(),
            models.expected.len(),
        );
    }
    eprintln!(
        "{} bidirectional sequence commands passed in one native process",
        models.commands.len()
    );
}

#[test]
fn reverse_requires_matching_forward_and_backward_item_traits() {
    for name in ["reject_forward_only.lani", "reject_wrong_back_item.lani"] {
        let error = compile(name).expect_err("rev needs both exact item traits");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("actual rejected rev call");
        assert!(label.path.ends_with(name), "{label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("core::iter::rev"),
            "{label:?}"
        );
    }
}
