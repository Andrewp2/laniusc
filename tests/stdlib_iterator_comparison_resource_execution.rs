//! Borrowed comparison owners, guarded decisions and finite linear work.
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
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_comparison_resources")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("iterator comparison resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("iterator comparison {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_iter_compare_resources", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.rsplit_once('=')
        .unwrap()
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap()
        .split_once('(')
        .unwrap()
        .1
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
fn effects(events: &str, mappings: usize, phases: usize, report_size: usize, guard: bool) {
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut allocated = 0;
    let mut released = Vec::new();
    let mut pure = false;
    let mut completed = 0;
    let mut done = false;
    let (mut entries, mut exits, mut protections, mut reports) = (0, 0, 0, 0);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            assert!(!done, "{events}");
            if line.contains("\"P\", 1)") {
                assert!(
                    !pure && allocated == mappings && protections == usize::from(guard),
                    "all backing reserved before pure work: {events}"
                );
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure, "{events}");
                pure = false;
                completed += 1;
            } else {
                assert!(
                    line.contains("\"D\", 1)") && !pure && live.is_empty(),
                    "all owners retired before D: {events}"
                );
                done = true;
            }
            continue;
        }
        assert!(
            !pure,
            "comparison/source/callback reached a host service: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows D: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("mmap(") {
            assert_eq!(
                completed, 0,
                "no operation or resumed source allocates: {events}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields[0], "NULL", "{events}");
            let bytes: usize = fields[1].parse().unwrap();
            assert!(bytes > 0, "{events}");
            let value = result(line);
            let pointer = value.split_whitespace().next().unwrap();
            assert!(
                pointer.starts_with("0x") && !value.contains("INJECTED"),
                "actual successful setup backing: {events}"
            );
            assert!(
                live.insert(address(pointer), (bytes, allocated)).is_none(),
                "distinct live owner: {events}"
            );
            allocated += 1;
        } else if line.starts_with("mprotect(") {
            assert!(
                guard && completed == 0 && protections == 0 && live.len() == 1,
                "{events}"
            );
            let (&pointer, &(bytes, _)) = live.iter().next().unwrap();
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(bytes, 8192);
            assert_eq!(pointer % 4096, 0);
            assert_eq!(address(fields[0]), pointer + 4096);
            assert_eq!(&fields[1..], &["4096", "PROT_NONE"]);
            assert_eq!(result(line), "0", "{events}");
            protections += 1;
        } else if line.starts_with("munmap(") {
            assert_eq!(
                completed, phases,
                "all owners remain live throughout comparisons: {events}"
            );
            let (pointer, bytes) = arguments(line).split_once(',').unwrap();
            let bytes: usize = bytes.trim().parse().unwrap();
            let (actual, id) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown/double release: {line}"));
            assert_eq!(bytes, actual, "exact owner extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            released.push(id);
        } else if line.starts_with("write(1,") {
            let bytes: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            assert_eq!(bytes, report_size, "{events}");
            assert_eq!(result(line), report_size.to_string(), "{events}");
            reports += 1;
            assert_eq!(
                reports, completed,
                "one independent observation after each pure phase: {events}"
            );
        } else {
            panic!("unexpected host effect: {line}");
        }
    }
    assert!(done && !pure && live.is_empty(), "{events}");
    assert_eq!(
        (allocated, released.len(), completed, reports, protections),
        (mappings, mappings, phases, phases, usize::from(guard)),
        "{events}"
    );
    assert_eq!((entries, exits), (1, 1), "{events}");
    assert_eq!(
        released.last(),
        Some(&0),
        "initial backing retires last: {events}"
    );
}
fn run(name: &str, mappings: usize, phases: usize, width: usize, guard: bool) -> Vec<Vec<i32>> {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_iter_compare_resources", "trace", None);
    let output = common::process_output_with_timeout(
        "iterator comparison finite resource lifecycle",
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(30),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "{name}: {output:?}\n{events}"
    );
    let mut markers = b"Pp".repeat(phases);
    markers.push(b'D');
    assert_eq!(output.stderr, markers, "{events}");
    effects(&events, mappings, phases, width * 4, guard);
    assert_eq!(output.stdout.len(), phases * width * 4);
    output
        .stdout
        .chunks_exact(width * 4)
        .map(|row| {
            row.chunks_exact(4)
                .map(|bytes| i32::from_le_bytes(bytes.try_into().unwrap()))
                .collect()
        })
        .collect()
}
#[test]
fn iterator_comparisons_borrow_nested_owners_and_recover_discarded_owning_items() {
    let rows = run("owners.lani", 28, 10, 9, false);
    let expected = [
        [1, 1, 7, 7, 6, 0, 0, 0, 0],
        [2, 1, 7, 7, 0, 0, 0, 0, 6],
        [3, 1, 6, 6, 0, 10, 0, 0, 0],
        [4, -1, 3, 3, 0, 0, 0, 0, 3],
        [5, 0, 7, 7, 0, 0, 6, 0, 0],
        [6, 2, 2, 2, 0, 0, 0, 0, 2],
        [7, 1, 7, 0, 0, 0, 0, 5, 0],
        [8, 1, 2, 2, 0, 0, 0, 0, 2],
        [9, 1, 7, 2, 0, 0, 0, 0, 3],
        [10, -1, 8, 3, 0, 0, 0, 0, 0],
    ];
    assert_eq!(
        rows,
        expected.iter().map(|row| row.to_vec()).collect::<Vec<_>>()
    );
    eprintln!(
        "iterator-comparison owners=12 nested-backings=24 total-mappings=28 exact-releases=28 pure-phases=10"
    );
}
#[test]
fn iterator_comparisons_guarded_short_circuits_zero_size_and_real_byte_strides_are_effect_free() {
    let rows = run("guards.lani", 1, 10, 5, true);
    let expected = [
        [1, 0, 1, 1, 0],
        [2, 1, 1, 1, 0],
        [3, -1, 1, 1, 0],
        [4, 0, 2, 0, 0],
        [5, 0, 2, 0, 1],
        [6, -1, 1, 1, 0],
        [7, 1, 4, 4, 0],
        [8, -1, 3, 3, 0],
        [9, 1, 4, 0, 0],
        [10, 0, 1, 1, 1],
    ];
    assert_eq!(
        rows,
        expected.iter().map(|row| row.to_vec()).collect::<Vec<_>>()
    );
    eprintln!(
        "iterator-comparison guards=10 zero-size/native-negative/packed-byte-strides mappings=1 protections=1 exact-releases=1"
    );
}
fn expected(length: i32, case: i32) -> [i32; 8] {
    let mid = length / 2;
    match case {
        0 => [
            length,
            case,
            1,
            length + 1,
            length + 1,
            length,
            length,
            length,
        ],
        1 | 2 => [
            length,
            case,
            0,
            length + 1,
            length + 1,
            length,
            length,
            length,
        ],
        3 => [length, case, 1, length + 1, 0, length - 1, length, 0],
        4 => [length, case, 0, 1, 1, 1, 1, 1],
        5 => [
            length,
            case,
            -1,
            mid + 1,
            mid + 1,
            mid + 1,
            mid + 1,
            mid + 1,
        ],
        6 => [length, case, -1, length, length, length, length, length],
        7 => [length, case, 2, mid + 1, mid + 1, mid + 1, mid + 1, mid + 1],
        8 => [
            length,
            case,
            1,
            length,
            length,
            length - 1,
            length,
            length - 1,
        ],
        9 => [length, case, 0, length, 0, length - 1, length, 0],
        10 => [length, case, 0, 2, 0, 1, 2, 0],
        _ => unreachable!(),
    }
}
#[test]
fn iterator_comparisons_large_sequences_use_linear_pulls_and_callbacks() {
    let rows = run("scale.lani", 2, 33, 8, false);
    let mut index = 0;
    for length in [257, 4096, 65536] {
        for case in 0..11 {
            assert_eq!(
                rows[index],
                expected(length, case).to_vec(),
                "length={length} case={case}"
            );
            index += 1;
        }
    }
    eprintln!(
        "iterator-comparison scale-cases=33 lengths=257/4096/65536 callbacks<=n pulls<=n+1-per-source mappings=2 exact-releases=2"
    );
}
