//! Borrowed segmentation retains scalar and nested-owner backing until explicit cleanup.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_slice_segmentation/resources")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("slice segmentation resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("segmentation resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_slice_segmentation_resources", name, None);
    file.write_bytes(bytes); // Shared writer checks every x86 jump before execution.
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
#[derive(Debug, Default)]
struct Effects {
    allocations: usize,
    releases: usize,
    phases: usize,
    output_bytes: usize,
}
fn effects(events: &str, stderr: &[u8], cycles: &[Vec<usize>], nested: bool) -> Effects {
    let mut observed = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut markers = Vec::new();
    let mut allocation_sizes = Vec::new();
    let mut release_order = Vec::new();
    let (mut cycle, mut entries, mut exits, mut cycle_phases) = (0, 0, 0, 0);
    let (mut active, mut started, mut pure, mut cleanup, mut done) =
        (false, false, false, false, false);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"APpCED"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(
                        !active && !pure && live.is_empty() && cycle < cycles.len(),
                        "{events}"
                    );
                    active = true;
                    started = false;
                    cleanup = false;
                    cycle_phases = 0;
                    allocation_sizes.clear();
                    release_order.clear();
                }
                b'P' => {
                    assert!(active && !pure && !cleanup, "{events}");
                    assert_eq!(
                        allocation_sizes, cycles[cycle],
                        "all backing reserved before borrowed work: {events}"
                    );
                    assert_eq!(live.len(), cycles[cycle].len(), "{events}");
                    started = true;
                    pure = true;
                }
                b'p' => {
                    assert!(pure && live.len() == cycles[cycle].len(), "{events}");
                    pure = false;
                    observed.phases += 1;
                    cycle_phases += 1;
                }
                b'C' => {
                    assert!(
                        active && started && !pure && !cleanup && live.len() == cycles[cycle].len(),
                        "all owners remain live until caller cleanup: {events}"
                    );
                    cleanup = true;
                }
                b'E' => {
                    assert!(
                        active && cleanup && !pure && live.is_empty(),
                        "all explicit releases precede E: {events}"
                    );
                    assert_eq!(cycle_phases, 5, "{events}");
                    let expected: Vec<usize> = if nested {
                        (1..cycles[cycle].len()).chain(std::iter::once(0)).collect()
                    } else {
                        vec![0]
                    };
                    assert_eq!(
                        release_order, expected,
                        "each nested payload retires once before outer descriptor storage: {events}"
                    );
                    active = false;
                    cycle += 1;
                }
                b'D' => {
                    assert!(
                        !active && !pure && live.is_empty() && cycle == cycles.len(),
                        "{events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "factory/predicate/cursor/source observation performed host work: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            continue;
        }
        assert!(
            !done,
            "only exit follows complete explicit retirement: {events}"
        );
        if line.starts_with("execve(") {
            assert!(!active && entries == 0, "{events}");
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("mmap(") {
            assert!(
                active && !started && !cleanup,
                "only initial source owners allocate: {events}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields.len(), 6, "{events}");
            assert_eq!(fields[0], "NULL", "{events}");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ],
                "{events}"
            );
            let size: usize = fields[1].parse().unwrap();
            let ordinal = allocation_sizes.len();
            assert_eq!(
                Some(&size),
                cycles[cycle].get(ordinal),
                "exact expected source reservation: {events}"
            );
            let returned = result(line);
            assert!(!returned.contains("INJECTED"), "{events}");
            let pointer = address(returned);
            let end = pointer.checked_add(size as u64).unwrap();
            assert!(
                live.iter()
                    .all(|(&start, &(_, length))| end <= start || pointer >= start + length as u64),
                "live backing extents cannot overlap: {events}"
            );
            assert!(
                live.insert(pointer, (ordinal, size)).is_none(),
                "distinct live allocation: {events}"
            );
            allocation_sizes.push(size);
            observed.allocations += 1;
        } else if line.starts_with("munmap(") {
            assert!(active && cleanup, "only caller cleanup releases: {events}");
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let size: usize = length.trim().parse().unwrap();
            let (ordinal, actual) = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown/duplicate owner release: {line}\n{events}"));
            assert_eq!(size, actual, "exact live address/extent release: {events}");
            assert_eq!(result(line), "0", "{events}");
            release_order.push(ordinal);
            observed.releases += 1;
        } else if line.starts_with("write(1,") {
            assert!(
                active && started && !cleanup && live.len() == cycles[cycle].len(),
                "all output observes still-live owners: {events}"
            );
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = result(line).parse().unwrap();
            assert!(used > 0 && used <= requested, "{events}");
            observed.output_bytes += used;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(done && !active && !pure && live.is_empty(), "{events}");
    assert_eq!((entries, exits), (1, 1), "{events}");
    assert_eq!(
        observed.allocations, observed.releases,
        "cleanup is observed, not inferred from process exit: {events}"
    );
    assert_eq!(stderr, markers, "native/trace marker agreement");
    observed
}
fn run(
    executable: &common::TempArtifact,
    cycles: &[Vec<usize>],
    nested: bool,
) -> (Vec<u8>, Effects) {
    let trace = common::TempArtifact::new("laniusc_slice_segmentation_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"])
        .arg(executable.path())
        .stdin(Stdio::null());
    let output = common::process_output_with_timeout(
        "borrowed segmentation finite owner lifecycle",
        &mut command,
        Duration::from_secs(25),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert!(
        !events.contains("INJECTED"),
        "no fictitious allocation-failure campaign: {events}"
    );
    let observed = effects(&events, &output.stderr, cycles, nested);
    assert_eq!(observed.output_bytes, output.stdout.len());
    (output.stdout, observed)
}
const PATTERN: [i32; 16] = [0, 0, 1, 1, 1, 2, 0, 3, 3, 0, 0, 4, 5, 5, 5, 0];
fn scalar_source(count: usize) -> Vec<u8> {
    (0..count + 7)
        .flat_map(|index| {
            let value = if (3..count + 3).contains(&index) {
                let at = index - 3;
                (at / 16 * 16) as i32 + PATTERN[at % 16]
            } else {
                -700 - index as i32
            };
            value.to_le_bytes()
        })
        .collect()
}
#[test]
fn slice_segmentation_preserves_live_scalar_backing_at_two_sizes_without_host_effects() {
    let executable = executable("scalars.lani");
    let (output, observed) = run(
        &executable,
        &[vec![(4096 + 7) * 4], vec![(65536 + 7) * 4]],
        false,
    );
    let mut expected = scalar_source(4096);
    expected.extend(scalar_source(65536));
    assert_eq!(
        output, expected,
        "complete selected backing and every guard survive all borrowed operations"
    );
    assert_eq!(
        (observed.phases, observed.allocations, observed.releases),
        (10, 2, 2)
    );
    eprintln!(
        "segmentation-scalar-owners elements=4096,65536 pure-phases=10 full-partitions-and-callbacks=true exact-maps=2 explicit-exact-releases=2"
    );
}
#[test]
fn slice_segmentation_borrows_real_nested_owner_handles_and_preserves_cleanup_authority() {
    let executable = executable("handles.lani");
    // alloc/vec.lani declares pointer/length/reserved. core/mem.lani's
    // size_of contract stores these scalar fields in three eight-byte words;
    // standalone packed i32 storage does not pack i32 fields inside records.
    let mut allocations = vec![23 * 3 * 8];
    allocations.extend(std::iter::repeat_n(8, 23));
    let (output, observed) = run(&executable, &[allocations], true);
    let expected: Vec<u8> = (0..23)
        .flat_map(|index| {
            (0..8).map(move |offset| match offset {
                0 => {
                    if (3..19).contains(&index) {
                        PATTERN[index - 3] as u8
                    } else {
                        255
                    }
                }
                1 => index as u8,
                _ => ((index * 29 + offset * 17) % 256) as u8,
            })
        })
        .collect();
    assert_eq!(
        output, expected,
        "all bytes of every distinct inner owner survive cursor and predicate retirement"
    );
    assert_eq!(
        (observed.phases, observed.allocations, observed.releases),
        (5, 24, 24)
    );
    eprintln!(
        "segmentation-nested-owners selected=16 guards=7 payloads=23 pure-phases=5 all-payload-bytes=184 exact-maps=24 explicit-inner-then-outer-releases=24"
    );
}
