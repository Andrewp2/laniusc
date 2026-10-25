#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
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
    let exe = common::TempArtifact::new("laniusc_image", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut n = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let addr = line.rsplit(" = ").next().unwrap();
            if addr.starts_with("0x") {
                assert!(
                    live.insert(addr.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                n += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    n
}
#[test]
fn image_coordinates_views_aliasing_bounds_and_compositing_execute() {
    let exe = executable("tests/fixtures/extended/image_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_image", "trace", None);
    let output = common::process_output_with_timeout(
        "image contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty() && output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) > 100);
}
#[test]
fn every_image_allocation_denial_returns_and_cleans_up_prior_owners() {
    let exe = executable("tests/fixtures/extended/image_allocation_failure.lani");
    let trace = common::TempArtifact::new("laniusc_image", "failure-trace", None);
    let run = |failure: Option<usize>| {
        let mut cmd = Command::new("strace");
        cmd.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = failure {
            cmd.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
        }
        cmd.arg(exe.path());
        let o = common::process_output_with_timeout(
            "image allocation failure",
            &mut cmd,
            Duration::from_secs(10),
        );
        assert!(o.stderr.is_empty() && o.stdout.is_empty(), "{o:?}");
        let n = freed(&std::fs::read_to_string(trace.path()).unwrap());
        (o.status.code(), n)
    };
    let (status, n) = run(None);
    assert_eq!(status, Some(0));
    assert_eq!(n, 5);
    for fail in 1..=n {
        assert_eq!(run(Some(fail)).0, Some(7), "allocation {fail}/{n}");
    }
}
