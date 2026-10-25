//! Owning Vec/Deque cursor handoff and independent sequence state models.
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
        .join("tests/fixtures/stdlib_foundation/owning_iterators")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("owning iterators {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_owning_iterator", name, None);
    executable.write_bytes(bytes); // Retain the shared strict native ELF checker.
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
struct MemoryLedger {
    allocations: usize,
    releases: Vec<usize>,
    events: Vec<(bool, usize)>,
}
fn memory_ledger(events: &str) -> MemoryLedger {
    let mut live = BTreeMap::new();
    let mut allocations = 0;
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
            allocations += 1;
            assert!(
                live.insert(address, (length, allocations)).is_none(),
                "{events}"
            );
            order.push((true, allocations));
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            let (allocated_length, identity) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("one live owner for release: {events}"));
            assert_eq!(
                allocated_length,
                length.trim().parse::<usize>().unwrap(),
                "matching address and size: {events}"
            );
            releases.push(identity);
            order.push((false, identity));
        } else {
            panic!("unexpected owning iterator memory call: {events}");
        }
    }
    assert!(live.is_empty(), "all owners released: {events}");
    MemoryLedger {
        allocations,
        releases,
        events: order,
    }
}
fn traced(
    name: &str,
    executable: &common::TempArtifact,
    input: Option<&common::TempArtifact>,
    timeout: u64,
) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_owning_iterator", name, None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
        .arg(executable.path());
    if let Some(input) = input {
        command.stdin(std::fs::File::open(input.path()).unwrap());
    }
    let output =
        common::process_output_with_timeout(name, &mut command, Duration::from_secs(timeout));
    successful(&output);
    (output, std::fs::read_to_string(trace.path()).unwrap())
}

#[test]
fn typed_owning_cursor_resource_handoffs_execute() {
    let executable = executable("contracts.lani");
    let (output, trace) = traced("typed owning iterators", &executable, None, 5);
    assert!(output.stdout.is_empty(), "{output:?}");
    let ledger = memory_ledger(&trace);
    // Each make() allocates String then nested Vec. Vector setup allocates
    // backing #1, five pairs #2..11, reused backing #12, and id9's #13/14.
    // Deque setup allocates backing #1, id12/id11/id13/id14 pairs #2..9,
    // reused backing #10, and id19's #11/12. Transfer setup allocates source
    // backing #1, id21/id22/id23 pairs #2..7, then sink backing #8.
    let phases: &[(usize, &[usize])] = &[
        (14, &[13, 14, 12, 2, 3, 10, 11, 8, 9, 4, 5, 6, 7, 1]),
        (12, &[11, 12, 10, 8, 9, 4, 5, 2, 3, 6, 7, 1]),
        (8, &[4, 5, 1, 2, 3, 6, 7, 8]),
    ];
    let mut expected = Vec::new();
    let mut offset = 0;
    for &(count, releases) in phases {
        expected.extend((1..=count).map(|id| (true, offset + id)));
        expected.extend(releases.iter().map(|id| (false, offset + id)));
        offset += count;
    }
    // The final two non-ZST empty reserved owners allocate/release separately;
    // all Unit cases allocate zero. Repeated finish/destruction adds no event.
    expected.extend([(true, 35), (false, 35), (true, 36), (false, 36)]);
    assert_eq!(
        ledger.allocations, 36,
        "only explicit typed owners allocate: {trace}"
    );
    assert_eq!(ledger.releases.len(), 36, "{trace}");
    assert_eq!(
        ledger.events, expected,
        "typed owner allocation/release identities and order: {trace}"
    );
}

#[test]
fn imported_string_cursor_helpers_cleanup_without_caller_finish_result_projection() {
    let executable = executable("helper_only_strings.lani");
    let (output, trace) = traced("helper-only String owners", &executable, None, 5);
    assert!(output.stdout.is_empty(), "{output:?}");
    let ledger = memory_ledger(&trace);
    // Vec backing #1, then three unique Strings #2..4. Deque backing #5,
    // then three unique Strings #6..8, logically ordered #7/#6/#8 by pushes.
    // Only the two helpers destroy items and release their cursor backing.
    let expected: Vec<_> = (1..=4)
        .map(|id| (true, id))
        .chain([2, 3, 4, 1].into_iter().map(|id| (false, id)))
        .chain((5..=8).map(|id| (true, id)))
        .chain([7, 6, 8, 5].into_iter().map(|id| (false, id)))
        .collect();
    assert_eq!(
        ledger.allocations, 8,
        "six unique Strings and two backing owners only: {trace}"
    );
    assert_eq!(ledger.releases.len(), 8, "{trace}");
    assert_eq!(
        ledger.events, expected,
        "helper-only cleanup identities/order: {trace}"
    );
}

