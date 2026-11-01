#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
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
    let exe = common::TempArtifact::new("laniusc_http", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("http", command)
}
fn allocations(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "{events}");
    count
}
#[test]
fn http_borrowed_heads_framing_chunks_strides_limits_and_checked_encoders_execute() {
    let exe = executable("tests/fixtures/extended/http_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_http", "trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,open,openat,socket,connect"])
        .arg(exe.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("socket(") && !events.contains("connect(") && !events.contains("open("),
        "{events}"
    );
    assert!(allocations(&events) > 0);
}
#[test]
fn http_encoder_releases_staging_on_every_allocation_failure() {
    let exe = executable("tests/fixtures/extended/http_failure.lani");
    let trace = common::TempArtifact::new("laniusc_http", "failure", None);
    let execute = |injection: Option<String>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(injection) = injection {
            command.args(["-e", &injection]);
        }
        let output = run(command.arg(exe.path()));
        assert_eq!(output.status.code(), Some(status), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        allocations(&std::fs::read_to_string(trace.path()).unwrap())
    };
    let count = execute(None, 0);
    assert_eq!(count, 1, "the checked encoder reserves its exact output once");
    for at in 1..=count {
        execute(Some(format!("inject=mmap:error=ENOMEM:when={at}")), 4);
    }
}

#[test]
fn http_encoder_preflights_caps_and_uses_one_exact_allocation_per_valid_message() {
    let exe = executable("tests/fixtures/extended/http_encoder_preflight.lani");
    let trace = common::TempArtifact::new("laniusc_http", "preflight", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,open,openat,socket,connect"])
        .arg(exe.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(!events.contains("socket(") && !events.contains("connect(") && !events.contains("open("), "{events}");
    // Fifteen successful encodings; cap and invalid-field rejections allocate
    // nothing. Matching unmaps also check explicit destruction of each owner.
    assert_eq!(allocations(&events), 15, "{events}");
}
