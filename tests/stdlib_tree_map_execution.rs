#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
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
    let exe = common::TempArtifact::new("laniusc_tree_map", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("tree map", command)
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
fn tree_map_contracts_execute() {
    for name in ["tree_map_basic", "tree_map_types"] {
        let exe = fixture(name);
        let output = run(&mut Command::new(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn mixed_edits_and_ranges_match_an_independent_ordered_map() {
    let exe = fixture("tree_map_model");
    let input = common::TempArtifact::new("laniusc_tree_map", "model_input", None);
    let mut seed = 0x7aee_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut model = std::collections::BTreeMap::<i32, i32>::new();
    let mut data = Vec::new();
    let mut expected = Vec::new();
    let mut covered = [false; 20];
    for step in 0..6000 {
        let mut op = (random() % 20) as u8;
        if step % 19 < 9 {
            op = (step % 2) as u8;
        }
        if step % 257 == 0 {
            op = 14;
        }
        let mut key = (random() % 68) as i32 - 2;
        let mut value = random() as i32;
        if step % 11 == 0 {
            value = i32::MIN;
        }
        if step % 17 == 0 {
            value = i32::MAX;
        }
        if op == 11 {
            value = (random() % 70) as i32 - 3;
        }
        if op == 8 {
            key = match step % 5 {
                0 => -1,
                1 => i32::MAX,
                _ => (random() % 160) as i32,
            };
        }
        covered[op as usize] = true;
        data.push(op);
        data.extend_from_slice(&key.to_le_bytes());
        data.extend_from_slice(&value.to_le_bytes());
        let mut tag = 0;
        let mut answer = 0;
        let mut returned_key = 0;
        let mut found = None;
        let mut range = Vec::<(i32, i32)>::new();
        match op {
            0 | 1 => found = model.insert(key, value).map(|old| (key, old)),
            2 => found = model.remove_entry(&key),
            3 => found = model.get_key_value(&key).map(|(&k, &v)| (k, v)),
            4 => {
                tag = 2;
                answer = i32::from(model.contains_key(&key));
            }
            5 => found = model.pop_first(),
            6 => found = model.pop_last(),
            7 | 14 => model.clear(),
            8 => {
                if key < 0 {
                    tag = 3;
                } else if key == i32::MAX {
                    tag = 4;
                }
            }
            9 | 17 => {}
            10 | 18 => found = model.first_key_value().map(|(&k, &v)| (k, v)),
            11 => {
                if key > value {
                    tag = 7;
                } else {
                    range = model.range(key..value).map(|(&k, &v)| (k, v)).collect();
                }
            }
            12 => found = model.range(key..).next().map(|(&k, &v)| (k, v)),
            13 => {
                found = model
                    .range((std::ops::Bound::Excluded(key), std::ops::Bound::Unbounded))
                    .next()
                    .map(|(&k, &v)| (k, v))
            }
            15 => {
                model.clear();
                model.extend([(key, value), (key + 1, value / 2), (key + 2, 0)]);
            }
            16 => tag = 6,
            19 => found = model.last_key_value().map(|(&k, &v)| (k, v)),
            _ => unreachable!(),
        }
        if let Some((k, v)) = found {
            tag = 1;
            returned_key = k;
            answer = v;
        }
        let mut row = vec![tag, returned_key, answer, range.len() as i32];
        for (k, v) in range {
            row.extend([k, v]);
        }
        row.push(model.len() as i32);
        for (&k, &v) in &model {
            row.extend([k, v]);
        }
        expected.push(row);
    }
    assert!(covered.into_iter().all(|hit| hit));
    input.write_bytes(&data);
    let output = common::process_output_with_timeout(
        "ordered map command model",
        Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
        std::time::Duration::from_secs(10),
    );
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
        assert_eq!(actual, expected, "seed=0x7aee2026 step={step}");
    }
}

#[test]
fn every_tree_map_allocation_failure_preserves_contents_capacity_and_cursors() {
    let exe = fixture("tree_map_failure");
    let trace = common::TempArtifact::new("laniusc_tree_map", "failure_trace", None);
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
    assert!(allocations >= 12, "exercise each allocation path");
    for when in 1..=allocations {
        execute(Some(when));
    }
}

#[test]
fn adversarial_orders_keep_logarithmic_searches_and_reuse_nodes() {
    let exe = fixture("tree_map_workload");
    for mode in 0..3 {
        let trace = common::TempArtifact::new("laniusc_tree_map", "workload_trace", None);
        let output = common::process_output_with_timeout(
            "balanced tree workload",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=2+",
                ])
                .arg(exe.path())
                .args(std::iter::repeat("order").take(mode)),
            std::time::Duration::from_secs(5),
        );
        checked(&output, 0);
        let comparisons: u64 = std::str::from_utf8(&output.stdout)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(comparisons > 0 && comparisons < 10_000_000);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("INJECTED"), "{events}");
        assert_eq!(freed(&events), 1);
    }
}

#[test]
fn empty_owners_and_invalid_requests_do_not_allocate() {
    let exe = fixture("tree_map_empty");
    let trace = common::TempArtifact::new("laniusc_tree_map", "empty_trace", None);
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
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

fn word_reference(input: &[u8], range: Option<(&[u8], &[u8])>) -> Vec<u8> {
    let mut counts = std::collections::BTreeMap::<Vec<u8>, i32>::new();
    for word in input
        .split(|byte| matches!(byte, 9..=13 | 32))
        .filter(|word| !word.is_empty())
    {
        *counts.entry(word.to_vec()).or_default() += 1;
    }
    let mut output = Vec::new();
    for (word, count) in counts {
        if let Some((lower, upper)) = range {
            if word.as_slice() < lower || word.as_slice() >= upper {
                continue;
            }
        }
        output.extend(word);
        output.push(b'\t');
        output.extend(count.to_string().as_bytes());
        output.push(b'\n');
    }
    output
}

#[test]
fn sorted_word_counts_match_a_reference_and_enforce_limits() {
    use std::{ffi::OsString, os::unix::ffi::OsStringExt};
    let exe = executable("sample_programs/word_counts.lani");
    let data = common::TempArtifact::new("laniusc_tree_map", "words", None);
    let words = ["alpha", "Z", "é", "😀", "a\0b", "\u{a0}", "中", "omega"];
    let mut generated = Vec::new();
    for i in 0..2048 {
        generated.extend_from_slice(words[(i * 37 + i / 7 + 3) % words.len()].as_bytes());
        generated.push([9, 10, 11, 12, 13, 32][i % 6]);
    }
    let mut cases: Vec<(Vec<u8>, Vec<OsString>, i32, Vec<u8>)> = Vec::new();
    for input in [
        Vec::new(),
        b" \t\n\x0b\x0c\r".to_vec(),
        b"z a a b c a".to_vec(),
        "a\0b a\0b é 😀 中".as_bytes().to_vec(),
        generated,
    ] {
        let expected = word_reference(&input, None);
        cases.push((input.clone(), vec![], 0, expected));
        let expected = word_reference(&input, Some((b"b", "😀".as_bytes())));
        cases.push((input.clone(), vec!["b".into(), "😀".into()], 0, expected));
        cases.push((input, vec!["a".into(), "a".into()], 0, vec![]));
    }
    cases.extend([
        (b"\xff".to_vec(), vec![], 2, vec![]),
        (b"\xf0\x9f".to_vec(), vec![], 2, vec![]),
        (b"a".to_vec(), vec!["z".into(), "a".into()], 2, vec![]),
        (b"a".to_vec(), vec!["only".into()], 2, vec![]),
        (
            b"a".to_vec(),
            vec![OsString::from_vec(vec![255]), "z".into()],
            2,
            vec![],
        ),
        (
            b"a".to_vec(),
            vec!["a".repeat(257).into(), "z".into()],
            2,
            vec![],
        ),
        (vec![b' '; 1048576], vec![], 0, vec![]),
        (vec![b' '; 1048577], vec![], 2, vec![]),
    ]);
    let mut distinct = Vec::new();
    for i in 0..65536 {
        distinct.extend(format!("k{i:05} ").as_bytes());
    }
    let expected = word_reference(&distinct, None);
    cases.push((distinct.clone(), vec![], 0, expected));
    distinct.extend(b"overflow");
    cases.push((distinct, vec![], 2, vec![]));
    for (index, (input, args, status, expected)) in cases.into_iter().enumerate() {
        data.write_bytes(&input);
        let mut command = Command::new(exe.path());
        command.args(args).stdin(std::process::Stdio::from(
            std::fs::File::open(data.path()).unwrap(),
        ));
        let output = common::process_output_with_timeout(
            format!("word counts case {index}"),
            &mut command,
            if input.len() > 65536 {
                std::time::Duration::from_secs(5)
            } else {
                std::time::Duration::from_millis(500)
            },
        );
        checked(&output, status);
        assert_eq!(output.stdout, expected, "case={index}");
    }
}

#[test]
fn word_count_allocation_and_io_failures_release_every_allocation() {
    let exe = executable("sample_programs/word_counts.lani");
    let input = b"h g f e d c b a a c e h";
    let expected = word_reference(input, None);
    let data = common::TempArtifact::new("laniusc_tree_map", "fault_words", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tree_map", "word_fault_trace", None);
    let execute = |injection: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(ref injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command.arg(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(data.path()).unwrap(),
        )));
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, expected);
        } else if status == 4 {
            assert!(output.stdout.is_empty());
        } else {
            assert!(expected.starts_with(&output.stdout));
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        events
    };
    let baseline = execute(None, 0);
    let allocations = baseline.lines().filter(|l| l.starts_with("mmap(")).count();
    assert!(allocations >= 3);
    for when in 1..=allocations {
        execute(Some(format!("mmap:error=ENOMEM:when={when}+")), 4);
    }
    for call in ["read", "write"] {
        let count = baseline
            .lines()
            .filter(|l| l.starts_with(&format!("{call}(")))
            .count();
        assert!(count > 0);
        for when in 1..=count {
            execute(Some(format!("{call}:error=EIO:when={when}+")), 3);
        }
        execute(Some(format!("{call}:error=EINTR:when=1")), 0);
    }
    execute(Some("write:retval=0:when=1".into()), 3);
}

#[test]
fn sorted_bulk_construction_has_linear_comparison_cost() {
    let exe = fixture("tree_map_bulk");
    for repeated in [false, true] {
        let trace = common::TempArtifact::new("laniusc_tree_map", "bulk_trace", None);
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=3+",
            ])
            .arg(exe.path());
        if repeated {
            command.arg("insert");
        }
        let output = common::process_output_with_timeout(
            "sorted bulk tree",
            &mut command,
            std::time::Duration::from_secs(5),
        );
        checked(&output, 0);
        let comparisons: usize = std::str::from_utf8(&output.stdout)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        if repeated {
            assert!(comparisons > 65535 && comparisons <= 2 * 65536 * 17);
        } else {
            assert_eq!(comparisons, 65535);
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("INJECTED"), "{events}");
        assert_eq!(freed(&events), 2);
    }
}
