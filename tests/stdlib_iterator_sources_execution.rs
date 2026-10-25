#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

fn executable(entry: &Path, name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = entry.to_path_buf();
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_iterator_sources", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/iterator_sources")
        .join(name)
}

#[test]
fn source_shapes_aliases_lazy_stepping_and_one_owner_release_execute() {
    let executable = executable(&fixture("contracts.lani"), "contracts");
    let trace = common::TempArtifact::new("laniusc_iterator_sources", "owner_trace", None);
    let output = common::process_output_with_timeout(
        "iterator sources, compound items and shallow owner aliases",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    let lines: Vec<_> = events.lines().collect();
    assert_eq!(
        lines.len(),
        2,
        "one owner allocation/release; sources must not clone or destroy aliases: {events}"
    );
    let allocation = lines[0].strip_prefix("mmap(").expect("owner allocation");
    let size = allocation.split(',').nth(1).unwrap().trim();
    let address = lines[0].rsplit_once(" = ").unwrap().1;
    assert!(address.starts_with("0x"), "{events}");
    let release = lines[1]
        .strip_prefix("munmap(")
        .expect("sole owner release");
    let (arguments, result) = release.split_once(')').unwrap();
    let (released_address, released_size) = arguments.split_once(',').unwrap();
    assert_eq!(released_address.trim(), address, "{events}");
    assert_eq!(released_size.trim(), size, "{events}");
    assert_eq!(result.trim(), "= 0", "{events}");
}

#[derive(Clone, Copy, Default)]
struct CursorState {
    used: bool,
    ended: bool,
}

#[derive(Default)]
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    cases: Vec<[u64; 6]>,
    ends: Vec<usize>,
}
impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }

    fn case(&mut self, record: [u64; 6]) {
        self.cases.push(record);
        for word in record {
            self.input.extend_from_slice(&word.to_le_bytes());
        }
        let [kind, length, step, calls, schedule, fork_after] = record;
        if kind <= 1 && step == 0 {
            self.word(0);
            self.ends.push(self.expected.len());
            return;
        }
        self.word(1);
        let mut states = [CursorState::default(); 2];
        let mut position = 0;
        let mut polls = 0;
        for call in 0..calls {
            if call == fork_after {
                states[1] = states[0];
            }
            let selected = if kind == 1 || call < fork_after {
                0
            } else {
                ((schedule >> call) & 1) as usize
            };
            let state = &mut states[selected];
            let item = match kind {
                0 | 1 if state.ended => None,
                0 | 1 => {
                    // Compute the next selected index mathematically, rather
                    // than replaying the implementation's skip/poll loop.
                    let gap = if state.used { step - 1 } else { 0 };
                    let target = u128::from(position) + u128::from(gap);
                    state.used = true;
                    if target < u128::from(length) {
                        let target = target as u64;
                        polls += target + 1 - position;
                        position = target + 1;
                        Some(target)
                    } else {
                        polls += length - position + 1;
                        position = length;
                        state.ended = true;
                        None
                    }
                }
                2 if state.used => None,
                2 => {
                    state.used = true;
                    Some(100 + length)
                }
                3 => Some(100 + length),
                4 => None,
                _ => unreachable!(),
            };
            self.word(u64::from(item.is_some()));
            self.word(item.unwrap_or(0));
            self.word(position);
            self.word(polls);
        }
        self.ends.push(self.expected.len());
    }
}

