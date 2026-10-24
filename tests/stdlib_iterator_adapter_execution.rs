// Native adapter contracts, sequence/call-order models, and one overflow trap.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_adapters")
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
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_iterator_adapter", name, None);
    exe.write_bytes(bytes); // Unchanged common strict x86 jump validation.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn typed_callbacks_composition_and_shallow_owner_contracts_execute() {
    let exe = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_iterator_adapter", "owner_trace", None);
    let output = common::process_output_with_timeout(
        "typed adapter and owner contracts",
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
        "one String allocation and its sole release; no adapter allocation/clone/drop: {events}"
    );
    let args = lines[0]
        .strip_prefix("mmap(")
        .expect("source String allocation");
    let size: usize = args.split(", ").nth(1).unwrap().parse().unwrap();
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
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    ends: Vec<usize>,
}
impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }
    fn option(&mut self, value: Option<(u64, u64)>, pair: bool) {
        self.word(u64::from(value.is_some()));
        self.word(value.map_or(0, |item| item.0));
        if pair {
            self.word(value.map_or(0, |item| item.1));
        }
    }
    fn case(&mut self, record: [u64; 5]) {
        for value in record {
            self.input.extend_from_slice(&value.to_le_bytes());
        }
        let [op, a, b, c, d] = record;
        let mut trace = Vec::new();
        let mut ended_copies = BTreeSet::new();
        match op {
            0 | 3 => {
                // Shared finite sequence. Before EOF every selected adapter
                // succeeds. Afterwards each distinct copy probes EOF once.
                for call in 0..b {
                    let selected = (c >> call) & 1;
                    let success = call < a;
                    if success {
                        trace.push(1);
                        if op == 0 {
                            trace.push(3);
                        }
                    } else if ended_copies.insert(selected) {
                        trace.push(1);
                    }
                    let item = if !success {
                        None
                    } else if op == 0 {
                        Some((call * 3 + d, 0))
                    } else {
                        let preceding = (0..call)
                            .filter(|previous| ((c >> previous) & 1) == selected)
                            .count() as u64;
                        Some((d + preceding, call))
                    };
                    self.option(item, op == 3);
                    self.word((call + 1).min(a));
                    self.word((call + 1).min(a) + ended_copies.len() as u64);
                    if op == 0 {
                        self.word((call + 1).min(a));
                    }
                }
            }
            1 => {
                // Sequence zip, including the finite supply of unpaired left
                // items available to independently terminating adapter copies.
                let pairs = a.min(b);
                for call in 0..c {
                    let selected = (d >> call) & 1;
                    if call < pairs {
                        trace.extend([1, 2]);
                    } else {
                        let previous = ended_copies.len() as u64;
                        if ended_copies.insert(selected) {
                            trace.push(1);
                            if a > b && previous < a - b {
                                trace.push(2);
                            }
                        }
                    }
                    self.option((call < pairs).then_some((call, 100 + call)), true);
                    let completed = (call + 1).min(pairs);
                    let terminal = ended_copies.len() as u64;
                    let unmatched = if a > b { terminal.min(a - b) } else { 0 };
                    self.word(completed + unmatched);
                    self.word(completed);
                    self.word(completed + terminal);
                    self.word(completed + unmatched);
                }
            }
            2 => {
                // Aliased zip partitions one finite sequence into adjacent
                // pairs, with a single unmatched trailing item for odd length.
                let pairs = a / 2;
                for call in 0..b {
                    let selected = (c >> call) & 1;
                    if call < pairs {
                        trace.extend([1, 1]);
                    } else {
                        let first_terminal = ended_copies.is_empty();
                        if ended_copies.insert(selected) {
                            trace.push(1);
                            if first_terminal && a % 2 == 1 {
                                trace.push(1);
                            }
                        }
                    }
                    self.option((call < pairs).then_some((call * 2, call * 2 + 1)), true);
                    let completed = (call + 1).min(pairs);
                    let trailing = u64::from(!ended_copies.is_empty()) * (a % 2);
                    self.word(completed * 2 + trailing);
                    self.word(completed * 2 + trailing + ended_copies.len() as u64);
                }
            }
            _ => panic!("unknown model op"),
        }
        self.word(trace.len() as u64);
        for event in trace {
            self.word(event);
        }
        self.ends.push(self.expected.len());
    }
}

#[test]
fn adapter_sequences_and_exact_pull_order_match_independent_models() {
    let mut models = Models::default();
    for length in 0..=4 {
        for calls in 0..=7 {
            for pattern in [0, u64::MAX, 0xaa] {
                models.case([0, length, calls, pattern, 7]);
                models.case([3, length, calls, pattern, 29]);
            }
        }
    }
    for left in 0..=4 {
        for right in 0..=4 {
            for calls in 0..=7 {
                for pattern in [0, u64::MAX, 0xaa] {
                    models.case([1, left, right, calls, pattern]);
                }
            }
        }
    }
    for length in 0..=6 {
        for calls in 0..=7 {
            for pattern in [0, u64::MAX, 0xaa] {
                models.case([2, length, calls, pattern, 0]);
            }
        }
    }
    let exe = executable("model.lani");
    let input = common::TempArtifact::new("laniusc_iterator_adapter", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "adapter sequence and call-order models",
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
        panic!(
            "case {case}, first different byte {first}; actual length {}, expected {}",
            output.stdout.len(),
            models.expected.len()
        );
    }
    eprintln!(
        "{} adapter sequence/call-order commands passed in one native process",
        models.ends.len()
    );
}

#[test]
fn enumerate_consumes_the_unindexable_item_before_checked_panic() {
    let exe = executable("overflow.lani");
    let output = common::signal_process_output_with_timeout(
        "enumerate overflow witness",
        &mut Command::new(exe.path()),
    );
    assert_eq!(
        output.status.signal(),
        Some(4),
        "checked panic must trap: {output:?}"
    );
    assert_eq!(
        output.stdout, b"a!b",
        "source witnessed the extra Some; no next result was returned"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn mapper_and_zip_bounds_require_exact_input_and_output_items() {
    for name in [
        "reject_mapper_input.lani",
        "reject_mapper_output.lani",
        "reject_zip_item.lani",
    ] {
        let error = compile(name).expect_err("the exact callback/source item bounds are required");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("bound rejection retains its source call");
        assert!(label.path.ends_with(name), "{label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::iter::map") || line.contains("core::iter::zip"),
            "{label:?}"
        );
    }
}
