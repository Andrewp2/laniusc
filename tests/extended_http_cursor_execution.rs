#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_http_cursor", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn traced(path: &str) -> String {
    let exe = executable(path);
    let trace = common::TempArtifact::new("laniusc_http_cursor", "trace", None);
    let output = common::short_process_output_with_timeout(
        "HTTP cursor native contract",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write,socket,connect"])
            .arg(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{path}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("read(")
            && !events.contains("write(")
            && !events.contains("socket(")
            && !events.contains("connect("),
        "{events}"
    );
    events
}
#[test]
fn http_cursor_every_split_relocation_stride_fused_outcomes_limits_and_strict_parser_boundaries() {
    let events = traced("tests/fixtures/extended/http_cursor_contracts.lani");
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "cursor fixture must remain allocation free: {events}"
    );
}
#[test]
fn http_cursor_long_chunk_extensions_one_byte_feeds_have_partition_invariant_linear_work() {
    let events = traced("tests/fixtures/extended/http_cursor_scale.lani");
    let mut live = std::collections::BTreeMap::new();
    let mut allocations = 0;
    for line in events.lines() {
        if let Some(tail) = line.strip_prefix("mmap(") {
            let length = tail.split(',').nth(1).unwrap().trim().to_owned();
            let address = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            assert!(address.starts_with("0x"), "{events}");
            assert!(
                live.insert(address.to_owned(), length).is_none(),
                "{events}"
            );
            allocations += 1;
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, rest) = tail.split_once(',').unwrap();
            let length = rest.split(')').next().unwrap().trim();
            assert_eq!(live.remove(address).as_deref(), Some(length), "{events}");
            assert!(line.ends_with(" = 0"), "{events}");
        }
    }
    // Both allocations belong to the caller's wire and decoded fixture buffers.
    assert_eq!(allocations, 2, "{events}");
    assert!(live.is_empty(), "{events}");
}
