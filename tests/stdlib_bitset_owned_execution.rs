#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
};
fn fixture(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_bitset", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
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
fn owned_and_counted_view_contracts_execute_with_native_and_raw_strides() {
    for name in [
        "bitset_owned_smoke",
        "bitset_view_contracts",
        "bitset_owned_boundaries",
    ] {
        let exe = fixture(name);
        let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
        checked(&output);
        assert!(output.stdout.is_empty());
    }
}
#[test]
fn every_observed_bitset_allocation_denial_preserves_owner_contents_and_views() {
    let exe = fixture("bitset_owned_failure");
    let trace = common::TempArtifact::new("laniusc_bitset", "allocation_trace", None);
    let execute = |when: Option<(usize, bool)>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some((when, persistent)) = when {
            let suffix = if persistent { "+" } else { "" };
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}{suffix}"));
        }
        let output = common::short_process_output_with_timeout(
            "bitset allocation denial",
            command.arg(exe.path()),
        );
        checked(&output);
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
    assert!(
        allocations >= 10,
        "each fallible allocation path is exercised: {allocations}"
    );
    for when in 1..=allocations {
        execute(Some((when, false)));
        execute(Some((when, true)));
    }
}
#[test]
fn stateful_edits_match_an_independent_boolean_array_model() {
    let exe = fixture("bitset_owned_model");
    let input = common::TempArtifact::new("laniusc_bitset", "model_input", None);
    let mut seed = 0xb175_e726_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut model = Vec::<bool>::new();
    let mut data = Vec::new();
    let mut expected = Vec::new();
    let mut coverage = [false; 20];
    for step in 0..4500 {
        let mut op = (random() % 20) as u8;
        let mut a = (random() % (model.len() as u32 + 5)) as i32 - 2;
        let mut b = (random() % (model.len() as u32 + 5)) as i32 - 2;
        let mut c = (random() % (model.len() as u32 + 5)) as i32 - 2;
        if step % 23 == 0 {
            op = 0;
            a = [0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 257][step / 23 % 12];
            b = (random() % 2) as i32;
        }
        if op == 0 && step % 23 != 0 {
            a = (random() % 260) as i32 - 2;
        }
        if op == 6 || op == 7 || op == 8 || op == 11 {
            if step % 3 != 0 {
                a = a.max(0).min(model.len() as i32);
                b = b.max(a).min(model.len() as i32);
                if op == 11 {
                    c = (random() % (model.len() as u32 - (b - a) as u32 + 1)) as i32;
                }
            }
        }
        if op == 15 || op == 19 {
            a = model.len() as i32;
            if step % 5 == 0 {
                a += 1;
            }
            b = (random() % 100) as i32;
            c = (random() % 4) as i32;
        }
        if op == 9 || op == 10 {
            a = [-1, 0, 1, 7, 31, 32, 33, 63, 64, 65, 300][step % 11];
        }
        if op == 1 && model.len() > 270 {
            op = 2;
        }
        coverage[op as usize] = true;
        data.push(op);
        for arg in [a, b, c] {
            data.extend_from_slice(&arg.to_le_bytes());
        }
        let (mut tag, mut answer) = (0, 0);
        let valid_index = a >= 0 && (a as usize) < model.len();
        match op {
            0 => {
                if a < 0 {
                    tag = 2;
                } else {
                    model.resize(a as usize, b != 0);
                }
            }
            1 => model.push(b != 0),
            2 => {
                if let Some(bit) = model.pop() {
                    tag = 1;
                    answer = i32::from(bit);
                }
            }
            3 | 4 => {
                if valid_index {
                    tag = 1;
                    answer = i32::from(model[a as usize]);
                    model[a as usize] = if op == 3 { b != 0 } else { !model[a as usize] };
                } else {
                    tag = 2;
                }
            }
            5 => model.fill(b != 0),
            6..=8 => {
                if a < 0 || b < a || b as usize > model.len() {
                    tag = 2;
                } else {
                    for bit in &mut model[a as usize..b as usize] {
                        *bit = match op {
                            6 => true,
                            7 => false,
                            _ => !*bit,
                        };
                    }
                }
            }
            9 | 10 => {
                if a < 0 {
                    tag = 2;
                } else {
                    let old = model.clone();
                    for (i, bit) in model.iter_mut().enumerate() {
                        let source = if op == 9 {
                            i.checked_sub(a as usize)
                        } else {
                            i.checked_add(a as usize)
                        };
                        *bit = source.and_then(|j| old.get(j)).copied().unwrap_or(false);
                    }
                }
            }
            11 => {
                if a < 0
                    || b < a
                    || b as usize > model.len()
                    || c < 0
                    || c as usize > model.len() - (b - a) as usize
                {
                    tag = 2;
                } else {
                    model.copy_within(a as usize..b as usize, c as usize);
                }
            }
            12 => {
                if a < 0 {
                    tag = 2;
                }
            }
            13 | 14 => {}
            15 | 19 => {
                if a as usize != model.len() {
                    tag = 2;
                } else {
                    let other = (0..a).map(|i| (i * 13 + b) % 7 < 3).collect::<Vec<_>>();
                    if op == 19 {
                        tag = 1;
                        answer = i32::from(model.iter().zip(&other).all(|(l, r)| !l || *r))
                            + 2 * i32::from(model.iter().zip(&other).all(|(l, r)| !(*l && *r)));
                    } else {
                        for (left, right) in model.iter_mut().zip(other) {
                            *left = match c {
                                0 => *left || right,
                                1 => *left && right,
                                2 => *left && !right,
                                _ => *left ^ right,
                            };
                        }
                    }
                }
            }
            16 => {
                if valid_index {
                    tag = 1;
                    answer = i32::from(model[a as usize]);
                }
            }
            17 => model.clear(),
            18 => {
                if a < 0 || a as usize > model.len() {
                    tag = 2;
                } else {
                    tag = 1;
                    let find = |value| {
                        model
                            .iter()
                            .enumerate()
                            .skip(a as usize)
                            .find(|(_, bit)| **bit == value)
                            .map_or(-1, |(i, _)| i as i32)
                    };
                    answer = find(true) * 10000 + find(false);
                }
            }
            _ => unreachable!(),
        }
        let mut row = vec![
            tag,
            answer,
            model.len() as i32,
            model.iter().filter(|b| **b).count() as i32,
            model.iter().position(|b| *b).map_or(-1, |i| i as i32),
            model.iter().rposition(|b| *b).map_or(-1, |i| i as i32),
        ];
        row.extend(model.chunks(32).map(|bits| {
            bits.iter()
                .enumerate()
                .fold(0_u32, |word, (i, bit)| word | (u32::from(*bit) << i)) as i32
        }));
        expected.push(row);
    }
    assert!(coverage.into_iter().all(|hit| hit));
    input.write_bytes(&data);
    let output = common::process_output_with_timeout(
        "stateful bitset differential seed=0xb175e726",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        std::time::Duration::from_secs(15),
    );
    checked(&output);
    let actual = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_ascii_whitespace()
                .map(|n| n.parse::<i32>().unwrap())
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    assert_eq!(actual.len(), expected.len());
    for (step, (actual, expected)) in actual.iter().zip(&expected).enumerate() {
        assert_eq!(
            actual,
            expected,
            "seed=0xb175e726 step={step} command={:?}",
            &data[step * 13..step * 13 + 13]
        );
    }
}

#[test]
fn overstated_physical_backing_traps_at_the_native_slice_boundary() {
    let exe = fixture("bitset_view_physical_bounds");
    let output = common::short_process_output_with_timeout(
        "bitset physical backing",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(101), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
}
#[test]
fn million_bit_dense_and_sparse_workloads_execute_without_leaks() {
    let exe = fixture("bitset_owned_large");
    let trace = common::TempArtifact::new("laniusc_bitset", "large_trace", None);
    let output = common::process_output_with_timeout(
        "million bit workloads",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        std::time::Duration::from_secs(15),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert_eq!(freed(&std::fs::read_to_string(trace.path()).unwrap()), 3);
}
