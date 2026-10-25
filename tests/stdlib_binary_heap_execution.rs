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
    let exe = common::TempArtifact::new("laniusc_heap", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("binary heap", command)
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
fn heap_contracts_execute_ordering_aliases_generic_payloads_and_zero_sized_values() {
    for name in [
        "binary_heap_contracts",
        "binary_heap_types",
        "binary_heap_views",
    ] {
        let exe = fixture(name);
        let output = run(&mut Command::new(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
    }
    let exe = fixture("binary_heap_zero_sized");
    let trace = common::TempArtifact::new("laniusc_heap", "zero_sized_trace", None);
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
        "zero-sized heaps must not allocate"
    );
}

fn random(seed: &mut u32) -> u32 {
    *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
    *seed
}

#[test]
fn mixed_heap_operations_match_a_sorted_multiset_in_both_orders() {
    let exe = fixture("binary_heap_model");
    let input = common::TempArtifact::new("laniusc_heap", "model_input", None);
    for maximum in [false, true] {
        let mut seed = 0x4ea9_2026_u32;
        let mut data = vec![u8::from(maximum)];
        let mut expected = Vec::<Vec<i32>>::new();
        let mut model = Vec::<i32>::new();
        for step in 0..6000 {
            // Explicit empty/boundary operations followed by a mixed workload.
            let mut op = (random(&mut seed) % 13) as u8;
            let mut value = random(&mut seed) as i32;
            if step % 17 < 8 {
                op = 0;
            }
            if step % 127 == 0 {
                op = 6;
            }
            if op == 8 && model.len() > 256 {
                op = 1;
            }
            if step % 11 == 0 {
                value = 7;
            }
            if step % 19 == 0 {
                value = i32::MIN;
            }
            if step % 23 == 0 {
                value = i32::MAX;
            }
            if op == 4 {
                value = match step % 5 {
                    0 => -1,
                    1 => i32::MAX,
                    _ => (random(&mut seed) % 129) as i32,
                };
            }
            data.push(op);
            data.extend_from_slice(&value.to_le_bytes());
            model.sort_unstable();
            if maximum {
                model.reverse();
            }
            let mut tag = 0;
            let mut answer = 0;
            let mut sorted = Vec::new();
            match op {
                0 => model.push(value),
                1 => {
                    if !model.is_empty() {
                        tag = 1;
                        answer = model.remove(0);
                    }
                }
                2 => {
                    if !model.is_empty() {
                        tag = 1;
                        answer = model[0];
                        model[0] = value;
                    }
                }
                3 => {
                    model.push(value);
                    model.sort_unstable();
                    if maximum {
                        model.reverse();
                    }
                    tag = 1;
                    answer = model.remove(0);
                }
                4 => {
                    if value < 0 {
                        tag = 2;
                    } else if value == i32::MAX {
                        tag = 3;
                    }
                }
                5 => {}
                6 => model.clear(),
                7 => model.extend([value, 0, value / 2]),
                8 => model.extend(model.clone()),
                9 => {
                    if !model.is_empty() {
                        tag = 1;
                        answer = model[0];
                    }
                }
                10 => {
                    sorted = std::mem::take(&mut model);
                    tag = 5;
                    answer = sorted.len() as i32;
                }
                11 => {}
                12 => model.clear(),
                _ => unreachable!(),
            }
            model.sort_unstable();
            if maximum {
                model.reverse();
            }
            let mut row = vec![
                tag,
                answer,
                model.len() as i32,
                i32::from(!model.is_empty()),
                model.first().copied().unwrap_or(0),
            ];
            row.extend(sorted);
            expected.push(row);
        }
        input.write_bytes(&data);
        let output =
            run(Command::new(exe.path())
                .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, 0);
        let actual: Vec<Vec<i32>> = std::str::from_utf8(&output.stdout)
            .unwrap()
            .lines()
            .map(|line| {
                line.split_ascii_whitespace()
                    .map(|n| n.parse().unwrap())
                    .collect()
            })
            .collect();
        assert_eq!(actual.len(), expected.len());
        for (step, (actual, expected)) in actual.iter().zip(&expected).enumerate() {
            assert_eq!(
                actual, expected,
                "seed=0x4ea92026 maximum={maximum} step={step}"
            );
        }
    }
}

#[test]
fn every_heap_allocation_failure_preserves_contents_capacity_and_views() {
    let exe = fixture("binary_heap_failure");
    let trace = common::TempArtifact::new("laniusc_heap", "failure_trace", None);
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
fn bulk_heap_construction_has_linear_comparison_cost() {
    let exe = fixture("binary_heap_workload");
    for repeated_push in [false, true] {
        let mut command = Command::new(exe.path());
        if repeated_push {
            command.arg("push");
        }
        let output = run(&mut command);
        checked(&output, 0);
        let comparisons: usize = std::str::from_utf8(&output.stdout)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        // Durable algorithmic bounds, without a wall-clock or exact-count gate.
        // The executable also checks all keys and the heap-order invariant.
        let bound = 65_536 * if repeated_push { 16 } else { 2 };
        assert!(comparisons > 0 && comparisons <= bound, "{comparisons}");
    }
}

fn report(k: usize, values: &[i64]) -> Vec<u8> {
    let mut values = values.to_vec();
    values.sort_unstable_by(|a, b| b.cmp(a));
    values
        .into_iter()
        .take(k)
        .map(|value| format!("{value}\n"))
        .collect::<String>()
        .into_bytes()
}
fn source(k: usize, values: &[i64]) -> Vec<u8> {
    format!(
        "{k}\n{}",
        values
            .iter()
            .map(|value| format!("{value}\n"))
            .collect::<String>()
    )
    .into_bytes()
}

#[test]
fn top_scores_program_executes_large_inputs_limits_and_resource_failures() {
    let exe = executable("sample_programs/top_scores.lani");
    let input = common::TempArtifact::new("laniusc_heap", "scores_input", None);
    let execute = |data: &[u8]| {
        input.write_bytes(data);
        run(Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
    };
    let mut seed = 0x7a12_2026_u32;
    let mut values = vec![i64::MIN, i64::MAX, 0, -1, 1, 42, 42];
    for _ in 0..8192 {
        let high = random(&mut seed) as u64;
        let low = random(&mut seed) as u64;
        values.push(((high << 32) | low) as i64);
    }
    for k in [0, 1, 2, 17, 256, 4096] {
        let output = execute(&source(k, &values));
        checked(&output, 0);
        assert_eq!(output.stdout, report(k, &values), "k={k}");
    }
    for data in [&b"3"[..], &b"0\n"[..], &b"2\n"[..]] {
        let output = execute(data);
        checked(&output, 0);
        assert!(output.stdout.is_empty());
    }
    let output = execute(b" 3\r\n +12 \r\n-3\n12");
    checked(&output, 0);
    assert_eq!(output.stdout, b"12\n12\n-3\n");
    for data in [
        &b""[..],
        &b"-1\n"[..],
        &b"4097\n"[..],
        &b"1\n\n"[..],
        &b"0\ninvalid\n"[..],
        &b"2\n9223372036854775808\n"[..],
        &b"2\n-9223372036854775809\n"[..],
        &b"2\n\xff\n"[..],
        &b"2\n1\n\n2\n"[..],
    ] {
        let output = execute(data);
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
    for count in [100000, 100001] {
        let values: Vec<i64> = (0..count).map(|i| (i % 29) - 14).collect();
        let output = execute(&source(32, &values));
        checked(&output, if count == 100000 { 0 } else { 2 });
        if count == 100000 {
            assert_eq!(output.stdout, report(32, &values));
        } else {
            assert!(output.stdout.is_empty());
        }
    }
    let mut exact = b"1\n".to_vec();
    exact.extend(vec![b' '; 1_048_572]);
    exact.extend_from_slice(b"1\n");
    assert_eq!(exact.len(), 1_048_576);
    let output = execute(&exact);
    checked(&output, 0);
    assert_eq!(output.stdout, b"1\n");
    exact.push(b' ');
    let output = execute(&exact);
    checked(&output, 2);
    assert!(output.stdout.is_empty());

    let values: Vec<i64> = (0..300).map(|i| (i * 37) % 101 - 50).collect();
    let expected = report(17, &values);
    input.write_bytes(&source(17, &values));
    let trace = common::TempArtifact::new("laniusc_heap", "scores_trace", None);
    let traced = |injection: Option<String>, status: i32, prefix: usize| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(injection) = &injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, status);
        assert_eq!(output.stdout, expected[..prefix], "{injection:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        freed(&events)
    };
    let allocations = traced(None, 0, expected.len());
    for when in 1..=allocations {
        traced(Some(format!("mmap:error=ENOMEM:when={when}+")), 4, 0);
    }
    let first_line = expected.iter().position(|byte| *byte == b'\n').unwrap() + 1;
    for (injection, status, prefix) in [
        ("read:error=EINTR:when=1", 0, expected.len()),
        ("read:error=EIO:when=2", 3, 0),
        ("read:error=EAGAIN:when=1", 3, 0),
        ("write:error=EIO:when=2", 3, first_line),
        ("write:error=EINTR:when=2", 0, expected.len()),
        ("write:retval=0:when=2", 3, first_line),
    ] {
        traced(Some(injection.to_owned()), status, prefix);
    }
}
