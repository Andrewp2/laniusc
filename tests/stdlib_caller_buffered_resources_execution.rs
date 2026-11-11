//! Actual caller owners, mixed nesting, and reached constructor recovery.
//! common::strace selects LANIUS_ALLOC=mmap: these are exact logical allocation
//! lifetimes in direct allocator mode, not guessed counts under normal pooling.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{collections::BTreeMap, fs, os::unix::fs::PermissionsExt, path::PathBuf};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_caller_buffered/resources");
    let entry = fixtures.join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let label = format!("caller-buffered resources {name}");
    let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_caller_buffered_resources", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[derive(Debug, PartialEq)]
enum Event {
    Allocate(usize),
    Denied(usize),
    // One-based attempt number; identity is resolved from the full address.
    Release(usize),
    Mark(u8),
    Output(usize),
}

fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}

fn observe(trace: &str) -> Vec<Event> {
    let mut events = Vec::new();
    let mut live = BTreeMap::<u64, (usize, u64)>::new();
    let mut attempt = 0;
    let mut pure = false;
    let mut output_phase = false;
    let mut launches = 0;
    let mut exits = 0;
    for line in trace.lines() {
        if line.starts_with("write(2,") {
            let marker = b"PpROD"
                .iter()
                .copied()
                .find(|byte| line.starts_with(&format!("write(2, \"{}\", 1)", *byte as char)))
                .unwrap_or_else(|| panic!("unknown marker: {line}\n{trace}"));
            assert_eq!(line.rsplit_once(" = ").unwrap().1.trim(), "1", "{trace}");
            match marker {
                b'P' => {
                    assert!(!pure && !output_phase, "{trace}");
                    pure = true;
                }
                b'p' => {
                    assert!(pure, "{trace}");
                    pure = false;
                }
                b'O' => {
                    assert!(!pure && !output_phase && live.len() == 2, "{trace}");
                    output_phase = true;
                }
                b'D' => {
                    assert!(!pure && live.is_empty(), "{trace}");
                    output_phase = false;
                }
                b'R' => assert!(!pure && !output_phase, "{trace}"),
                _ => unreachable!(),
            }
            events.push(Event::Mark(marker));
            continue;
        }
        assert!(
            !pure,
            "host effect during core I/O and handoff phase: {line}\n{trace}"
        );
        assert_eq!(exits, 0, "host effect after exit: {trace}");
        if line.starts_with("execve(") {
            assert!(events.is_empty() && launches == 0, "{trace}");
            assert!(line.ends_with("= 0"), "{trace}");
            launches += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            assert!(!output_phase, "{trace}");
            let (arguments, result) = arguments.rsplit_once(" = ").unwrap();
            let mut fields = arguments.trim_end().strip_suffix(')').unwrap().split(',');
            assert_eq!(fields.next().unwrap().trim(), "NULL", "{trace}");
            let size: usize = fields.next().unwrap().trim().parse().unwrap();
            assert!(size > 0, "{trace}");
            attempt += 1;
            let returned = result.split_whitespace().next().unwrap();
            if returned == "-1" {
                assert!(
                    result.contains("ENOMEM") && result.contains("INJECTED"),
                    "{trace}"
                );
                events.push(Event::Denied(size));
            } else {
                let base = address(returned);
                let end = base.checked_add(size as u64).unwrap();
                assert!(
                    base != 0
                        && live
                            .iter()
                            .all(|(&other, &(_, extent))| end <= other || other + extent <= base),
                    "{trace}"
                );
                assert!(
                    live.insert(base, (attempt, size as u64)).is_none(),
                    "{trace}"
                );
                events.push(Event::Allocate(size));
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.rsplit_once(" = ").unwrap();
            assert_eq!(result.trim(), "0", "{trace}");
            let (base, size) = arguments
                .trim_end()
                .strip_suffix(')')
                .unwrap()
                .split_once(',')
                .unwrap();
            let extent: u64 = size.trim().parse().unwrap();
            let (id, owned) = live
                .remove(&address(base))
                .unwrap_or_else(|| panic!("unknown/repeated release: {trace}"));
            assert_eq!(
                extent, owned,
                "release must match the complete allocation extent: {trace}"
            );
            events.push(Event::Release(id));
        } else if line.starts_with("write(1,") {
            assert!(output_phase && live.len() == 2, "{trace}");
            let written: usize = line.rsplit_once(" = ").unwrap().1.trim().parse().unwrap();
            assert!(written > 0, "{trace}");
            if let Some(Event::Output(total)) = events.last_mut() {
                *total += written;
            } else {
                events.push(Event::Output(written));
            }
        } else if line == "exit(0) = ?"
            || line == "exit_group(0) = ?"
            || line.starts_with("exit(0)")
            || line.starts_with("exit_group(0)")
        {
            assert!(
                !output_phase && live.is_empty() && events.last() == Some(&Event::Mark(b'D')),
                "{trace}"
            );
            exits += 1;
        } else {
            panic!("unexpected resource fixture host effect: {line}\n{trace}");
        }
    }
    assert!(!pure && !output_phase && live.is_empty(), "{trace}");
    assert_eq!((launches, exits), (1, 1), "{trace}");
    events
}

fn run(file: &common::TempArtifact, deny: Option<usize>, expected: &[Event], bytes: &[u8]) {
    let trace = common::TempArtifact::new("laniusc_caller_buffered_resources", "trace", None);
    let mut command = common::strace();
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = deny {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command.arg(file.path());
    let output = common::short_process_output_with_timeout(
        "caller-buffered resource lifecycle",
        &mut command,
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(output.stdout, bytes, "complete binary stream differs");
    let markers = expected
        .iter()
        .filter_map(|event| match event {
            Event::Mark(byte) => Some(*byte),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(output.stderr, markers, "{events}");
    assert_eq!(observe(&events), expected, "{events}");
}

#[test]
fn caller_heap_owner_survives_core_lifecycle_and_native_negative_stride_is_real() {
    use Event::*;
    let file = executable("heap_lifecycle");
    run(
        &file,
        None,
        &[
            Allocate(9),
            Allocate(12),
            Allocate(11),
            Mark(b'P'),
            Mark(b'p'),
            Release(3),
            Release(2),
            Release(1),
            Mark(b'D'),
        ],
        &[],
    );
}

fn mixed(name: &str, core_outer: bool) {
    use Event::*;
    let file = executable(name);
    let mut expected = Vec::new();
    let mut bytes = Vec::new();
    for (case, length) in [4096usize, 262144].into_iter().enumerate() {
        let base = case * 6;
        let sizes = if core_outer {
            [length, length, 11, 17, 11, 5]
        } else {
            [length, length, 15, 9, 7, 13]
        };
        expected.extend(sizes.into_iter().map(Allocate));
        expected.extend([Mark(b'P'), Mark(b'p')]);
        // Core outer scratch owners end before the owning inner wrappers.
        // Owning outer wrappers end before their borrowed core providers.
        let releases = if core_outer {
            [4, 3, 6, 5]
        } else {
            [6, 5, 4, 3]
        };
        expected.extend(releases.into_iter().map(|id| Release(base + id)));
        expected.extend([
            Mark(b'O'),
            Output(length),
            Release(base + 2),
            Release(base + 1),
            Mark(b'D'),
        ]);
        // Independent host oracle specifies the input, not buffering transitions.
        bytes.extend(
            (0..length)
                .map(|index| ((73 * index + index / 251 + 19 * (index / 65536)) & 255) as u8),
        );
    }
    run(&file, None, &expected, &bytes);
}

#[test]
fn core_outer_owned_inner_preserve_all_binary_bytes_and_layer_local_state() {
    mixed("mixed_core_outer", true);
}

#[test]
fn owned_outer_core_inner_preserve_all_binary_bytes_and_layer_local_state() {
    mixed("mixed_alloc_outer", false);
}

#[test]
fn reached_owned_constructor_denial_preserves_live_borrowed_provider_then_retry_succeeds() {
    use Event::*;
    let file = executable("constructor_retry");
    for denied in [false, true] {
        let mut expected = vec![Allocate(8), Allocate(9), Mark(b'P'), Mark(b'p')];
        if denied {
            expected.push(Denied(3));
        } else {
            expected.extend([Allocate(3), Release(3)]);
        }
        expected.extend([
            Mark(b'R'),
            Allocate(3),
            Mark(b'P'),
            Mark(b'p'),
            Release(4),
            Release(2),
            Release(1),
            Mark(b'D'),
        ]);
        run(&file, denied.then_some(3), &expected, &[]);
    }
}
