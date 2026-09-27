mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile hexadecimal stream fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_hex", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat hex fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod hex fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_input(executable: &common::TempArtifact, input: &[u8]) -> std::process::Output {
    let source = common::TempArtifact::new("laniusc_std_io_hex", "input", None);
    source.write_bytes(input);
    common::short_process_output_with_timeout(
        format!("hex stdin {input:?}"),
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).expect("open hex input"),
        )),
    )
}

#[test]
fn hexadecimal_stream_writers_execute_on_x86() {
    let bytes = compile_fixture("std_io_hex");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_io_hex", "std_io_hex", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout,
            b"0\nff\nAB\nbeef\nBEEF\n1a2b3c4d\n1A2B3C4D\nffffffff\n"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn hexadecimal_stream_writer_reports_partial_failures_on_x86() {
    let bytes = compile_fixture("std_io_hex_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = common::TempArtifact::new("laniusc_std_io_hex", "failure", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat hex fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).expect("chmod hex fixture");
        for (injection, expected_stdout) in [
            ("write:retval=0:when=1", b"".as_slice()),
            ("write:error=EIO:when=1", b"".as_slice()),
            ("write:retval=0:when=2", b"a".as_slice()),
            ("write:error=EIO:when=2", b"a".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("hex write {injection}"),
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
fn bounded_hexadecimal_stdin_readers_execute_on_x86() {
    for name in [
        "std_io_hex_read_u32",
        "std_io_hex_read_u8",
        "std_io_hex_read_u16",
    ] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let cases: &[(&[u8], &[u8])] = match name {
                "std_io_hex_read_u32" => &[
                    (b"0", b"0"),
                    (b"f", b"f"),
                    (b" \t0X1a2B\r\n", b"1a2b"),
                    (b"FFFFFFFF", b"ffffffff"),
                    (b"0xffffffff", b"ffffffff"),
                    (b"00", b"0"),
                    (b"", b"309"),
                    (b" \t\n", b"309"),
                    (b"0x", b"309"),
                    (b"0X ", b"309"),
                    (b"x1", b"309"),
                    (b"+1", b"309"),
                    (b"-1", b"309"),
                    (b"0x1 2", b"309"),
                    (b"00x1", b"309"),
                    (b"0x100000000", b"309"),
                    (b"100000000", b"309"),
                ],
                "std_io_hex_read_u8" => &[
                    (b"0", b"0"),
                    (b"ff", b"ff"),
                    (b"0XFF", b"ff"),
                    (b"aB", b"ab"),
                    (b"0x00", b"0"),
                    (b"100", b"7"),
                    (b"0x100", b"7"),
                    (b"", b"7"),
                    (b"gg", b"7"),
                ],
                "std_io_hex_read_u16" => &[
                    (b"0", b"0"),
                    (b"ffff", b"ffff"),
                    (b"0xBEEF", b"beef"),
                    (b"0x0001", b"1"),
                    (b"10000", b"309"),
                    (b"0X10000", b"309"),
                    (b"", b"309"),
                    (b"fffg", b"309"),
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
            if name == "std_io_hex_read_u32" {
                let mut exact = vec![b' '; 22];
                exact.extend_from_slice(b"0xFFFFFFFF");
                let output = run_input(&executable, &exact);
                assert_eq!(output.stdout, b"ffffffff", "{output:?}");
                exact.push(b' ');
                let output = run_input(&executable, &exact);
                assert_eq!(output.stdout, b"309", "{output:?}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn bounded_hexadecimal_stdin_reader_reports_host_failure_on_x86() {
    let bytes = compile_fixture("std_io_hex_read_u32");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "read_u32_failure");
        let source = common::TempArtifact::new("laniusc_std_io_hex", "fault_input", None);
        source.write_bytes(b"1a2b");
        for injection in [
            "read:error=EIO:when=1",
            "read:error=EIO:when=2",
            "read:retval=0:when=1",
            "read:retval=2:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("hex read {injection}"),
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
            assert_eq!(output.stdout, b"309", "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn hexadecimal_stream_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_hex.lani");
    let fixture = [
        include_str!("fixtures/stdlib_host/std_io_hex.lani"),
        include_str!("fixtures/stdlib_host/std_io_hex_read_u32.lani"),
        include_str!("fixtures/stdlib_host/std_io_hex_read_u8.lani"),
        include_str!("fixtures/stdlib_host/std_io_hex_read_u16.lani"),
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
            fixture.contains(&format!("std::io_hex::{name}(")),
            "std::io_hex::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 9);
}
