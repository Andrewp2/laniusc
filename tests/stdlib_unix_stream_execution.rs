//! Direct owned Unix stream contracts, binary staging and descriptor lifetime.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_unix_stream", "directory", None);
        fs::create_dir(path.path()).unwrap();
        Self(path)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}

fn execute(name: &str, directory: &Directory) -> String {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/unix_stream")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("Unix stream {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_unix_stream", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_unix_stream", "trace", None);
    let output=common::process_output_with_timeout(
        name,
        Command::new("strace").args(["-qq","-s","64","-o"]).arg(trace.path())
            .args(["-e","trace=socket,socketpair,bind,listen,connect,accept4,sendto,recvfrom,shutdown,fcntl,poll,clock_gettime,close,mmap,mremap,munmap,brk,unlink,unlinkat","-e","signal=none"])
            .arg(executable.path()).current_dir(directory.path()),
        Duration::from_secs(12),
    );
    let trace = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{trace}"
    );
    for forbidden in [
        "mmap(",
        "mremap(",
        "munmap(",
        "brk(",
        "unlink(",
        "unlinkat(",
    ] {
        assert!(
            !trace.contains(forbidden),
            "no allocation or implicit path removal: {trace}"
        );
    }
    assert_closed_owners(&trace);
    trace
}

fn calls<'a>(trace: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    trace
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn returned(line: &str) -> i32 {
    line.rsplit_once('=')
        .unwrap()
        .1
        .split_whitespace()
        .next()
        .unwrap()
        .parse()
        .unwrap_or_else(|error| panic!("numeric syscall result {error}: {line}"))
}
fn assert_closed_owners(trace: &str) {
    let mut live = BTreeSet::new();
    for line in trace.lines() {
        if line.starts_with("socketpair(") {
            assert_eq!(returned(line), 0, "{trace}");
            let array = line.rsplit_once('[').unwrap().1.split_once(']').unwrap().0;
            let handles: Vec<i32> = array
                .split(',')
                .map(|part| part.trim().parse().unwrap())
                .collect();
            assert_eq!(handles.len(), 2, "{trace}");
            for fd in handles {
                assert!(fd >= 0 && live.insert(fd), "unique acquired owner: {trace}");
            }
        } else if line.starts_with("socket(")
            || line.starts_with("accept4(")
            || (line.starts_with("fcntl(") && line.contains("F_DUPFD_CLOEXEC"))
        {
            let fd = returned(line);
            if fd >= 0 {
                assert!(live.insert(fd), "duplicate acquired owner: {trace}");
            }
        } else if let Some(rest) = line.strip_prefix("close(") {
            let fd: i32 = rest.split_once(')').unwrap().0.trim().parse().unwrap();
            assert!(
                live.remove(&fd),
                "close must retire exactly one acquired owner: {trace}"
            );
            assert_eq!(returned(line), 0, "{trace}");
        }
    }
    assert!(
        live.is_empty(),
        "all acquired descriptors explicitly closed: {live:?}\n{trace}"
    );
    for line in calls(trace, "socketpair")
        .into_iter()
        .chain(calls(trace, "socket"))
    {
        assert!(
            line.contains("AF_UNIX")
                && line.contains("SOCK_STREAM")
                && line.contains("SOCK_CLOEXEC"),
            "atomic stream/family/CLOEXEC creation: {line}"
        );
    }
    for line in calls(trace, "accept4") {
        assert!(
            line.contains("SOCK_CLOEXEC"),
            "atomic accepted-owner CLOEXEC: {line}"
        );
    }
}

#[test]
fn unix_socketpair_admits_bidirectional_binary_bytes_and_owned_close() {
    let directory = Directory::new();
    let trace = execute("admission.lani", &directory);
    assert_eq!(calls(&trace, "socketpair").len(), 1, "{trace}");
    assert_eq!(calls(&trace, "sendto").len(), 2, "{trace}");
    assert_eq!(calls(&trace, "recvfrom").len(), 2, "{trace}");
    assert_eq!(calls(&trace, "close").len(), 2, "{trace}");
}

#[test]
fn unix_stream_direct_contracts_cover_staging_flags_transfer_and_half_close() {
    let directory = Directory::new();
    let trace = execute("contracts.lani", &directory);
    assert!(
        calls(&trace, "sendto").len() >= 8 && calls(&trace, "recvfrom").len() >= 8,
        "real staged transfers: {trace}"
    );
    assert_eq!(calls(&trace, "bind").len(), 1, "{trace}");
    assert_eq!(calls(&trace, "listen").len(), 1, "{trace}");
    assert_eq!(calls(&trace, "connect").len(), 1, "{trace}");
    assert_eq!(calls(&trace, "accept4").len(), 1, "{trace}");
    assert!(
        directory.path().join("listener").exists(),
        "explicit close leaves pathname lifetime to caller"
    );
}

#[test]
#[ignore = "compiler follow-up: generic Result method chaining must compile and execute"]
fn generic_write_result_chain_should_execute_without_typed_local() {
    let directory = Directory::new();
    execute("generic_result_chain/chained.lani", &directory);
}

#[test]
#[ignore = "companion positive control for the isolated generic Result chain reduction"]
fn generic_write_result_typed_local_control_executes() {
    let directory = Directory::new();
    execute("generic_result_chain/typed_local.lani", &directory);
}
