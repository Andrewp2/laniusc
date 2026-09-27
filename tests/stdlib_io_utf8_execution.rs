mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile UTF-8 stream fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_utf8", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat UTF-8 stream fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod UTF-8 stream fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_with_input(executable: &common::TempArtifact, input_bytes: &[u8]) -> std::process::Output {
    let input = common::TempArtifact::new("laniusc_std_io_utf8", "input", None);
    input.write_bytes(input_bytes);
    common::short_process_output_with_timeout(
        "UTF-8 scalar I/O",
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).expect("open UTF-8 input"),
        )),
    )
}

#[test]
fn utf8_scalar_io_executes_on_x86() {
    let bytes = compile_fixture("std_io_utf8");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_utf8");
        let output = run_with_input(
            &executable,
            b"A\xc2\xa2\xe2\x82\xac\xf0\x9f\x99\x82\xf4\x8f\xbf\xbf",
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout, b"A\xf0\x9f\x99\x82\xf4\x8f\xbf\xbf",
            "{output:?}"
        );
        assert_eq!(output.stderr, b"\xc2\xa2\xe2\x82\xac", "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn utf8_scalar_io_rejects_malformed_and_truncated_sequences() {
    let cases: &[(&str, &[u8])] = &[
        ("std_io_utf8_invalid", b"\xc0A\xe2A\x80\xe0\x80\x80B"),
        ("std_io_utf8_truncated", b"\xf0\x9f"),
    ];
    for &(name, input) in cases {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let output = run_with_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, input);
    }
}

#[test]
fn utf8_scalar_io_reports_host_failures() {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, syscall, injection, expected_stdout) in [
            (
                "std_io_utf8_read_error",
                "read",
                "read:error=EIO:when=2",
                b"".as_slice(),
            ),
            (
                "std_io_utf8_write_error",
                "write",
                "write:error=EIO:when=2",
                b"\xc2".as_slice(),
            ),
        ] {
            let bytes = compile_fixture(name);
            let executable = write_executable(&bytes, name);
            let input = common::TempArtifact::new("laniusc_std_io_utf8", "fault_input", None);
            input.write_bytes(b"\xc2\xa2");
            let trace = common::TempArtifact::new("laniusc_std_io_utf8", "fault_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("UTF-8 scalar {syscall} failure"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-o")
                    .arg(trace.path())
                    .arg("-e")
                    .arg(format!("trace={syscall}"))
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(input.path()).expect("open fault input"),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert_eq!(output.stdout, expected_stdout, "{name}: {output:?}");
            assert!(
                std::fs::read_to_string(trace.path())
                    .expect("read fault trace")
                    .contains("INJECTED"),
                "{name}: host fault was not injected"
            );
        }
    }
}

#[test]
fn utf8_scalar_io_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_utf8.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_io_utf8.lani");
    let mut count = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        assert!(
            fixture.contains(&format!("std::io_utf8::{name}(")),
            "std::io_utf8::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}
