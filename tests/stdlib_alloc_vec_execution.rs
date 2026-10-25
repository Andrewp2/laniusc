#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_alloc_vec", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("alloc vector", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}

#[test]
fn vector_contracts_execute_edits_generic_values_and_zero_sized_storage() {
    for name in [
        "alloc_vec",
        "alloc_vec_types",
        "vec_view_dependency/direct",
        "vec_view_dependency/local",
    ] {
        let exe = fixture(name);
        let output = run(&mut Command::new(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
    }
    let exe = fixture("alloc_vec_zero_sized");
    let trace = common::TempArtifact::new("laniusc_alloc_vec", "zero_sized_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "zero-sized vectors must not allocate"
    );
}

#[test]
fn every_vector_allocation_failure_preserves_contents_capacity_and_views() {
    let exe = fixture("alloc_vec_failure");
    let trace = common::TempArtifact::new("laniusc_alloc_vec", "failure_trace", None);
    let execute = |when: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        let output = run(command.arg(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(
                events.contains("INJECTED") && events.contains("ENOMEM"),
                "{events}"
            );
        }
        freed(&events)
    };
    let allocations = execute(None);
    assert!(allocations >= 7, "exercise each allocation path");
    for when in 1..=allocations {
        execute(Some(when));
    }
}

#[test]
fn mixed_edits_match_an_independent_vector_model() {
    let exe = fixture("alloc_vec_model");
    let input = common::TempArtifact::new("laniusc_alloc_vec", "model_input", None);
    let mut seed = 0x7ec0_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut model = Vec::<i32>::new();
    let mut data = Vec::new();
    let mut expected = Vec::new();
    let mut covered = [false; 19];
    for step in 0..6000 {
        let mut op = (random() % 19) as u8;
        if step % 13 < 5 {
            op = 0;
        }
        if step % 127 == 0 {
            op = 18;
        }
        if op == 14 && model.len() > 128 {
            op = 1;
        }
        let mut index = (random() % (model.len() as u32 + 3)) as i32 - 1;
        let mut value = random() as i32;
        if step % 7 == 0 {
            value = 7;
        }
        if step % 17 == 0 {
            value = i32::MIN;
        }
        if step % 23 == 0 {
            value = i32::MAX;
        }
        if op == 6 {
            index = (random() % 42) as i32 - 2;
        }
        if op == 8 {
            index = match step % 5 {
                0 => -1,
                1 => i32::MAX,
                _ => (random() % 129) as i32,
            };
        }
        covered[op as usize] = true;
        data.push(op);
        data.extend_from_slice(&index.to_le_bytes());
        data.extend_from_slice(&value.to_le_bytes());
        let mut tag = 0;
        let mut answer = 0;
        let valid = index >= 0 && (index as usize) < model.len();
        let mut removed = None;
        match op {
            0 => model.push(value),
            1 => removed = model.pop(),
            2 => {
                if valid {
                    removed = Some(std::mem::replace(&mut model[index as usize], value));
                } else {
                    tag = 2;
                }
            }
            3 => {
                if index >= 0 && index as usize <= model.len() {
                    model.insert(index as usize, value);
                } else {
                    tag = 2;
                }
            }
            4 => {
                if valid {
                    removed = Some(model.remove(index as usize));
                } else {
                    tag = 2;
                }
            }
            5 => {
                if valid {
                    removed = Some(model.swap_remove(index as usize));
                } else {
                    tag = 2;
                }
            }
            6 => {
                if index < 0 {
                    tag = 2;
                } else {
                    model.resize(index as usize, value);
                }
            }
            7 => {
                if index < 0 {
                    tag = 2;
                } else {
                    model.truncate(index as usize);
                }
            }
            8 => {
                if index < 0 {
                    tag = 3;
                } else if index == i32::MAX {
                    tag = 4;
                }
            }
            9 => {}
            10 => model.reverse(),
            11 => model.sort_unstable(),
            12 => model.clear(),
            13 => model.extend([value, 0, value / 2]),
            14 => model.extend(model.clone()),
            15 => removed = model.last().copied(),
            16 => {
                if valid {
                    removed = Some(model[index as usize]);
                }
            }
            17 => {
                model.sort_unstable();
                removed = Some(
                    model
                        .iter()
                        .position(|n| *n == value)
                        .map_or(-1, |i| i as i32),
                );
            }
            18 => model.clear(),
            _ => unreachable!(),
        }
        if let Some(value) = removed {
            tag = 1;
            answer = value;
        }
        let mut row = vec![tag, answer, model.len() as i32];
        row.extend_from_slice(&model);
        expected.push(row);
    }
    assert!(covered.into_iter().all(|hit| hit));
    input.write_bytes(&data);
    let output = common::process_output_with_timeout(
        "vector model with complete state after every edit",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        std::time::Duration::from_secs(10),
    );
    checked(&output, 0);
    let actual: Vec<Vec<i32>> = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_ascii_whitespace()
                .map(|value| value.parse().unwrap())
                .collect()
        })
        .collect();
    assert_eq!(actual.len(), expected.len());
    for (step, (actual, expected)) in actual.iter().zip(&expected).enumerate() {
        assert_eq!(actual, expected, "seed=0x7ec02026 step={step}");
    }
}

#[test]
fn checked_indexing_panics_for_empty_negative_and_past_end_indices() {
    let exe = fixture("alloc_vec_at_bounds");
    for arguments in [vec![], vec!["negative"], vec!["past", "end"]] {
        use std::os::unix::process::ExitStatusExt;
        let output = common::signal_process_output_with_timeout(
            "vector bounds panic",
            Command::new(exe.path()).args(arguments),
        );
        assert_eq!(output.status.signal(), Some(4), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
}
