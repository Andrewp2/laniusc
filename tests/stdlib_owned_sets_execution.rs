#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
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
    let exe = common::TempArtifact::new("laniusc_owned_sets", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

// Track both mapping address and requested length. Every owned allocation must
// be released exactly once, including partially built algebra destinations.
fn freed(events: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut count = 0;
    for line in events.lines() {
        if let Some(tail) = line.strip_prefix("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                let length = tail.split(',').nth(1).unwrap().trim().to_owned();
                assert!(live.insert(address, length).is_none(), "{events}");
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, rest) = tail.split_once(',').unwrap();
            let length = rest.split(')').next().unwrap().trim();
            assert!(line.ends_with(" = 0"), "{events}");
            assert_eq!(live.remove(address).as_deref(), Some(length), "{events}");
        }
    }
    assert!(live.is_empty(), "leaked allocations: {live:?}\n{events}");
    count
}

#[test]
fn owned_set_underlying_map_controls_execute() {
    for name in ["owned_sets_hash_map_control", "owned_sets_tree_map_control"] {
        let exe = fixture(name);
        checked(
            &common::short_process_output_with_timeout(name, &mut Command::new(exe.path())),
            0,
        );
    }
}

#[test]
fn set_contracts_generic_widths_and_explicit_key_owners_execute() {
    let contracts = fixture("owned_sets_contracts");
    checked(
        &common::short_process_output_with_timeout(
            "set contracts",
            &mut Command::new(contracts.path()),
        ),
        0,
    );
    let types = fixture("owned_sets_types");
    let trace = common::TempArtifact::new("laniusc_owned_sets", "owner_trace", None);
    let output = common::short_process_output_with_timeout(
        "set owner keys",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(types.path()),
    );
    checked(&output, 0);
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) > 0);
}

#[test]
fn mixed_set_operations_and_collisions_match_an_independent_model() {
    let exe = fixture("owned_sets_model");
    let input = common::TempArtifact::new("laniusc_owned_sets", "model_input", None);
    let mut seed = 0x5e72_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut model = BTreeMap::<i32, i32>::new();
    let right: BTreeMap<i32, i32> = (0..12).map(|key| (key, 1000 + key)).collect();
    let mut data = Vec::new();
    let mut expected = Vec::new();
    let mut covered = [false; 25];
    for step in 0..3200 {
        let mut op = (random() % 25) as u8;
        if step % 97 < 60 {
            op = (step % 2) as u8;
        }
        if step % 211 == 0 {
            op = 14;
        }
        if step < 25 {
            op = step as u8;
        }
        let mut key = (random() % 68) as i32 - 2;
        let mut stamp = random() as i32;
        if op == 8 {
            key = match step % 5 {
                0 => -1,
                1 => i32::MAX,
                _ => (random() % 160) as i32,
            };
        }
        if op == 11 {
            stamp = (random() % 70) as i32 - 3;
        }
        covered[op as usize] = true;
        data.push(op);
        data.extend_from_slice(&key.to_le_bytes());
        data.extend_from_slice(&stamp.to_le_bytes());
        let mut tag = 0;
        let mut answer = 0;
        let mut found = None;
        let mut query = BTreeMap::new();
        match op {
            0 => {
                if let std::collections::btree_map::Entry::Vacant(entry) = model.entry(key) {
                    entry.insert(stamp);
                } else {
                    found = Some((key, stamp));
                }
            }
            1 => found = model.insert(key, stamp).map(|old| (key, old)),
            2 => found = model.remove_entry(&key),
            3 | 10 => found = model.get_key_value(&key).map(|(&key, &stamp)| (key, stamp)),
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
            9 => {}
            11 => {
                if stamp < key {
                    tag = 7;
                } else {
                    query = model
                        .iter()
                        .filter(|(k, _)| **k >= key && **k < stamp)
                        .map(|(&k, &v)| (k, v))
                        .collect();
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
                query = model.clone();
                for (&k, &v) in &right {
                    query.entry(k).or_insert(v);
                }
            }
            16 => {
                query = model
                    .iter()
                    .filter(|(k, _)| right.contains_key(k))
                    .map(|(&k, &v)| (k, v))
                    .collect()
            }
            17 => {
                query = model
                    .iter()
                    .filter(|(k, _)| !right.contains_key(k))
                    .map(|(&k, &v)| (k, v))
                    .collect()
            }
            18 => {
                query = model
                    .iter()
                    .filter(|(k, _)| !right.contains_key(k))
                    .map(|(&k, &v)| (k, v))
                    .collect();
                for (&k, &v) in &right {
                    if !model.contains_key(&k) {
                        query.insert(k, v);
                    }
                }
            }
            19 | 20 => query = model.clone(),
            21 | 22 => {}
            23 => found = model.first_key_value().map(|(&k, &v)| (k, v)),
            24 => found = model.last_key_value().map(|(&k, &v)| (k, v)),
            _ => unreachable!(),
        }
        let mut returned = 0;
        if let Some((key, stamp)) = found {
            tag = 1;
            returned = key;
            answer = stamp;
        }
        let mut line = vec![tag, returned, answer, query.len() as i32];
        for (&k, &v) in &query {
            line.extend([k, v]);
        }
        line.push(model.len() as i32);
        for (&k, &v) in &model {
            line.extend([k, v]);
        }
        expected.push((op, line));
    }
    assert!(covered.into_iter().all(|covered| covered));
    input.write_bytes(data);
    let output = common::process_output_with_timeout(
        "set model",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        std::time::Duration::from_secs(3),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let text = String::from_utf8(output.stdout).unwrap();
    let lines: Vec<_> = text.lines().collect();
    assert_eq!(lines.len(), expected.len());
    for (step, (line, (op, expected))) in lines.into_iter().zip(expected).enumerate() {
        let actual: Vec<i32> = line
            .split_whitespace()
            .map(|value| value.parse().unwrap())
            .collect();
        assert_eq!(
            actual, expected,
            "step {step}, opcode {op}, seed 0x5e722026"
        );
    }
}

#[test]
fn every_set_allocation_failure_is_atomic_and_releases_partial_storage() {
    let exe = fixture("owned_sets_failure");
    let trace = common::TempArtifact::new("laniusc_owned_sets", "failure_trace", None);
    let traced = |when: Option<usize>| {
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
        command.arg(exe.path());
        let output =
            common::short_process_output_with_timeout("set allocation fault", &mut command);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, freed(&events))
    };
    let (baseline, allocations) = traced(None);
    checked(&baseline, 1);
    assert!(allocations > 0, "fault sweep must observe real allocations");
    for when in 1..=allocations {
        let (output, _) = traced(Some(when));
        assert_eq!(
            output.status.code(),
            Some(0),
            "allocation {when}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "allocation {when}: {output:?}"
        );
    }
}
