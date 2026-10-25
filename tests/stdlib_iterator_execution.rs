// Focused x86_64 Linux native admission through the GPU compiler.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterators")
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
    let exe = common::TempArtifact::new("laniusc_iterator", name, None);
    exe.write_bytes(bytes); // Unchanged common x86 jump validation.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn tiny_imported_iterator_adapter_and_consumer_admission() {
    let exe = executable("admission.lani");
    let result = common::short_process_output_with_timeout(
        "iterator admission",
        &mut Command::new(exe.path()),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}

#[test]
fn cursor_and_adapter_contracts_are_fused_and_allocate_nothing() {
    let exe = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_iterator", "allocation_trace", None);
    let result = common::process_output_with_timeout(
        "iterator contracts without allocation",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[derive(Default)]
struct Cases {
    input: Vec<u8>,
    expected: Vec<u8>,
    reply_ends: Vec<usize>,
}
impl Cases {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }
    fn option(&mut self, value: Option<i64>) {
        self.word(u64::from(value.is_some()));
        self.word(value.unwrap_or(0) as u64);
    }
    fn case(&mut self, words: [u64; 6]) {
        for value in words {
            self.input.extend_from_slice(&value.to_le_bytes());
        }
        let [op, a, b, c, d, e] = words;
        match op {
            0 => {
                // Define the finite concatenated sequence independently, then
                // derive source consumption from its prefix length. No replay
                // of the production next/phase implementation is needed.
                let start = a as i64;
                let end = b as i64;
                let left_count = (b - a).min(c);
                let right: Vec<i64> = (-2..e as i32 as i64).collect();
                let joined: Vec<i64> = (start..end)
                    .take(left_count as usize)
                    .chain(right.iter().copied())
                    .collect();
                let count = (joined.len() as u64).min(d) as usize;
                self.word(count as u64);
                for &value in &joined[..count] {
                    self.word(value as u64);
                }
                let left_consumed = (count as u64).min(left_count);
                let right_consumed = count as u64 - left_consumed;
                self.word(b - a - left_consumed);
                self.word(c - left_consumed);
                self.word(right.len() as u64 - right_consumed);
                self.word(d - count as u64);
            }
            1 => {
                // Each adapter has a quota and fused flag, but both borrow one
                // source sequence. The bitmap selects the observable schedule.
                let mut source = (0..a as i64).peekable();
                let mut quotas = [c; 2];
                let mut exhausted = [false; 2];
                self.word(b);
                for index in 0..b {
                    let adapter = ((d >> index) & 1) as usize;
                    let value = if exhausted[adapter] || quotas[adapter] == 0 {
                        None
                    } else {
                        let item = source.next();
                        if item.is_some() {
                            quotas[adapter] -= 1;
                        } else {
                            exhausted[adapter] = true;
                        }
                        item
                    };
                    self.option(value);
                    self.word(source.clone().count() as u64);
                    self.word(quotas[0]);
                    self.word(quotas[1]);
                }
            }
            2 => {
                // Mathematical interval endpoints are wider than i32, and
                // count/skip use u64. No enormous interval is enumerated.
                let start = a as i32 as i64;
                let end = b as i32 as i64 + i64::from(c == 1);
                let length = end.saturating_sub(start).max(0) as u64;
                let skipped = length.min(d);
                let mut remaining = length - skipped;
                let mut position = start + skipped as i64;
                self.word(length);
                self.word(skipped);
                self.word(remaining);
                let next = if remaining == 0 {
                    None
                } else {
                    let item = position;
                    position += 1;
                    remaining -= 1;
                    Some(item)
                };
                self.option(next);
                assert!(
                    remaining <= 64 || e <= 64,
                    "test does not request billions of next calls"
                );
                let advanced = remaining.min(e);
                let observed_none = remaining < e;
                position += advanced as i64;
                remaining -= advanced;
                self.word(advanced);
                self.word(u64::from(observed_none));
                self.word(remaining);
                self.option(if remaining == 0 { None } else { Some(position) });
            }
            _ => panic!("unknown test operation"),
        }
        self.reply_ends.push(self.expected.len());
    }
}

#[test]
fn borrowed_composition_and_full_i32_ranges_match_independent_sequence_models() {
    let mut cases = Cases::default();
    for start in 0..=8 {
        for end in start..=8 {
            for left in [0, 1, 2, 8, u64::MAX] {
                for outer in [0, 1, 3, 12, u64::MAX] {
                    for right_end in [-2_i32, 1, 4] {
                        cases.case([0, start, end, left, outer, right_end as u64]);
                    }
                }
            }
        }
    }
    let mut seed = 0x4954_4552_2026_u64;
    let mut next = || {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        seed
    };
    for length in 0..=10 {
        for quota in [0, 1, 2, 5, u64::MAX] {
            for pattern in [0, u64::MAX, 0xaaaa_aaaa, 0x5555_5555, next()] {
                cases.case([1, length, 32, quota, pattern, 0]);
            }
        }
    }
    for start in -4_i32..=4 {
        for end in -4_i32..=4 {
            for inclusive in 0..=1 {
                for skip in [0, 1, 2, u64::MAX] {
                    for consume in [0, 1, 2, 12] {
                        cases.case([2, start as u64, end as u64, inclusive, skip, consume]);
                    }
                }
            }
        }
    }
    for start in [i32::MIN, i32::MIN + 1, -1, 0, i32::MAX - 1, i32::MAX] {
        for end in [i32::MIN, i32::MIN + 1, -1, 0, i32::MAX - 1, i32::MAX] {
            for inclusive in 0..=1 {
                let length = (end as i64 + inclusive as i64 - start as i64).max(0) as u64;
                for skip in [0, 1, length.saturating_sub(1), length, u64::MAX] {
                    let after_next = length.saturating_sub(skip).saturating_sub(1);
                    let consume = if after_next <= 64 { u64::MAX } else { 2 };
                    cases.case([2, start as u64, end as u64, inclusive, skip, consume]);
                }
            }
        }
    }
    let exe = executable("model.lani");
    let input = common::TempArtifact::new("laniusc_iterator", "model_input", None);
    input.write_bytes(&cases.input);
    let output = common::process_output_with_timeout(
        "iterator sequence/state models",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(15),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    if output.stdout != cases.expected {
        let first = output
            .stdout
            .iter()
            .zip(&cases.expected)
            .position(|(a, b)| a != b)
            .unwrap_or(output.stdout.len().min(cases.expected.len()));
        let case = cases.reply_ends.partition_point(|end| *end <= first);
        panic!(
            "case {case}, first different byte {first}; lengths actual={} expected={}",
            output.stdout.len(),
            cases.expected.len()
        );
    }
    eprintln!(
        "{} independently modeled iterator cases passed",
        cases.reply_ends.len()
    );
}

#[test]
fn shallow_owner_items_and_native_physical_bounds_keep_existing_contracts() {
    let owned = executable("owned_items.lani");
    let trace = common::TempArtifact::new("laniusc_iterator", "owner_trace", None);
    let result = common::process_output_with_timeout(
        "shallow iterator owner aliases",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(owned.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let mut allocation = None;
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            assert!(
                allocation.is_none(),
                "iteration must not allocate: {events}"
            );
            let size: usize = args.split(", ").nth(1).unwrap().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.to_string();
            assert!(address.starts_with("0x"), "{events}");
            allocation = Some((address, size));
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (address, size) = allocation
                .take()
                .expect("a matching source String allocation");
            let (fields, tail) = args.split_once(')').expect("closed munmap arguments");
            let (released_address, released_size) =
                fields.split_once(',').expect("two munmap arguments");
            assert_eq!(released_address.trim(), address, "{events}");
            assert_eq!(
                released_size.trim().parse::<usize>().unwrap(),
                size,
                "{events}"
            );
            assert_eq!(tail.trim(), "= 0", "{events}");
        } else {
            panic!("unexpected memory trace: {events}");
        }
    }
    assert!(allocation.is_none(), "{events}");
    assert_eq!(
        events.lines().count(),
        2,
        "one source allocation and its single release: {events}"
    );

    let physical = executable("physical_bounds.lani");
    let result = common::short_process_output_with_timeout(
        "iterator physical bounds",
        &mut Command::new(physical.path()),
    );
    assert_eq!(result.status.code(), Some(101), "{result:?}");
}

#[test]
fn consumers_require_the_exact_item_protocol_bound() {
    for name in ["reject_missing_bound.lani", "reject_wrong_item.lani"] {
        let error = compile(name).expect_err("the exact Iterator<i32> implementation is required");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(
            diagnostic.code, "LNC0008",
            "expected bound rejection, not an incidental parser/compiler failure: {error}"
        );
        let label = diagnostic
            .primary_label
            .expect("rejection retains the consumer occurrence");
        assert!(label.path.ends_with(name), "{label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .is_some_and(|line| line.contains("core::iter::advance_up_to")),
            "{label:?}"
        );
    }
}
