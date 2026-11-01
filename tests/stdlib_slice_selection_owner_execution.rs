//! Generic shallow-owner selection and finite adversarial comparison growth.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/slice_selection_owners/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("slice selection owners/scale", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("slice selection {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_slice_selection", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}

fn mappings(events: &str, expected: usize, expected_phases: usize, records_retire_last: bool) {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut mappings = 0;
    let mut releases = Vec::new();
    let mut pure = false;
    let mut phases = 0;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
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
        assert!(!pure, "selection/comparator reached a host service: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "cleanup checkpoint precedes process exit: {events}");
            exits += 1;
            continue;
        }
        assert!(
            !done,
            "only process exit follows completed cleanup: {events}"
        );
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
                live.insert(address.to_owned(), (mappings, size)).is_none(),
                "duplicate live owner: {events}"
            );
            mappings += 1;
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
            assert!(
                !records_retire_last && arguments.ends_with(", 24") && result(line) == "24",
                "exact finite scale report: {events}"
            );
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(done && !pure && live.is_empty(), "{events}");
    assert_eq!(
        (entries, exits, mappings, releases.len(), phases),
        (1, 1, expected, expected, expected_phases),
        "{events}"
    );
    if records_retire_last {
        assert_eq!(
            releases.last(),
            Some(&0),
            "all nested owners retire before record backing: {events}"
        );
    }
}

fn run(name: &str, phases: usize, owners: usize) -> Vec<u8> {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_slice_selection", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "slice selection finite native lifecycle",
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    let mut expected = b"Pp".repeat(phases);
    expected.push(b'D');
    assert_eq!(output.stderr, expected, "{output:?}\n{events}");
    mappings(&events, owners, phases, name == "owners");
    output.stdout
}

#[test]
fn generic_selection_preserves_nested_owners_zero_sizes_and_selected_aliases() {
    assert!(run("owners", 5, 57).is_empty());
}

fn key(index: usize, size: usize, family: usize) -> i32 {
    match family {
        0 => index as i32,
        1 => (size - 1 - index) as i32,
        2 => (index % 8) as i32,
        3 => index.min(size - 1 - index) as i32,
        4 => ((index * 37) % 97) as i32,
        5 => ((index * 40503 + 17) % size) as i32,
        _ => unreachable!(),
    }
}

#[test]
fn selection_adversarial_scale_preserves_rank_permutation_and_linear_comparison_ceiling() {
    let output = run("scale", 180, 2);
    assert_eq!(output.len(), 180 * 24);
    let mut seen = BTreeSet::new();
    let mut maximum = [0.0_f64; 2];
    for record in output.chunks_exact(24) {
        let words: Vec<i32> = record
            .chunks_exact(4)
            .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        let [size, family, nth, mode, calls, selected]: [i32; 6] = words.try_into().unwrap();
        assert!([257, 4096, 65536].contains(&size));
        assert!((0..6).contains(&family) && (0..2).contains(&mode));
        assert!([0, 1, size / 2, size - 2, size - 1].contains(&nth));
        assert!(
            seen.insert((size, family, nth, mode)),
            "duplicate scale observation"
        );
        let mut expected: Vec<_> = (0..size as usize)
            .map(|index| key(index, size as usize, family as usize))
            .collect();
        expected.sort_unstable();
        assert_eq!(
            selected, expected[nth as usize],
            "independently sorted rank size={size} family={family} nth={nth} mode={mode}"
        );
        let ceiling = if mode == 0 { 100 } else { 200 };
        assert!(
            calls > 0 && calls <= ceiling * size,
            "finite linear ceiling size={size} family={family} nth={nth} mode={mode} calls={calls}"
        );
        maximum[mode as usize] = maximum[mode as usize].max(calls as f64 / size as f64);
    }
    assert_eq!(seen.len(), 180);
    eprintln!(
        "slice-selection-scale cases=180 sizes=257,4096,65536 families=6 ranks=5 APIs=2 max_custom_per_n={} max_natural_lt_per_n={}",
        maximum[0], maximum[1]
    );
}