fn item(output: &mut Vec<u64>, id: u64) {
    output.extend([
        id,
        u64::MAX - id,
        (1_u64 << 32) + id,
        id * 17 + 3,
        if id % 3 == 0 {
            0
        } else if id % 2 == 0 {
            2
        } else {
            1
        },
    ]);
}
fn optional(output: &mut Vec<u64>, id: Option<u64>) {
    output.push(u64::from(id.is_some()));
    if let Some(id) = id {
        item(output, id);
    }
}
struct State {
    remaining: VecDeque<u64>,
    capacity: u64,
    front_calls: u64,
    back_calls: u64,
    consumed: Vec<u64>,
    accepted: Vec<u64>,
    sink_calls: u64,
}
impl State {
    fn new(length: u64, capacity: u64) -> Self {
        Self {
            remaining: (0..length).collect(),
            capacity,
            front_calls: 0,
            back_calls: 0,
            consumed: Vec::new(),
            accepted: Vec::new(),
            sink_calls: 0,
        }
    }
    fn state(&self, output: &mut Vec<u64>) {
        output.extend([
            self.remaining.len() as u64,
            self.capacity,
            u64::from(self.remaining.is_empty()),
        ]);
        for &id in &self.remaining {
            item(output, id);
        }
        output.extend([
            self.front_calls,
            self.back_calls,
            self.consumed.len() as u64,
        ]);
        for &id in &self.consumed {
            item(output, id);
        }
        output.extend([self.sink_calls, self.accepted.len() as u64]);
        for &id in &self.accepted {
            item(output, id);
        }
    }
    fn finish(&mut self, output: &mut Vec<u64>) {
        if self.remaining.is_empty() {
            self.capacity = 0;
            output.push(0);
        } else {
            output.extend([1, self.remaining.len() as u64]);
        }
        self.state(output);
    }
    fn pull(&mut self, back: bool) -> Option<u64> {
        let value = if back {
            self.back_calls += 1;
            self.remaining.pop_back()
        } else {
            self.front_calls += 1;
            self.remaining.pop_front()
        };
        if let Some(value) = value {
            self.consumed.push(value);
        }
        value
    }
    fn advance(&mut self, quota: u64, output: &mut Vec<u64>) {
        let count = quota.min(self.remaining.len() as u64);
        let values: Vec<_> = self.remaining.drain(..count as usize).collect();
        self.consumed.extend(values);
        let exhausted = quota > count;
        self.front_calls += count + u64::from(exhausted);
        output.extend([count, u64::from(exhausted)]);
    }
    fn transfer(&mut self, quota: u64, reject: Option<u64>, output: &mut Vec<u64>) {
        // Derive the accepted prefix and possible rejection from a finite
        // sequence window, separately from the production pull/callback loop.
        let window: Vec<_> = self
            .remaining
            .iter()
            .copied()
            .take(quota.min(self.remaining.len() as u64) as usize)
            .collect();
        let refusal = reject.and_then(|id| window.iter().position(|value| *value == id));
        let accepted = refusal.unwrap_or(window.len());
        let consumed = accepted + usize::from(refusal.is_some());
        let values: Vec<_> = self.remaining.drain(..consumed).collect();
        self.front_calls += consumed as u64;
        self.consumed.extend(&values);
        self.sink_calls += consumed as u64;
        self.accepted.extend(&values[..accepted]);
        if let Some(index) = refusal {
            let rejected = window[index];
            output.extend([1, accepted as u64]);
            item(output, rejected);
            item(output, rejected);
            output.push(self.sink_calls);
            // The fixture explicitly disables rejection and retries once.
            self.sink_calls += 1;
            self.accepted.push(rejected);
        } else {
            let exhausted = quota > accepted as u64;
            self.front_calls += u64::from(exhausted);
            output.extend([0, accepted as u64, u64::from(exhausted)]);
        }
    }
    fn cycle(&mut self, quota: u64, reject: u64, round: usize, output: &mut Vec<u64>) {
        self.state(output);
        self.finish(output);
        self.advance(0, output);
        self.state(output);
        optional(output, self.pull(false));
        self.state(output);
        optional(output, self.pull(true));
        self.state(output);
        self.advance(quota, output);
        self.state(output);
        self.transfer(quota, Some(reject), output);
        self.state(output);
        if round < 2 {
            self.restore(output);
            self.cycle(quota, reject, round + 1, output);
        } else {
            self.transfer(u64::MAX, None, output);
            self.state(output);
            optional(output, self.pull(false));
            optional(output, self.pull(true));
            self.state(output);
            self.finish(output);
            self.finish(output);
            self.restore(output);
        }
    }
    fn restore(&self, output: &mut Vec<u64>) {
        output.extend([self.remaining.len() as u64, self.capacity]);
        for &id in &self.remaining {
            item(output, id);
        }
    }
    fn check_conservation(&self, length: u64) {
        assert!(self.remaining.is_empty());
        let mut actual = self.consumed.clone();
        actual.sort_unstable();
        assert_eq!(
            actual,
            (0..length).collect::<Vec<_>>(),
            "each payload yielded exactly once"
        );
        assert!(self.accepted.iter().all(|id| self.consumed.contains(id)));
        assert_eq!(
            self.accepted.iter().copied().collect::<BTreeSet<_>>().len(),
            self.accepted.len(),
            "retried rejection accepted once"
        );
    }
}

