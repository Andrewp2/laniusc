mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile LF line I/O fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_line", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat LF line fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod LF line fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_with_input(executable: &common::TempArtifact, input_bytes: &[u8]) -> std::process::Output {
    let input = common::TempArtifact::new("laniusc_std_io_line", "line_input", None);
    input.write_bytes(input_bytes);
    common::short_process_output_with_timeout(
        "LF line I/O",
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).expect("open LF line input"),
        )),
    )
}

#[test]
fn lf_line_io_executes_on_x86() {
    let bytes = compile_fixture("std_io_line_codes");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_line_codes");
        let output = run_with_input(&executable, b"AB\n\nXYZW\nQ");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"AB\n\nXYZW\nQ\n", "{output:?}");
        assert_eq!(output.stderr, b"AB\n", "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn utf8_line_counter_composes_line_io_validation_and_decimal_output() {
    let bytes = compile_fixture("std_utf8_line_count");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_utf8_line_count");
        let cases: &[(&[u8], i32, &[u8])] = &[
            (b"A\xc2\xa2\xe2\x82\xac\xf0\x9f\x99\x82\n", 0, b"4\n"),
            (b"A\0B\n", 0, b"3\n"),
            (b"\n", 0, b"0\n"),
            (b"\xc2\xa2", 0, b"1\n"),
            (b"\xc0\x80\n", 3, b""),
            (b"\xe2\x82\n", 3, b""),
            (b"abcdefghijklmnopq\n", 2, b""),
            (b"", 2, b""),
        ];
        for &(input, expected_exit, expected_stdout) in cases {
            let output = run_with_input(&executable, input);
            assert_eq!(output.status.code(), Some(expected_exit), "{input:?}: {output:?}");
            assert_eq!(output.stdout, expected_stdout, "{input:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{input:?}: {output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn lf_line_io_consumes_overflow_and_handles_binary_boundaries() {
    let bytes = compile_fixture("std_io_line_codes_edges");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_line_codes_edges");
        let output = run_with_input(&executable, b"ABCDE\nZ\n\nA\n\r\nWXYZ\n\0\n");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn lf_line_io_reports_host_failures() {
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
                "std_io_line_codes_read_error",
                "read",
                "read:error=EIO:when=1",
                b"".as_slice(),
            ),
            (
                "std_io_line_codes_write_error",
                "write",
                "write:error=EIO:when=2",
                b"A".as_slice(),
            ),
        ] {
            let bytes = compile_fixture(name);
            let executable = write_executable(&bytes, name);
            let input = common::TempArtifact::new("laniusc_std_io_line", "fault_input", None);
            input.write_bytes(b"A");
            let trace = common::TempArtifact::new("laniusc_std_io_line", "fault_trace", None);
            let output = common::short_process_output_with_timeout(
                format!("LF line {syscall} failure"),
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
fn lf_line_io_traps_on_overstated_backing_capacity() {
    let bytes = compile_fixture("std_io_line_codes_bounds");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "std_io_line_codes_bounds");
        let output = run_with_input(&executable, b"AB\n");
        assert_eq!(output.status.code(), Some(101), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn lf_line_io_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_line.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_io_line_codes.lani");
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
            fixture.contains(&format!("std::io_line::{name}(")),
            "std::io_line::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}
