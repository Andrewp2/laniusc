mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_hash_map", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn hash_map_models_collisions_and_executes_generic_payloads() {
    for name in ["alloc_hash_map", "alloc_hash_map_model", "alloc_hash_types"] {
        let exe = executable(name);
        let output = common::process_output_with_timeout(
            name,
            &mut std::process::Command::new(exe.path()),
            std::time::Duration::from_secs(2),
        );
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}

fn assert_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(live.insert(address), "duplicate live allocation: {line}");
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0"), "deallocation failed: {line}");
            assert!(live.remove(address), "unknown/double deallocation: {line}");
        }
    }
    assert!(live.is_empty(), "allocations leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn hash_map_preserves_entries_and_releases_storage_on_every_allocation_failure() {
    let exe = executable("alloc_hash_failure");
    let trace = common::TempArtifact::new("laniusc_hash_map", "trace", None);
    let traced = |when: Option<usize>| {
        let mut command = std::process::Command::new("strace");
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
            common::short_process_output_with_timeout("hash map allocation fault", &mut command);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let allocations = assert_freed(&events);
        (output, allocations)
    };
    let (baseline, allocations) = traced(None);
    assert_eq!(baseline.status.code(), Some(1), "{baseline:?}");
    assert!(allocations > 0, "fault sweep must observe native allocations");
    for when in 1..=allocations {
        let (output, _) = traced(Some(when));
        assert_eq!(
            output.status.code(),
            Some(0),
            "allocation {when}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    // Owned String keys/values are returned for explicit destruction, including
    // replaced keys. Verify the successful ownership path with a syscall trace.
    let owned = executable("alloc_hash_types");
    let output = common::short_process_output_with_timeout(
        "hash map nested ownership",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(owned.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_freed(&std::fs::read_to_string(trace.path()).unwrap());
}
