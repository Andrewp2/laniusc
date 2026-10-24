#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    process::{Command, Output},
};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_signal", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn run(exe: &common::TempArtifact, closed: bool, inject: Option<&str>) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_signal", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=rt_sigaction,write,mmap,munmap"]);
    if let Some(inject) = inject {
        command.arg("-e").arg(format!("inject={inject}"));
    }
    command.arg(exe.path());
    if closed {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    let out = command.output().expect("run bounded signal fixture");
    assert_ne!(out.status.code(), Some(124), "{out:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "signal disposition allocated: {events}"
    );
    if inject.is_some() {
        assert!(events.contains("INJECTED"), "{events}");
    }
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    (out, events)
}
#[test]
fn typed_dispositions_match_kernel_state_and_ignore_real_broken_pipe() {
    let mappings = executable("signal_mappings");
    let (out, _) = run(&mappings, false, None);
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    let ignore = executable("signal_ignore");
    let (out, events) = run(&ignore, true, None);
    assert_eq!(out.status.code(), Some(0), "{out:?}\n{events}");
    assert!(
        events.contains("SIGPIPE") && events.contains("EPIPE"),
        "{events}"
    );
}
#[test]
fn restoring_default_broken_pipe_disposition_terminates_only_the_child() {
    let exe = executable("signal_default");
    let (out, events) = run(&exe, true, None);
    assert!(
        out.status.signal() == Some(13) || out.status.code() == Some(141),
        "{out:?}\n{events}"
    );
    assert!(events.contains("killed by SIGPIPE"), "{events}");
}
#[test]
fn signal_host_errors_and_invalid_statuses_are_explicit_without_allocation() {
    let exe = executable("signal_errors");
    let (out, _) = run(&exe, false, None);
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    for (inject, status) in [
        ("rt_sigaction:error=EPERM:when=1", 71),
        ("rt_sigaction:error=EINTR:when=1", 72),
        ("rt_sigaction:error=EAGAIN:when=1", 73),
        ("rt_sigaction:retval=1:when=1", 74),
    ] {
        let (out, events) = run(&exe, false, Some(inject));
        assert_eq!(
            out.status.code(),
            Some(status),
            "{inject}: {out:?}\n{events}"
        );
    }
}
