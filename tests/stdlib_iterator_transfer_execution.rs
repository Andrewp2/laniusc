//! Bounded transfer, rejected-item handoff and independent resumable state models.
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
        .join("tests/fixtures/stdlib_foundation/iterator_transfer")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("iterator transfer {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_iterator_transfer", name, None);
    // Retain the shared strict ELF/native transfer checker.
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn typed_bounded_transfer_retry_and_owner_contracts_execute() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_iterator_transfer", "contract_memory", None);
    let output = common::process_output_with_timeout(
        "typed bounded iterator transfer",
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
                "one matching owner release: {events}"
            );
            releases.push(address.trim().to_owned());
        } else {
            panic!("unexpected transfer memory call: {events}");
        }
    }
    assert_eq!(
        allocations.len(),
        3,
        "only String/Vec/Deque storage may allocate: {events}"
    );
    assert_eq!(releases.len(), 3, "{events}");
    assert!(live.is_empty(), "{events}");
    assert_eq!(
        releases.last(),
        allocations.first(),
        "the external String outlives every alias: {events}"
    );
}

fn item(output: &mut Vec<u64>, key: u64) {
    let flag = if key % 3 == 0 {
        0
    } else if key % 2 == 0 {
        2
    } else {
        1
    };
    output.extend([key, u64::MAX - key, flag]);
}

struct State {
    source: VecDeque<u64>,
    initial_length: usize,
    source_calls: u64,
    sink: Vec<u64>,
    sink_calls: u64,
    reject: Option<u64>,
    trace: Vec<u64>,
}
impl State {
    fn new(length: u64, prefix: u64, reject: u64) -> Self {
        Self {
            source: (0..length).collect(),
            initial_length: length as usize,
            source_calls: 0,
            sink: (100..100 + prefix).collect(),
            sink_calls: 0,
            reject: Some(reject),
            trace: Vec::new(),
        }
    }
    fn error(&self, output: &mut Vec<u64>, key: u64) {
        output.push(500 + self.reject.expect("only a matching policy rejects"));
        item(output, key);
        output.extend([self.sink.len() as u64, self.sink_calls]);
    }
    fn snapshot(&self, output: &mut Vec<u64>) {
        output.extend([
            (self.initial_length - self.source.len()) as u64,
            self.source_calls,
            self.sink_calls,
            self.reject.unwrap_or(u64::MAX),
            self.sink.len() as u64,
        ]);
        for &key in &self.sink {
            item(output, key);
        }
    }
    fn transfer(&mut self, quota: u64, output: &mut Vec<u64>) -> Option<u64> {
        // Find the finite candidate window and its rejected item independently
        // of the production loop's successful-item counter.
        let window: Vec<_> = self
            .source
            .iter()
            .copied()
            .take(quota.min(self.source.len() as u64) as usize)
            .collect();
        let rejected = window.iter().position(|key| Some(*key) == self.reject);
        let accepted = rejected.unwrap_or(window.len());
        let consumed = accepted + usize::from(rejected.is_some());
        let observed: Vec<_> = self.source.drain(..consumed).collect();
        self.source_calls += consumed as u64;
        self.sink_calls += consumed as u64;
        for key in &observed {
            self.trace.extend([1, 100 + key]);
        }
        self.sink.extend_from_slice(&observed[..accepted]);
        if let Some(index) = rejected {
            let key = window[index];
            output.extend([1, accepted as u64]);
            item(output, key);
            self.error(output, key);
            Some(key)
        } else {
            let exhausted = self.source.is_empty() && quota > accepted as u64;
            if exhausted {
                self.source_calls += 1;
                self.trace.push(1);
            }
            output.extend([0, accepted as u64, u64::from(exhausted)]);
            None
        }
    }
    fn retry(&mut self, pending: Option<u64>, output: &mut Vec<u64>) {
        if let Some(key) = pending {
            self.trace.push(100 + key);
            self.sink_calls += 1;
            if self.reject == Some(key) {
                output.push(2);
                item(output, key);
                self.error(output, key);
            } else {
                self.sink.push(key);
                output.push(1);
                item(output, key);
            }
        } else {
            output.push(0);
        }
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
        let [
            length,
            prefix,
            first_reject,
            second_reject,
            first_quota,
            second_quota,
        ] = command;
        let mut state = State::new(length, prefix, first_reject);
        let first = state.transfer(first_quota, &mut self.expected);
        state.snapshot(&mut self.expected);
        state.retry(first, &mut self.expected);
        state.snapshot(&mut self.expected);
        state.reject = None;
        state.retry(first, &mut self.expected);
        state.snapshot(&mut self.expected);
        state.reject = Some(second_reject);
        let second = state.transfer(second_quota, &mut self.expected);
        state.snapshot(&mut self.expected);
        state.retry(second, &mut self.expected);
        state.snapshot(&mut self.expected);
        state.reject = None;
        state.retry(second, &mut self.expected);
        state.snapshot(&mut self.expected);
        for quota in [u64::MAX, 0, 1] {
            assert_eq!(state.transfer(quota, &mut self.expected), None);
            state.snapshot(&mut self.expected);
        }
        self.expected.push(state.trace.len() as u64);
        self.expected.extend(state.trace);
        assert_eq!(
            state.sink,
            (100..100 + prefix).chain(0..length).collect::<Vec<_>>()
        );
        self.cases.push((self.expected.len(), command));
    }
}

#[test]
fn transfer_state_sequences_match_independent_retry_model() {
    let mut model = Model::default();
    for length in 0..=6 {
        for prefix in [0, 2] {
            for first_reject in BTreeSet::from([0, length / 2, length, length + 1]) {
                for first_quota in BTreeSet::from([0, 1, length, length + 1, u64::MAX]) {
                    let second_reject = (first_reject + 1) % (length + 2);
                    let second_quota = if prefix == 2 && first_reject == length {
                        u64::MAX
                    } else {
                        (first_reject + prefix + u64::from(first_quota == u64::MAX)) % (length + 2)
                    };
                    model.add([
                        length,
                        prefix,
                        first_reject,
                        second_reject,
                        first_quota,
                        second_quota,
                    ]);
                }
            }
        }
    }
    let input = common::TempArtifact::new("laniusc_iterator_transfer", "model_input", None);
    input.write_bytes(&model.input);
    let executable = executable("model.lani");
    let trace = common::TempArtifact::new("laniusc_iterator_transfer", "model_memory", None);
    let output = common::process_output_with_timeout(
        "iterator transfer state models",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(10),
    );
    successful(&output);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "the model source/sink/transfer must allocate nothing: {events}"
    );
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
            "transfer command {command:?}"
        );
        start = *end;
    }
    eprintln!(
        "{} independent transfer commands, {} stateful actions, passed in one native execution",
        model.cases.len(),
        model.cases.len() * 9
    );
}
