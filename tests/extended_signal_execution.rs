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
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_signal", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn direct_dft_fraction_convolution_windows_and_scale_models() {
    let exe = executable("tests/fixtures/extended/signal_model.lani");
    let output = common::process_output_with_timeout(
        "signal independent models",
        Command::new("python3")
            .args(["-c", include_str!("fixtures/extended/signal_oracle.py")])
            .arg(exe.path()),
        Duration::from_secs(45),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
#[test]
fn finite_errors_limits_borrows_and_every_allocation_failure_cleanup() {
    let contracts = executable("tests/fixtures/extended/signal_contracts.lani");
    let failure = executable("tests/fixtures/extended/signal_allocation_failure.lani");
    let trace = common::TempArtifact::new("laniusc_signal", "allocations", None);
    let output = common::short_process_output_with_timeout(
        "signal numeric error cleanup",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(contracts.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
    let mut count = 0;
    for when in 0..=5 {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if when > 0 {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        command.arg(failure.path());
        let output =
            common::short_process_output_with_timeout("signal allocation denial", &mut command);
        assert_eq!(
            output.status.code(),
            Some(0),
            "allocation {when}: {output:?}"
        );
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocated = no_leaks(&events);
        if when == 0 {
            count = allocated;
            assert_eq!(count, 5);
        } else {
            assert_eq!(allocated, when - 1);
            assert!(events.contains("INJECTED"));
        }
    }
    assert_eq!(count, 5);
}
fn no_leaks(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") && !line.contains("= -1") {
            let address = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            assert!(live.insert(address.to_owned()));
            count += 1;
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{trace}"
            );
        }
    }
    assert!(live.is_empty(), "leaked allocations {live:?}\n{trace}");
    count
}
