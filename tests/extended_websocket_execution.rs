#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
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
    let exe = common::TempArtifact::new("laniusc_websocket", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("websocket", command, Duration::from_secs(5))
}
fn checked(out: &Output, status: i32) {
    assert_eq!(out.status.code(), Some(status), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
}
fn freed(events: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut count = 0;
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap();
                let size = args.split(',').nth(1).unwrap().trim();
                assert!(live.insert(address, size).is_none(), "{events}");
                count += 1;
            }
        } else if let Some(args) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            let (address, rest) = args.split_once(',').unwrap();
            let size = rest.split(')').next().unwrap().trim();
            assert_eq!(live.remove(address), Some(size), "{line}");
        }
    }
    assert!(live.is_empty(), "leaked allocations: {live:?}\n{events}");
    count
}
#[test]
fn websocket_contracts_cover_requests_fragments_controls_close_and_limits() {
    let exe = executable("tests/fixtures/extended/websocket_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_websocket", "trace", None);
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,socket,connect,open,openat"])
        .arg(exe.path()));
    checked(&out, 0);
    assert!(out.stdout.is_empty());
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(freed(&events) > 0);
    assert!(
        !events.contains("socket(")
            && !events.contains("connect(")
            && !events.contains("open(")
            && !events.contains("openat("),
        "{events}"
    );
}
#[test]
fn websocket_allocation_errors_preserve_state_and_release_staging() {
    for name in ["websocket_failure", "websocket_handshake_failure"] {
        let exe = executable(&format!("tests/fixtures/extended/{name}.lani"));
        let trace = common::TempArtifact::new("laniusc_websocket", "trace", None);
        let execute = |when: Option<usize>, status| {
            let mut c = Command::new("strace");
            c.args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"]);
            if let Some(at) = when {
                c.arg("-e")
                    .arg(format!("inject=mmap:error=ENOMEM:when={at}"));
            }
            let out = run(c.arg(exe.path()));
            checked(&out, status);
            assert!(out.stdout.is_empty());
            let events = std::fs::read_to_string(trace.path()).unwrap();
            if when.is_some() {
                assert!(
                    events.contains("INJECTED") && events.contains("ENOMEM"),
                    "{events}"
                );
            }
            freed(&events)
        };
        let count = execute(None, 0);
        let minimum = if name == "websocket_failure" { 4 } else { 1 };
        assert!(count >= minimum, "{name} must reach an owned allocation");
        for at in 1..=count {
            execute(Some(at), 4);
        }
    }
}
