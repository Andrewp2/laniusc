#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{collections::BTreeSet, os::unix::fs::PermissionsExt, process::Command, time::Duration};

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
    let file = common::TempArtifact::new("laniusc_socket", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn owned_descriptors_close(trace: &str) -> usize {
    let mut live = BTreeSet::new();
    let mut opened = 0;
    for line in trace.lines() {
        assert!(
            !line.starts_with("mmap(") && !line.starts_with("munmap("),
            "socket foundation allocated: {trace}"
        );
        let result = line
            .rsplit(" = ")
            .next()
            .unwrap()
            .split_whitespace()
            .next()
            .unwrap();
        let Ok(result) = result.parse::<i32>() else {
            continue;
        };
        if result < 0 {
            continue;
        }
        if line.starts_with("socket(")
            || line.starts_with("accept4(")
            || (line.starts_with("fcntl(") && line.contains("F_DUPFD_CLOEXEC"))
        {
            assert!(live.insert(result), "duplicate owner: {trace}");
            opened += 1;
        } else if let Some(tail) = line.strip_prefix("close(") {
            let fd: i32 = tail.split(')').next().unwrap().parse().unwrap();
            assert_eq!(result, 0, "{trace}");
            assert!(live.remove(&fd), "closing unowned fd {fd}: {trace}");
        }
    }
    assert!(
        live.is_empty(),
        "leaked socket descriptors {live:?}: {trace}"
    );
    opened
}

fn run(name: &str) {
    let exe = executable(name);
    let trace = common::TempArtifact::new("laniusc_socket", "trace", None);
    let output = common::process_output_with_timeout(name, Command::new("strace")
        .args(["-qq","-o"]).arg(trace.path())
        .args(["-e","trace=socket,accept4,fcntl,close,mmap,munmap,bind,connect,listen,getsockname,getpeername,setsockopt,getsockopt,poll,sendto,recvfrom,shutdown"])
        .arg(exe.path()), Duration::from_secs(8));
    assert_eq!(
        output.status.code(),
        Some(0),
        "{output:?}\n{}",
        std::fs::read_to_string(trace.path()).unwrap()
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(owned_descriptors_close(&std::fs::read_to_string(trace.path()).unwrap()) >= 4);
}

#[test]
fn tcp_udp_ownership_options_half_close_deadlines_and_portable_stream_traits_execute() {
    run("socket_contracts");
}

#[test]
fn ipv4_ipv6_full_datagrams_strided_views_and_explicit_truncation_execute() {
    run("socket_datagrams");
}

#[test]
fn internet_connect_eagain_is_preserved_instead_of_inventing_pending_state() {
    let exe = executable("socket_connect_error");
    let trace = common::TempArtifact::new("laniusc_socket", "connect_fault", None);
    let output = common::process_output_with_timeout(
        "Internet connect EAGAIN",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=socket,close,connect,mmap,munmap",
                "-e",
                "inject=connect:error=EAGAIN:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(5),
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(
        events.contains("EAGAIN") && events.contains("INJECTED"),
        "{events}"
    );
    assert_eq!(owned_descriptors_close(&events), 1);
}

#[test]
fn absolute_deadlines_end_repeated_ready_eagain_and_continuous_interrupts() {
    let exe = executable("socket_deadline_faults");
    for (injection, args) in [
        ("inject=recvfrom:error=EAGAIN:when=1+", vec!["ready"]),
        ("inject=poll:error=EINTR:when=1+", vec![]),
        ("inject=sendto:error=EINTR:when=1+", vec!["send", "ready"]),
    ] {
        let trace = common::TempArtifact::new("laniusc_socket", "deadline_fault", None);
        let output = common::process_output_with_timeout(
            injection,
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=socket,accept4,fcntl,close,mmap,munmap,connect,bind,listen,sendto,recvfrom,poll", "-e", injection])
                .arg(exe.path())
                .args(args),
            Duration::from_secs(5),
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(
            output.status.code(),
            Some(0),
            "{injection}: {output:?}\n{events}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        assert!(
            events.matches("INJECTED").count() >= 2,
            "retry path was not explored: {events}"
        );
        assert_eq!(owned_descriptors_close(&events), 3);
    }
}

#[test]
fn malformed_accept_reply_closes_the_real_new_descriptor_before_returning_error() {
    let exe = executable("socket_accept_error");
    let trace = common::TempArtifact::new("laniusc_socket", "accept_reply", None);
    let output = common::process_output_with_timeout(
        "malformed accepted peer",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=socket,accept4,close,mmap,munmap",
                "-e",
                "inject=accept4:poke_exit=@arg3=ffffffff:when=1",
            ])
            .arg(exe.path()),
        Duration::from_secs(5),
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(events.contains("accept4("), "{events}");
    assert_eq!(owned_descriptors_close(&events), 3);
}
