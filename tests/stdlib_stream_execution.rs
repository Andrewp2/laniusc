mod common;

fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn stream_contracts_execute_partial_progress_and_failure_cases() {
    for name in ["core_io", "alloc_io"] {
        let bytes = compile(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let output = common::run_x86_64_elf_output("stream contracts", name, &bytes);
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn owned_stream_buffer_preserves_bytes_and_ownership_when_allocation_fails() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("tests/fixtures/stdlib_foundation/alloc_io_failure.lani");
    let executable = common::TempArtifact::new("laniusc_stream", "allocation_failure", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let normal = common::short_process_output_with_timeout(
        "stream buffer allocation",
        &mut std::process::Command::new(executable.path()),
    );
    assert_eq!(normal.status.code(), Some(1), "{normal:?}");
    let trace = common::TempArtifact::new("laniusc_stream", "allocation_trace", None);
    for (when, status) in [("1+", 2), ("2+", 0)] {
        let failed = common::short_process_output_with_timeout(
            "stream buffer allocation failure",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}"))
                .arg(executable.path()),
        );
        assert_eq!(failed.status.code(), Some(status), "{when}: {failed:?}");
        assert!(
            failed.stdout.is_empty() && failed.stderr.is_empty(),
            "{failed:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
        let mut live = std::collections::BTreeSet::new();
        for line in events.lines() {
            if line.starts_with("mmap(") {
                let value = line.rsplit(" = ").next().unwrap();
                if value.starts_with("0x") {
                    assert!(live.insert(value.to_owned()), "{line}");
                }
            } else if let Some(tail) = line.strip_prefix("munmap(") {
                assert!(line.ends_with(" = 0"), "{line}");
                assert!(live.remove(tail.split(',').next().unwrap()), "{line}");
            }
        }
        assert!(live.is_empty(), "leaked allocations: {events}");
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_descriptors_preserve_errors_strides_and_offsets() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("tests/fixtures/stdlib_foundation/std_stream.lani");
    let executable = common::TempArtifact::new("laniusc_stream", "descriptors", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = common::TempArtifact::new("laniusc_stream", "input", None);
    input.write_bytes(&[0, 128, 255, 42]);
    let output = common::short_process_output_with_timeout(
        "descriptor errors and strides",
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, [0, 128, 255]);
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_stream_copy_executes_binary_data_and_host_failures() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("sample_programs/stream_copy.lani");
    let executable = common::TempArtifact::new("laniusc_stream", "copy", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = common::TempArtifact::new("laniusc_stream", "input", None);
    let trace = common::TempArtifact::new("laniusc_stream", "trace", None);
    for length in [0, 1, 1023, 1024, 1025, 65539] {
        let data: Vec<u8> = (0..length)
            .map(|index| (index * 37 + index / 256) as u8)
            .collect();
        input.write_bytes(&data);
        let output = common::short_process_output_with_timeout(
            "binary stream copy",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "length {length}: {output:?}");
        assert_eq!(output.stdout, data, "length {length}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    let data: Vec<u8> = (0..2500).map(|index| (index * 17) as u8).collect();
    input.write_bytes(&data);
    for (injection, status, prefix) in [
        ("read:error=EINTR:when=1", 0, 2500),
        ("write:error=EINTR:when=1", 0, 2500),
        ("read:error=EAGAIN:when=2", 2, 1024),
        ("write:error=EIO:when=2", 2, 1024),
        ("write:retval=0:when=1", 1, 0),
    ] {
        let output = common::short_process_output_with_timeout(
            "injected stream error",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=read,write", "-e"])
                .arg(format!("inject={injection}"))
                .arg(executable.path())
                .stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
        );
        assert_eq!(
            output.status.code(),
            Some(status),
            "{injection}: {output:?}"
        );
        assert_eq!(output.stdout, data[..prefix], "{injection}");
        assert!(output.stderr.is_empty(), "{injection}: {output:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{injection}: {events}");
    }
}
