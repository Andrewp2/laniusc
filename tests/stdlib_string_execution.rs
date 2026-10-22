mod common;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"))
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn owned_utf8_edits_aliases_and_invalid_inputs_execute() {
    for name in ["alloc_string", "alloc_string_invalid"] {
        let bytes = compile_fixture(name);
        let output = common::run_x86_64_elf_output("owned UTF-8 string", name, &bytes);
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn failed_string_allocations_preserve_the_owner_and_bytes() {
    use std::os::unix::fs::PermissionsExt;
    for (name, when) in [
        ("alloc_string_alloc_failure", "1+"),
        ("alloc_string_growth_failure", "2+"),
    ] {
        let bytes = compile_fixture(name);
        let executable = common::TempArtifact::new("laniusc_string", name, None);
        executable.write_bytes(&bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        let normal = common::short_process_output_with_timeout(
            name,
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(normal.status.code(), Some(1), "{name}: {normal:?}");
        let trace = common::TempArtifact::new("laniusc_string", "allocation_trace", None);
        let injected = common::short_process_output_with_timeout(
            name,
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}"))
                .arg(executable.path()),
        );
        assert_eq!(injected.status.code(), Some(0), "{name}: {injected:?}");
        assert!(
            injected.stdout.is_empty() && injected.stderr.is_empty(),
            "{name}: {injected:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{name}: {events}"
        );
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn unicode_report_reads_validates_and_reverses_text() {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/unicode_text_report.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Unicode text report", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .expect("compile Unicode text report");
    let executable = common::TempArtifact::new("laniusc_string", "report", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    for (input_bytes, expected, status) in [
        (&b""[..], &b"0 0\n"[..], 0),
        (&b"abc"[..], &b"3 3\ncba"[..], 0),
        ("Aé🙂\0".as_bytes(), "8 4\n\0🙂éA".as_bytes(), 0),
        (&b"\xed\xa0\x80"[..], &b""[..], 2),
    ] {
        let input = common::TempArtifact::new("laniusc_string", "stdin", None);
        input.write_bytes(input_bytes);
        let output = common::short_process_output_with_timeout(
            "Unicode text report",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(
            output.status.code(),
            Some(status),
            "{input_bytes:?}: {output:?}"
        );
        assert_eq!(output.stdout, expected, "{input_bytes:?}: {output:?}");
        let stderr: &[u8] = if status == 2 {
            b"invalid UTF-8 input\n"
        } else {
            b""
        };
        assert_eq!(output.stderr, stderr, "{input_bytes:?}: {output:?}");
    }
}
