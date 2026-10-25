#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};

fn executable(name: &str, relative: &str) -> common::TempArtifact {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(relative);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_command", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(
        name,
        &format!("tests/fixtures/stdlib_foundation/{name}.lani"),
    )
}
fn check(exe: &common::TempArtifact, args: &[&Path], stdout: &[u8], stderr: &[u8]) {
    let output = Command::new("timeout")
        .args(["--kill-after=1s", "8s"])
        .arg(exe.path())
        .args(args)
        .env("COMMAND_TEST", "raw")
        .output()
        .expect("run bounded command fixture");
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, stdout);
    assert_eq!(output.stderr, stderr);
}
#[test]
fn raw_fork_exec_wait_and_checked_launch_contracts_execute() {
    let admission = fixture("command_admission");
    check(&admission, &[], b"", b"");
    let contracts = fixture("command_contracts");
    check(&contracts, &[], b"", b"");
    let validation = fixture("command_validation");
    check(&validation, &[], b"", b"");
}
#[test]
fn pipes_environment_descriptor_cycles_and_pid_signal_lifetimes_execute() {
    let signal = fixture("command_signal_peer");
    let lifecycle = fixture("command_lifecycle");
    check(&lifecycle, &[signal.path()], b"", b"");
    let peer = fixture("command_fd_peer");
    let cycle = fixture("command_cycle");
    check(&cycle, &[peer.path()], b"ERR", b"OUT");
}
#[test]
fn real_runner_and_independent_startup_resource_fault_models_execute() {
    let runner = executable("run_command", "sample_programs/library/run_command.lani");
    let probe = fixture("command_failure_probe");
    let signal = fixture("command_signal_peer");
    let oracle = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/command_oracle.py");
    let output = Command::new("timeout")
        .args(["--kill-after=1s", "40s", "python3"])
        .arg(oracle)
        .args([runner.path(), probe.path(), signal.path()])
        .output()
        .expect("run bounded independent command oracle");
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stdout).contains("ledgers balanced"),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn nonblocking_wait_returns_interruption_without_losing_pid_ownership() {
    let child = fixture("command_try_wait_interrupt");
    for (inject, expected) in [(false, 40), (true, 41)] {
        let trace = common::TempArtifact::new("laniusc_command", "try_wait_trace", None);
        let mut command = Command::new("timeout");
        command.args(["--kill-after=1s", "5s"]);
        if inject {
            command
                .args([
                    "strace",
                    "-qq",
                    "-e",
                    "trace=wait4",
                    "-e",
                    "signal=none",
                    "-o",
                ])
                .arg(trace.path())
                .args(["-e", "inject=wait4:error=EINTR:when=1"]);
        }
        let output = command.arg(child.path()).output().unwrap();
        assert_eq!(output.status.code(), Some(expected), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        if inject {
            assert!(
                std::fs::read_to_string(trace.path())
                    .unwrap()
                    .contains("INJECTED")
            );
        }
    }
}
