#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    net::UdpSocket,
    os::{fd::OwnedFd, unix::fs::PermissionsExt},
    process::{Command, Stdio},
};

use laniusc_compiler::{
    codegen::lowering_ir::HostService,
    compiler::compile_source_to_wasm_with_gpu_codegen,
};

fn fixture(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_linux", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn builtin_name_counts_and_sparse_host_slots_stay_consistent() {
    let count = laniusc_compiler::type_checker::LANGUAGE_SYMBOL_COUNT;
    assert_eq!(count, 75);
    let mut directories =
        vec![std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("shaders/type_checker")];
    let mut mirrors = 0;
    while let Some(directory) = directories.pop() {
        for entry in std::fs::read_dir(directory).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                directories.push(path);
            } else if path
                .extension()
                .is_some_and(|extension| extension == "slang")
            {
                for line in std::fs::read_to_string(&path).unwrap().lines() {
                    if let Some(value) = line
                        .strip_prefix("static const uint LANGUAGE_SYMBOL_COUNT = ")
                        .or_else(|| line.strip_prefix("static const uint LANGUAGE_NAME_COUNT = "))
                    {
                        let value: u32 = value.trim_end_matches("u;").parse().unwrap();
                        assert_eq!(value, count, "{}", path.display());
                        mirrors += 1;
                    }
                }
            }
        }
    }
    assert!(mirrors > 0);
    for slot in 20..63 {
        assert_eq!(
            HostService::from_symbol_slot(slot).map(HostService::symbol_slot),
            if slot == 52 { None } else { Some(slot) }
        );
    }
    for slot in 63..74 {
        assert_eq!(HostService::from_symbol_slot(slot), None);
    }
    assert_eq!(HostService::LinuxSyscall6.symbol_slot(), 74);
    assert_eq!(
        HostService::from_symbol_slot(74),
        Some(HostService::LinuxSyscall6)
    );
    assert_eq!(HostService::from_symbol_slot(75), None);
}

#[test]
fn native_words_results_and_fifth_sixth_pointer_arguments_execute() {
    let exe = fixture("linux_syscall_arguments");
    let data = common::TempArtifact::new("laniusc_linux", "sparse_file", None);
    data.write_bytes([]);
    let receiver = UdpSocket::bind("127.0.0.1:0").unwrap();
    let sender = UdpSocket::bind("127.0.0.1:0").unwrap();
    sender
        .send_to(b"abc", receiver.local_addr().unwrap())
        .unwrap();
    let trace = common::TempArtifact::new("laniusc_linux", "argument_trace", None);
    let output = common::short_process_output_with_timeout(
        "Linux argument ABI",
        // The common timeout helper captures stdout. Redirect after spawning so
        // the native program still receives the seekable read/write descriptor.
        Command::new("sh")
            .args(["-c", "exec strace -qq -o \"$1\" -e trace=lseek,ftruncate,statx,recvfrom,mmap,munmap \"$2\" 1<> \"$3\"", "linux-argument-abi"])
            .arg(trace.path())
            .arg(exe.path())
            .arg(data.path())
            .stdin(Stdio::from(OwnedFd::from(receiver))),
    );
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
    assert_eq!(std::fs::metadata(data.path()).unwrap().len(), 4_294_967_301);
    let trace = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        trace.contains("4294967301") && trace.contains("-4294967297"),
        "{trace}"
    );
    assert!(
        trace.contains("statx(1,") && trace.contains("recvfrom(0,"),
        "{trace}"
    );
    let maps: Vec<_> = trace
        .lines()
        .filter(|line| line.starts_with("mmap("))
        .collect();
    assert_eq!(maps.len(), 2, "unexpected helper allocation: {trace}");
    assert!(
        maps[0].contains(", 0x100000000)"),
        "sixth word lost high bits: {trace}"
    );
    assert!(
        maps[1].contains(", 0)"),
        "unused sixth word was not zero: {trace}"
    );
    let mut live = std::collections::BTreeSet::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            assert!(result.starts_with("0x"), "{trace}");
            assert!(live.insert(result.to_owned()));
        }
        if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0") && live.remove(address), "{trace}");
        }
    }
    assert!(live.is_empty(), "mapping leaked: {trace}");
}

#[test]
fn invalid_views_errno_and_interruption_do_not_allocate_or_retry() {
    let exe = fixture("linux_syscall_errors");
    let trace = common::TempArtifact::new("laniusc_linux", "error_trace", None);
    for (injection, status) in [(None, 0), (Some("EINTR"), 4), (Some("EIO"), 5)] {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=getpid,mmap,munmap"]);
        if let Some(error) = injection {
            command
                .arg("-e")
                .arg(format!("inject=getpid:error={error}:when=1+"));
        }
        command.arg(exe.path());
        let output =
            common::short_process_output_with_timeout("Linux error contract", &mut command);
        assert_eq!(output.status.code(), Some(status), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(
            events
                .lines()
                .filter(|line| line.starts_with("getpid("))
                .count(),
            1,
            "retried syscall: {events}"
        );
        assert!(
            !events.contains("mmap(") && !events.contains("munmap("),
            "helper allocated: {events}"
        );
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
    }
}

#[test]
fn native_runtime_metadata_includes_linux_without_binding_aggregate_host_services() {
    let exe = fixture("core_runtime_metadata");
    let output = common::short_process_output_with_timeout(
        "native runtime metadata",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn linux_syscall_is_explicitly_unsupported_on_wasm() {
    let source = "extern \"lanius_linux\" fn syscall6(number:i64,args:ptr)->i64; fn main()->i32 { let zero:ptr=0; return syscall6(39,zero) as i32; }".to_owned();
    let error = common::run_gpu_codegen_with_timeout("Wasm Linux syscall rejection", move || {
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(&source))
    })
    .expect_err("Linux syscall must not produce Wasm bytes");
    let error = error.to_string();
    assert!(
        error.contains("unsupported") || error.contains("not supported"),
        "{error}"
    );
}
