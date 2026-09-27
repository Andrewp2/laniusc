mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile binary stream fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_binary", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat binary fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod binary fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_input(executable: &common::TempArtifact, input: &[u8]) -> std::process::Output {
    let source = common::TempArtifact::new("laniusc_std_io_binary", "input", None);
    source.write_bytes(input);
    common::short_process_output_with_timeout(
        format!("binary stdin {input:?}"),
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).expect("open binary input"),
        )),
    )
}

#[test]
fn binary_stream_writers_execute_on_x86() {
    let bytes = compile_fixture("std_io_binary_write");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_io_binary_write", "std_io_binary_write", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout,
            b"0\n10100101\n11111111111111111111111111111111\n101\n11111111\n1000000000000001\n1111111111111111\n"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn binary_stream_writer_reports_host_failures_on_x86() {
    let bytes = compile_fixture("std_io_binary_write_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "write_failure");
        for (injection, expected_stdout) in [
            ("write:retval=0:when=1", b"".as_slice()),
            ("write:error=EIO:when=1", b"".as_slice()),
            ("write:retval=0:when=2", b"1".as_slice()),
            ("write:error=EIO:when=2", b"1".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("binary write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_binary_stdin_readers_execute_on_x86() {
    for name in [
        "std_io_binary_read_u32",
        "std_io_binary_read_u16",
        "std_io_binary_read_u8",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let cases: &[(&[u8], &[u8])] = match name {
                "std_io_binary_read_u32" => &[
                    (b"0", b"0"),
                    (b"1", b"1"),
                    (b" \t0B10100101\r\n", b"10100101"),
                    (
                        b"0b11111111111111111111111111111111",
                        b"11111111111111111111111111111111",
                    ),
                    (b"00", b"0"),
                    (b"", b"1100001001"),
                    (b" \t\n", b"1100001001"),
                    (b"0b", b"1100001001"),
                    (b"0B ", b"1100001001"),
                    (b"2", b"1100001001"),
                    (b"+1", b"1100001001"),
                    (b"-1", b"1100001001"),
                    (b"0b1 0", b"1100001001"),
                    (b"00b1", b"1100001001"),
                    (b"1\0", b"1100001001"),
                    (b"100000000000000000000000000000000", b"1100001001"),
                ],
                "std_io_binary_read_u16" => &[
                    (b"0", b"0"),
                    (b"0b1000000000000001", b"1000000000000001"),
                    (b"1111111111111111", b"1111111111111111"),
                    (b"10000000000000000", b"1001101"),
                    (b"0b", b"1001101"),
                    (b"10x1", b"1001101"),
                ],
                "std_io_binary_read_u8" => &[
                    (b"0", b"0"),
                    (b"0B10100101", b"10100101"),
                    (b"11111111", b"11111111"),
                    (b"100000000", b"111"),
                    (b"0b", b"111"),
                    (b"102", b"111"),
                ],
                _ => unreachable!(),
            };
            for &(input, expected) in cases {
                let output = run_input(&executable, input);
                assert_eq!(
                    output.status.code(),
                    Some(0),
                    "{name} {input:?}: {output:?}"
                );
                assert_eq!(output.stdout, expected, "{name} {input:?}");
                assert!(output.stderr.is_empty(), "{output:?}");
            }
            if name == "std_io_binary_read_u32" {
                let mut exact = vec![b' '; 6];
                exact.extend_from_slice(b"0b11111111111111111111111111111111");
                let output = run_input(&executable, &exact);
                assert_eq!(
                    output.stdout, b"11111111111111111111111111111111",
                    "{output:?}"
                );
                exact.push(b' ');
                let output = run_input(&executable, &exact);
                assert_eq!(output.stdout, b"1100001001", "{output:?}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn bounded_binary_stdin_reader_reports_host_failure_on_x86() {
    let bytes = compile_fixture("std_io_binary_read_u32");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "read_failure");
        let source = common::TempArtifact::new("laniusc_std_io_binary", "fault_input", None);
        source.write_bytes(b"0b1010");
        for injection in [
            "read:error=EIO:when=1",
            "read:error=EIO:when=2",
            "read:retval=0:when=1",
            "read:retval=2:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("binary read {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(source.path()).expect("open fault input"),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, b"1100001001", "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn binary_stream_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_binary.lani");
    let fixture = [
        include_str!("fixtures/stdlib_host/std_io_binary_write.lani"),
        include_str!("fixtures/stdlib_host/std_io_binary_read_u32.lani"),
        include_str!("fixtures/stdlib_host/std_io_binary_read_u16.lani"),
        include_str!("fixtures/stdlib_host/std_io_binary_read_u8.lani"),
    ]
    .concat();
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
            fixture.contains(&format!("std::io_binary::{name}(")),
            "std::io_binary::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 6);
}