#[test]
fn copied_and_aliased_source_states_match_math_models_for_all_short_schedules() {
    let mut models = Models::default();
    for length in 0..=5 {
        for step in [1, 2, 3, 1 << 63, u64::MAX] {
            for calls in 0..=5 {
                for fork_after in 0..=calls {
                    for schedule in 0..(1 << calls) {
                        models.case([0, length, step, calls, schedule, fork_after]);
                        if fork_after == 0 {
                            models.case([1, length, step, calls, schedule, 0]);
                        }
                    }
                }
            }
        }
    }
    for kind in [2, 3, 4] {
        for value in [0, 3, 5] {
            for calls in 0..=5 {
                for fork_after in 0..=calls {
                    for schedule in 0..(1 << calls) {
                        models.case([kind, value, 0, calls, schedule, fork_after]);
                    }
                }
            }
        }
    }
    for kind in [0, 1] {
        for length in [0, 5] {
            for calls in 0..=5 {
                models.case([kind, length, 0, calls, 0, 0]);
            }
        }
    }
    let executable = executable(&fixture("model.lani"), "models");
    let input = common::TempArtifact::new("laniusc_iterator_sources", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "source copy/alias states, lazy first pull and u64 stepping models",
        Command::new(executable.path()).stdin(fs::File::open(input.path()).unwrap()),
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
        let index = models.ends.partition_point(|end| *end <= first);
        panic!(
            "source model case {} {:?}, first different byte {first}; actual {}, expected {}",
            index,
            models.cases.get(index),
            output.stdout.len(),
            models.expected.len()
        );
    }
    eprintln!(
        "{} source state/copy/alias commands passed",
        models.cases.len()
    );
}

fn expected_sample(start: i32, end: i32, step: u64, limit: u64) -> String {
    let available = (i64::from(end) - i64::from(start) + 1).max(0) as u64;
    let prefix = available.min(limit);
    let count = if prefix == 0 {
        0
    } else {
        1 + (prefix - 1) / step
    };
    let sum = if count == 0 {
        0
    } else {
        i128::from(count) * (2 * i128::from(start) + i128::from(count - 1) * i128::from(step)) / 2
    };
    format!("count,sum\n{count},{sum}\n")
}

#[test]
fn sample_every_bounds_upstream_work_and_formats_range_statistics() {
    let entry =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("sample_programs/library/sample_every.lani");
    let executable = executable(&entry, "sample_every");
    let bounds = [
        (-3, 8),
        (2, 20),
        (5, 2),
        (i32::MIN, i32::MAX),
        (i32::MAX - 2, i32::MAX),
    ];
    for (start, end) in bounds {
        for step in [1, 3, u64::MAX] {
            for limit in [0, 1, 12] {
                let args = [
                    start.to_string(),
                    end.to_string(),
                    step.to_string(),
                    limit.to_string(),
                ];
                let output = common::process_output_with_timeout(
                    format!("sample_every {args:?}"),
                    Command::new(executable.path()).args(&args),
                    Duration::from_secs(2),
                );
                assert_eq!(output.status.code(), Some(0), "{args:?}: {output:?}");
                assert!(output.stderr.is_empty(), "{args:?}: {output:?}");
                assert_eq!(
                    output.stdout,
                    expected_sample(start, end, step, limit).as_bytes(),
                    "{args:?}"
                );
            }
        }
    }
    for args in [
        vec!["0", "9", "0", "12"],
        vec!["0", "9", "-1", "12"],
        vec!["0", "9", "18446744073709551616", "12"],
        vec!["0", "9", "3", "1000001"],
        vec!["2147483648", "9", "3", "12"],
        vec!["0", "9", "3"],
        vec!["0", "9", "3", "12", "extra"],
    ] {
        let output = common::short_process_output_with_timeout(
            "sample_every invalid arguments",
            Command::new(executable.path()).args(&args),
        );
        assert_eq!(output.status.code(), Some(2), "{args:?}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{args:?}: {output:?}"
        );
    }
    let output = common::short_process_output_with_timeout(
        "sample_every checked output failure",
        // The common helper captures Command stdout. Redirect in the child so
        // the program itself still receives the failing descriptor.
        Command::new("sh")
            .args(["-c", "exec \"$@\" > /dev/full", "sample_every-output"])
            .arg(executable.path())
            .args(["-3", "8", "3", "12"]),
    );
    assert_eq!(output.status.code(), Some(3), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
