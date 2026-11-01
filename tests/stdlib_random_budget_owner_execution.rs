//! Shared random budgets preserve real shallow owners and strided byte prefixes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}

fn owners(events: &str) {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut acquired = 0;
    let mut releases = Vec::new();
    let mut pure = false;
    let mut phases = 0;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
    let mut reports = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !done, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !done, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(
                    line.contains("\"D\", 1)") && !pure && !done && live.is_empty(),
                    "{events}"
                );
                done = true;
            }
            continue;
        }
        assert!(!pure, "random operations reached a host service: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "cleanup checkpoint precedes process exit: {events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows complete cleanup: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = result(line).split_whitespace().next().unwrap();
            assert!(
                address.starts_with("0x"),
                "actual successful allocation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), (acquired, size)).is_none(),
                "duplicate live owner: {events}"
            );
            acquired += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let arguments = arguments.split_once(')').unwrap().0;
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (identity, extent) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(size, extent, "exact owner extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            releases.push(identity);
        } else if line.starts_with("write(1,") {
            let (arguments, _) = line.rsplit_once(')').unwrap();
            let length: usize = arguments
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            assert!(
                [64, 80].contains(&length),
                "bounded report extent: {events}"
            );
            assert_eq!(
                result(line).parse::<usize>().unwrap(),
                length,
                "complete actual report: {events}"
            );
            reports += 1;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(done && !pure && live.is_empty(), "{events}");
    assert_eq!(
        (entries, exits, acquired, releases.len(), phases, reports),
        (1, 1, 41, 41, 7, 5),
        "{events}"
    );
    assert_eq!(
        releases.last(),
        Some(&0),
        "nested owners retire before record backing: {events}"
    );
}

#[derive(Debug, PartialEq)]
enum End {
    Complete,
    DrawLimit,
    Host(i32),
}

// Independent host control uses exact u128 remainder of 2^64, rather than
// reproducing the library's wrapping-negation threshold expression.
fn shuffle(values: &mut [i32], script: &[Result<u64, i32>], budget: usize) -> (usize, usize, End) {
    let mut calls = 0;
    let mut completed = 0;
    for remaining in (2_usize..=8).rev() {
        loop {
            if calls == budget {
                return (completed, calls, End::DrawLimit);
            }
            let drawn = script[calls];
            calls += 1;
            let word = match drawn {
                Ok(value) => value,
                Err(error) => return (completed, calls, End::Host(error)),
            };
            let threshold = (1_u128 << 64) % remaining as u128;
            if (word as u128) < threshold {
                continue;
            }
            values.swap(remaining, 1 + (word % remaining as u64) as usize);
            completed += 1;
            break;
        }
    }
    (completed, calls, End::Complete)
}

fn words(bytes: &[u8]) -> Vec<i32> {
    assert_eq!(bytes.len() % 4, 0);
    bytes
        .chunks_exact(4)
        .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

fn expectations(bytes: &[u8]) {
    assert_eq!(bytes.len(), 3 * 64 + 2 * 80);
    let mut values: Vec<_> = (0..10).collect();
    assert_eq!(
        shuffle(&mut values, &[Ok(1), Ok(0)], 2),
        (1, 2, End::DrawLimit)
    );
    assert_eq!(values, [0, 1, 8, 3, 4, 5, 6, 7, 2, 9]);
    let mut expected = vec![1, 2, 0, 1, 0, 0];
    expected.extend_from_slice(&values);
    assert_eq!(
        words(&bytes[..64]),
        expected,
        "partial-error permutation and shared exhaustion"
    );
    assert_eq!(
        shuffle(&mut values, &[Ok(u64::MAX); 7], 7),
        (7, 7, End::Complete)
    );
    assert_eq!(values, [0, 3, 7, 5, 6, 1, 4, 8, 2, 9]);
    let mut expected = vec![2, 7, 0, 7, 0, 0];
    expected.extend_from_slice(&values);
    assert_eq!(
        words(&bytes[64..128]),
        expected,
        "complete shuffle spends its shared last draw"
    );
    let script = [Ok(6), Ok(0), Err(-90210), Ok(9)];
    let (completed, mut calls, ending) = shuffle(&mut values, &script, 4);
    assert_eq!((completed, calls, ending), (1, 3, End::Host(-90210)));
    assert_eq!(values, [0, 3, 7, 5, 6, 1, 4, 2, 8, 9]);
    let chosen = values[1 + (script[calls].unwrap() % 8) as usize];
    calls += 1;
    assert_eq!(chosen, 7);
    let mut expected = vec![3, calls as i32, 0, 1, chosen, 1];
    expected.extend_from_slice(&values);
    assert_eq!(
        words(&bytes[128..192]),
        expected,
        "source error after rejection and remaining-budget choose"
    );
    let prefix = 0xffee_ddcc_bbaa_9988_u64.to_le_bytes();
    for (index, report) in bytes[192..].chunks_exact(80).enumerate() {
        let mut expected = vec![6 + index as i32, 3, 0, 8];
        let mut destination = [211_i32; 16];
        for (at, byte) in prefix.into_iter().enumerate() {
            destination[2 + at] = byte as i32;
        }
        expected.extend_from_slice(&destination);
        assert_eq!(
            words(report),
            expected,
            "actual stride policy {index}, exact initialized prefix and guards"
        );
    }
}

#[test]
fn budgeted_random_operations_preserve_nested_owners_aliases_strides_and_exact_progress() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/random_budget_owners/owners.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("budgeted random owners", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("budgeted random owners: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_random_budget_owners", "executable", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_random_budget_owners", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "shared random budget owner lifecycle",
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    let mut markers = b"Pp".repeat(7);
    markers.push(b'D');
    assert_eq!(output.stderr, markers, "{output:?}\n{events}");
    owners(&events);
    expectations(&output.stdout);
    eprintln!(
        "random-budget-owners mappings=41 releases=41 pure-phases=7 owner-reports=3 stride-reports=2"
    );
}
