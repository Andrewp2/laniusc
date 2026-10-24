#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{collections::BTreeMap, os::unix::fs::PermissionsExt, process::Command};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("tests/fixtures/stdlib_foundation/clone_fixture")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{name}: {e}"));
    let exe = common::TempArtifact::new("laniusc_clone", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn ledger(events: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let address = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            if address.starts_with("0x") {
                let length: usize = line.split(',').nth(1).unwrap().trim().parse().unwrap();
                assert!(
                    live.insert(address.to_owned(), length).is_none(),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, rest) = tail.split_once(',').unwrap();
            let length: usize = rest.split(')').next().unwrap().trim().parse().unwrap();
            assert_eq!(live.remove(address), Some(length), "{events}");
            assert!(line.ends_with(" = 0"), "{events}");
        }
    }
    assert!(live.is_empty(), "{events}");
    count
}
fn run(exe: &common::TempArtifact, when: Option<usize>, expected: Option<i32>) -> (String, usize) {
    let trace = common::TempArtifact::new("laniusc_clone", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = when {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={index}"));
    }
    let out = common::short_process_output_with_timeout(
        "explicit element clone",
        command.arg(exe.path()),
    );
    if let Some(code) = expected {
        assert_eq!(out.status.code(), Some(code), "{out:?}");
    } else {
        assert!(matches!(out.status.code(), Some(0..=2)), "{out:?}");
    }
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    if when.is_some() {
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
    }
    let count = ledger(&events);
    (events, count)
}
#[test]
fn cloning_preserves_duplicate_borrowed_sources_and_independent_nested_owners() {
    let exe = executable("clone_contracts");
    let (_, count) = run(&exe, None, Some(0));
    assert!(count >= 10);
}
#[test]
fn malformed_metadata_and_empty_views_do_not_allocate_or_clone_elements() {
    let exe = executable("clone_metadata");
    let (_, count) = run(&exe, None, Some(0));
    assert_eq!(count, 0);
}
#[test]
fn every_element_field_and_reached_allocation_releases_prefixes_and_preserves_owned_errors() {
    let exe = executable("clone_failures");
    let (_, count) = run(&exe, None, Some(0));
    assert!(count >= 80);
    for index in 1..=count {
        run(&exe, Some(index), None);
    }
    eprintln!("clone allocation positions={count}; every element/field owned error reached");
}

#[test]
fn zero_sized_elements_clone_and_destroy_without_allocating() {
    let exe = executable("clone_fixture/zero_sized");
    let (_, count) = run(&exe, None, Some(0));
    assert_eq!(count, 0);
}