#[test]
fn owning_cursor_sequences_match_independent_models_without_lifecycle_allocations() {
    let mut commands = Vec::new();
    for kind in 0..2 {
        for length in [0_u64, 1, 6, 9] {
            for spare in [0, 3] {
                for head in 0..if kind == 0 { 1 } else { 3 } {
                    for quota in BTreeSet::from([
                        0,
                        1,
                        2,
                        length.saturating_sub(2),
                        length,
                        length + 1,
                        u64::MAX,
                    ]) {
                        for reject in [2, 9] {
                            commands.push([kind, length, spare, head, quota, reject]);
                        }
                    }
                }
            }
        }
    }
    let input = common::TempArtifact::new("laniusc_owning_iterator", "model_input", None);
    let bytes: Vec<_> = commands
        .iter()
        .flatten()
        .copied()
        .flat_map(u64::to_le_bytes)
        .collect();
    input.write_bytes(bytes);
    let executable = executable("model.lani");
    let (output, trace) = traced(
        "owning iterator sequence models",
        &executable,
        Some(&input),
        15,
    );
    let ledger = memory_ledger(&trace);
    let owners: usize = commands
        .iter()
        .map(|command| 1 + usize::from(command[1] + command[2] > 0))
        .sum();
    assert_eq!(
        ledger.allocations, owners,
        "only initial reservation and independent reused source may allocate: {trace}"
    );
    assert_eq!(ledger.releases.len(), owners, "{trace}");
    assert_eq!(output.stdout.len() % 8, 0, "complete response words");
    let words: Vec<_> = output
        .stdout
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect();
    let mut start = 0;
    for command in &commands {
        let &[kind, length, spare, _head, quota, reject] = command;
        let capacity = *words.get(start).expect("initial capacity record");
        let reuse_capacity = *words.get(start + 1).expect("reused-source capacity record");
        assert!(
            capacity >= length + spare && capacity <= i32::MAX as u64,
            "actual capacity for {command:?}"
        );
        assert!(
            reuse_capacity >= 2 && reuse_capacity <= i32::MAX as u64,
            "reused-source capacity for {command:?}"
        );
        let mut expected = vec![capacity, reuse_capacity];
        let mut state = State::new(length, capacity);
        state.cycle(quota, reject, 0, &mut expected);
        state.check_conservation(length);
        expected.push(2);
        for id in if kind == 0 { [100, 101] } else { [101, 100] } {
            item(&mut expected, id);
        }
        let end = start + expected.len();
        assert_eq!(
            words.get(start..end),
            Some(expected.as_slice()),
            "owning iterator command {command:?}, actual capacities {capacity}/{reuse_capacity}"
        );
        start = end;
    }
    assert_eq!(start, words.len(), "no trailing model response");
    eprintln!("{} independent owning cursor scenarios, {} restore/reopen rounds, two reserved owners per nonzero reservation, passed in one native execution", commands.len(), commands.len() * 3);
}
