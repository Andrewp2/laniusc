// Selection payload/owner contracts and shared-source copy/callback models.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    cell::RefCell,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    rc::Rc,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_selection")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_iterator_selection", name, None);
    exe.write_bytes(bytes); // Unchanged common strict x86 jump validation.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn selection_preserves_typed_payloads_stride_context_and_shallow_owners() {
    let exe = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_iterator_selection", "owner_trace", None);
    let output = common::process_output_with_timeout(
        "selection payload and owner contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let lines: Vec<_> = events.lines().collect();
    assert_eq!(
        lines.len(),
        2,
        "one String allocation and its sole release; no selection allocation/clone/drop: {events}"
    );
    let allocation = lines[0]
        .strip_prefix("mmap(")
        .expect("source String allocation");
    let size: usize = allocation.split(", ").nth(1).unwrap().parse().unwrap();
    let address = lines[0].rsplit_once(" = ").unwrap().1;
    assert!(address.starts_with("0x"), "{events}");
    let release = lines[1]
        .strip_prefix("munmap(")
        .expect("sole String owner release");
    let (fields, result) = release.split_once(')').unwrap();
    let (freed_address, freed_size) = fields.split_once(',').unwrap();
    assert_eq!(freed_address.trim(), address, "{events}");
    assert_eq!(
        freed_size.trim().parse::<usize>().unwrap(),
        size,
        "{events}"
    );
    assert_eq!(result.trim(), "= 0", "{events}");
}

#[derive(Default)]
struct State {
    length: u64,
    position: u64,
    source_calls: u64,
    callback_calls: u64,
    callback_sum: u64,
    events: Vec<u64>,
}
#[derive(Clone)]
struct Probe(Rc<RefCell<State>>);
impl Iterator for Probe {
    type Item = u64;
    fn next(&mut self) -> Option<Self::Item> {
        let mut state = self.0.borrow_mut();
        state.source_calls += 1;
        if state.position == state.length {
            state.events.push(199);
            return None;
        }
        let value = state.position;
        state.position += 1;
        state.events.push(100 + value);
        Some(value)
    }
}
fn test(state: &Rc<RefCell<State>>, mask: u64, value: u64, tag: u64) -> bool {
    let mut state = state.borrow_mut();
    state.callback_calls += 1;
    state.callback_sum += value;
    state.events.push(tag + value);
    (mask >> value) & 1 != 0
}

#[derive(Default)]
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    ends: Vec<usize>,
    records: Vec<[u64; 5]>,
}
impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }
    fn observe<J: Iterator<Item = u64> + Clone>(
        &mut self,
        mut first: J,
        state: Rc<RefCell<State>>,
        calls: u64,
        schedule: u64,
    ) {
        let mut second = first.clone();
        assert_eq!(state.borrow().source_calls, 0);
        assert_eq!(state.borrow().callback_calls, 0);
        for call in 0..calls {
            let item = if (schedule >> call) & 1 == 0 {
                first.next()
            } else {
                second.next()
            };
            self.word(u64::from(item.is_some()));
            self.word(item.unwrap_or(0));
            let state = state.borrow();
            self.word(state.position);
            self.word(state.source_calls);
            self.word(state.callback_calls);
            self.word(state.callback_sum);
        }
        let state = state.borrow();
        self.word(state.events.len() as u64);
        for event in &state.events {
            self.word(*event);
        }
        self.ends.push(self.expected.len());
    }
    fn case(&mut self, record: [u64; 5]) {
        self.records.push(record);
        for value in record {
            self.input.extend_from_slice(&value.to_le_bytes());
        }
        let [op, length, calls, schedule, argument] = record;
        let state = Rc::new(RefCell::new(State {
            length,
            ..State::default()
        }));
        let source = Probe(Rc::clone(&state));
        let callback = Rc::clone(&state);
        // Standard selection methods supply an independent semantic oracle.
        // Each Fuse belongs to one copied adapter, matching Lanius's stronger
        // fused protocol while the underlying traced source remains shared.
        match op {
            0 => self.observe(
                source
                    .filter(move |value| test(&callback, argument, *value, 200))
                    .fuse(),
                state,
                calls,
                schedule,
            ),
            1 => self.observe(
                source
                    .filter_map(move |value| {
                        test(&callback, argument, value, 300).then_some(value * 3 + 11)
                    })
                    .fuse(),
                state,
                calls,
                schedule,
            ),
            2 => self.observe(
                source.skip(argument as usize).fuse(),
                state,
                calls,
                schedule,
            ),
            3 => self.observe(
                source
                    .take_while(move |value| test(&callback, argument, *value, 200))
                    .fuse(),
                state,
                calls,
                schedule,
            ),
            4 => self.observe(
                source
                    .skip_while(move |value| test(&callback, argument, *value, 200))
                    .fuse(),
                state,
                calls,
                schedule,
            ),
            _ => panic!("unknown selection model operation"),
        }
    }
}

#[test]
fn selection_sequences_and_copy_pull_order_match_independent_models() {
    let mut models = Models::default();
    for length in 0..=4 {
        for calls in [0, 1, 3, 6] {
            for schedule in [0, u64::MAX, 0xaa] {
                for op in [0, 1, 3, 4] {
                    // None, all, and a true prefix followed by false then true.
                    for mask in [0, u64::MAX, 0b1011] {
                        models.case([op, length, calls, schedule, mask]);
                    }
                }
                for count in [0, 1, 3, u64::MAX] {
                    models.case([2, length, calls, schedule, count]);
                }
            }
        }
    }
    let exe = executable("model.lani");
    let input = common::TempArtifact::new("laniusc_iterator_selection", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "selection shared-source sequence and callback models",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    if output.stdout != models.expected {
        let first = output
            .stdout
            .iter()
            .zip(&models.expected)
            .position(|(a, b)| a != b)
            .unwrap_or(output.stdout.len().min(models.expected.len()));
        let case = models.ends.partition_point(|end| *end <= first);
        let word = first / 8;
        let start = if case == 0 { 0 } else { models.ends[case - 1] };
        let nearby_start = word.saturating_sub(4);
        let nearby_end = word.saturating_add(6);
        let nearby = |bytes: &[u8]| {
            bytes
                .chunks_exact(8)
                .enumerate()
                .skip(nearby_start)
                .take(nearby_end - nearby_start)
                .map(|(index, value)| (index, u64::from_le_bytes(value.try_into().unwrap())))
                .collect::<Vec<_>>()
        };
        panic!(
            "case {case}, record {:?}, first different byte {first}, absolute word {word}, case word {}; actual length {}, expected {}; nearby actual {:?}; nearby expected {:?}",
            models.records.get(case),
            (first - start) / 8,
            output.stdout.len(),
            models.expected.len(),
            nearby(&output.stdout),
            nearby(&models.expected)
        );
    }
    eprintln!(
        "{} selection/copy/callback commands passed in one native process",
        models.ends.len()
    );
}
