#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_alloc_deque", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("alloc deque", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn freed(events: &str) -> usize {
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
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}

#[test]
fn deque_contracts_and_generic_payloads_execute() {
    for name in ["alloc_deque", "alloc_deque_types"] {
        let exe = fixture(name);
        let output = run(&mut Command::new(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn every_deque_allocation_failure_preserves_contents_capacity_and_views() {
    let exe = fixture("alloc_deque_failure");
    let trace = common::TempArtifact::new("laniusc_alloc_deque", "failure_trace", None);
    let execute = |when: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        let output = run(command.arg(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(
                events.contains("INJECTED") && events.contains("ENOMEM"),
                "{events}"
            );
        }
        freed(&events)
    };
    let allocations = execute(None);
    assert!(allocations >= 24, "exercise each allocation path");
    for when in 1..=allocations {
        execute(Some(when));
    }
}

#[test]
fn checked_indexing_panics_for_empty_negative_and_past_end_indices() {
    let exe = fixture("alloc_deque_at_bounds");
    for arguments in [vec![], vec!["negative"], vec!["past", "end"]] {
        use std::os::unix::process::ExitStatusExt;
        let output = common::signal_process_output_with_timeout(
            "deque bounds panic",
            Command::new(exe.path()).args(arguments),
        );
        assert_eq!(output.status.signal(), Some(4), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
}

#[test]
fn zero_sized_ring_storage_never_allocates() {
    let exe = fixture("alloc_deque_zero_sized");
    let trace = common::TempArtifact::new("laniusc_deque", "zst_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn reserved_edits_and_large_fifo_workloads_allocate_once() {
    let reserved = fixture("alloc_deque_reserved");
    let workload = fixture("alloc_deque_workload");
    for (exe, args, expected) in [
        (reserved.path(), vec![], String::new()),
        (
            workload.path(),
            vec![],
            format!("{}\n", (262144_i64..262144 + 4096).sum::<i64>()),
        ),
        (
            workload.path(),
            vec!["large"],
            format!("{}\n", (262144_i64..262144 + 65536).sum::<i64>()),
        ),
    ] {
        let trace = common::TempArtifact::new("laniusc_deque", "reserved_trace", None);
        let output = common::process_output_with_timeout(
            "reserved deque workload",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=2+",
                ])
                .arg(exe)
                .args(args),
            std::time::Duration::from_secs(3),
        );
        checked(&output, 0);
        assert_eq!(output.stdout, expected.as_bytes());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("INJECTED"), "{events}");
        assert_eq!(freed(&events), 1);
    }
}

#[test]
fn recent_value_programs_report_allocation_failure_and_release_storage() {
    for (path, input, status) in [
        (
            "sample_programs/recent_bool_count.lani",
            b"101101".as_slice(),
            2,
        ),
        (
            "sample_programs/recent_unicode_scalars.lani",
            "aΩ😀é中".as_bytes(),
            4,
        ),
    ] {
        let exe = executable(path);
        let data = common::TempArtifact::new("laniusc_deque", "program_input", None);
        data.write_bytes(input);
        let trace = common::TempArtifact::new("laniusc_deque", "program_trace", None);
        let execute = |when: Option<usize>| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"]);
            if let Some(when) = when {
                command
                    .arg("-e")
                    .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
            }
            let output = run(command.arg(exe.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(data.path()).unwrap(),
            )));
            checked(&output, if when.is_some() { status } else { 0 });
            let events = std::fs::read_to_string(trace.path()).unwrap();
            if when.is_some() {
                assert!(output.stdout.is_empty());
                assert!(events.contains("INJECTED") && events.contains("ENOMEM"));
            }
            freed(&events)
        };
        let allocations = execute(None);
        assert!(allocations >= 1);
        for when in 1..=allocations {
            execute(Some(when));
        }
    }
}
