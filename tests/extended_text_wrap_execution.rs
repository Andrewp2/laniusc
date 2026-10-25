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
    let exe = common::TempArtifact::new("laniusc_text_wrap", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn real_text_wrap_independent_width_fitting_limits_scale_and_fault_models() {
    let exe = executable("sample_programs/library/text_wrap.lani");
    let output = common::process_output_with_timeout(
        "text wrap independent models and faults",
        Command::new("python3")
            .args(["-c", include_str!("fixtures/extended/text_wrap_oracle.py")])
            .arg(exe.path()),
        Duration::from_secs(45),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
#[test]
fn wrap_owned_output_preserves_input_and_cleans_up_late_errors() {
    let exe = executable("tests/fixtures/extended/text_wrap_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_text_wrap", "cleanup", None);
    let output = common::short_process_output_with_timeout(
        "wrap ownership contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    let mut live = std::collections::BTreeSet::new();
    for line in std::fs::read_to_string(trace.path()).unwrap().lines() {
        if line.starts_with("mmap(") && !line.contains("= -1") {
            let address = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            assert!(live.insert(address.to_owned()));
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()));
        }
    }
    assert!(live.is_empty(), "leaked owners: {live:?}");
}
fn mappings_released(events: &str) -> usize {
    let mut live = std::collections::BTreeMap::new();
    let mut allocations = 0;
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let returned = line.rsplit(" = ").next().unwrap();
            if returned.starts_with("0x") {
                let address = returned.split_whitespace().next().unwrap();
                let size = arguments.split(',').nth(1).unwrap().trim();
                assert!(live.insert(address, size).is_none(), "{events}");
                allocations += 1;
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            let (address, tail) = arguments.split_once(',').unwrap();
            let size = tail.split(')').next().unwrap().trim();
            assert_eq!(live.remove(address), Some(size), "{events}");
        }
    }
    assert!(live.is_empty(), "unreleased mappings: {live:?}\n{events}");
    allocations
}

#[test]
fn text_wrap_real_closed_output_pipes_and_preallocation_signal_failure() {
    let exe = executable("sample_programs/library/text_wrap.lani");
    let input = common::TempArtifact::new("laniusc_text_wrap", "pipe_input", None);
    let trace = common::TempArtifact::new("laniusc_text_wrap", "pipe_trace", None);
    for boundary in 0..3 {
        input.write_bytes(if boundary == 1 {
            b"\xff".as_slice()
        } else {
            b"Hello. World!\n".as_slice()
        });
        let mut command = Command::new("timeout");
        command
            .args(["--kill-after=1s", "8s", "strace", "-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=rt_sigaction,read,write,mmap,munmap"]);
        if boundary == 2 {
            command.args(["-e", "inject=rt_sigaction:error=EINTR:when=1"]);
        }
        command
            .arg(exe.path())
            .args(["--columns", "8"])
            .stdin(std::fs::File::open(input.path()).unwrap());
        if boundary < 2 {
            let (reader, writer) = std::io::pipe().unwrap();
            drop(reader);
            if boundary == 0 {
                command.stdout(writer);
            } else {
                command.stderr(writer);
            }
        }
        // Command::output retains explicit redirection. The common capturing
        // helper replaces it and would not exercise a genuinely closed pipe.
        let output = command.output().expect("bounded wrap pipe gate");
        assert_eq!(output.status.code(), Some(3), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = mappings_released(&events);
        if boundary == 2 {
            assert!(output.stderr.is_empty());
            assert_eq!(allocations, 0, "setup must precede allocation: {events}");
            assert!(
                events.contains("INJECTED") && events.contains("EINTR"),
                "{events}"
            );
            assert!(
                !events
                    .lines()
                    .any(|line| line.starts_with("read(") || line.starts_with("write(")),
                "{events}"
            );
        } else {
            assert!(
                allocations > 0 && events.contains("SIG_IGN") && events.contains("EPIPE"),
                "{events}"
            );
            assert!(
                events.contains(if boundary == 0 {
                    "write(1,"
                } else {
                    "write(2,"
                }),
                "{events}"
            );
            if boundary == 0 {
                assert!(output.stderr.starts_with(b"text-wrap:"));
            } else {
                assert!(output.stderr.is_empty());
            }
        }
    }
}
