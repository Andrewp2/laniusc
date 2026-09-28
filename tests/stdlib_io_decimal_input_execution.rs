mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile bounded decimal stdin fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_decimal_stdin", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat decimal stdin fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod decimal stdin fixture");
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_input(executable: &common::TempArtifact, input: &[u8]) -> std::process::Output {
    let source = common::TempArtifact::new("laniusc_decimal_stdin", "input", None);
    source.write_bytes(input);
    common::short_process_output_with_timeout(
        format!("decimal stdin {:?}", input),
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).expect("open decimal input"),
        )),
    )
}

#[test]
fn bounded_unsigned_stdin_decimal_executes_on_x86() {
    let bytes = compile_fixture("std_io_decimal_read_u32");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "read_u32");
        let cases: &[(&[u8], &[u8])] = &[
            (b"0", b"0"),
            (b"42", b"42"),
            (b" \t+42\r\n", b"42"),
            (b"4294967295", b"4294967295"),
            (b"", b"777"),
            (b"  ", b"777"),
            (b"+", b"777"),
            (b"-1", b"777"),
            (b"12 3", b"777"),
            (b"12x", b"777"),
            (b"++1", b"777"),
            (b"4294967296", b"777"),
        ];
        for &(input, expected) in cases {
            let output = run_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "input={input:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        let mut exact = vec![b' '; 22];
        exact.extend_from_slice(b"4294967295");
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"4294967295");
        exact.push(b' ');
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"777");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_signed_stdin_decimal_executes_on_x86() {
    let bytes = compile_fixture("std_io_decimal_read_i32");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "read_i32");
        let cases: &[(&[u8], &[u8])] = &[
            (b"0", b"0"),
            (b"-42", b"-42"),
            (b"+2147483647", b"2147483647"),
            (b"-2147483648", b"-2147483648"),
            (b" \t-0\r\n", b"0"),
            (b"", b"-777"),
            (b"  ", b"-777"),
            (b"-", b"-777"),
            (b"1 2", b"-777"),
            (b"12x", b"-777"),
            (b"--1", b"-777"),
            (b"2147483648", b"-777"),
            (b"-2147483649", b"-777"),
        ];
        for &(input, expected) in cases {
            let output = run_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "input={input:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        let mut exact = vec![b' '; 21];
        exact.extend_from_slice(b"-2147483648");
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"-2147483648");
        exact.push(b' ');
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"-777");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_wide_unsigned_stdin_decimal_executes_on_x86() {
    let bytes = compile_fixture("std_io_decimal_read_wide_u64");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "read_wide_u64");
        let cases: &[(&[u8], &[u8])] = &[
            (b"0", b"0"),
            (b"4294967296", b"4294967296"),
            (b" \t+42\r\n", b"42"),
            (b"00000000000000000042", b"42"),
            (b"18446744073709551615", b"18446744073709551615"),
            (b"", b"777"),
            (b"  ", b"777"),
            (b"+", b"777"),
            (b"-1", b"777"),
            (b"12 3", b"777"),
            (b"12x", b"777"),
            (b"18446744073709551616", b"777"),
        ];
        for &(input, expected) in cases {
            let output = run_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "input={input:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        let mut exact = vec![b' '; 44];
        exact.extend_from_slice(b"18446744073709551615");
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"18446744073709551615");
        exact.push(b' ');
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"777");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_wide_signed_stdin_decimal_executes_on_x86() {
    let bytes = compile_fixture("std_io_decimal_read_wide_i64");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "read_wide_i64");
        let cases: &[(&[u8], &[u8])] = &[
            (b"0", b"0"),
            (b"-0", b"0"),
            (b"-4294967296", b"-4294967296"),
            (b" \t+42\r\n", b"42"),
            (b"-00000000000000000042", b"-42"),
            (b"9223372036854775807", b"9223372036854775807"),
            (b"-9223372036854775808", b"-9223372036854775808"),
            (b"", b"-777"),
            (b"  ", b"-777"),
            (b"-", b"-777"),
            (b"1 2", b"-777"),
            (b"12x", b"-777"),
            (b"--1", b"-777"),
            (b"9223372036854775808", b"-777"),
            (b"-9223372036854775809", b"-777"),
        ];
        for &(input, expected) in cases {
            let output = run_input(&executable, input);
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected, "input={input:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        let mut exact = vec![b' '; 44];
        exact.extend_from_slice(b"-9223372036854775808");
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"-9223372036854775808");
        exact.push(b' ');
        let output = run_input(&executable, &exact);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"-777");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_stdin_decimal_reports_host_failures_on_x86() {
    let unsigned_bytes = compile_fixture("std_io_decimal_read_u32");
    let signed_bytes = compile_fixture("std_io_decimal_read_i32");
    let wide_unsigned_bytes = compile_fixture("std_io_decimal_read_wide_u64");
    let wide_signed_bytes = compile_fixture("std_io_decimal_read_wide_i64");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, bytes, fallback) in [
            ("u32", unsigned_bytes.as_slice(), b"777".as_slice()),
            ("i32", signed_bytes.as_slice(), b"-777".as_slice()),
            (
                "wide_u64",
                wide_unsigned_bytes.as_slice(),
                b"777".as_slice(),
            ),
            ("wide_i64", wide_signed_bytes.as_slice(), b"-777".as_slice()),
        ] {
            let executable = write_executable(bytes, name);
            for injection in [
                "read:error=EIO:when=1",
                "read:error=EIO:when=2",
                "read:retval=0:when=1",
                "read:retval=2:when=1",
            ] {
                let source =
                    common::TempArtifact::new("laniusc_decimal_stdin", "fault_input", None);
                source.write_bytes(b"42");
                let trace = common::TempArtifact::new("laniusc_decimal_stdin", "trace", None);
                let output = common::short_process_output_with_timeout(
                    format!("decimal stdin {name} {injection}"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-o")
                        .arg(trace.path())
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
                assert_eq!(output.stdout, fallback, "{output:?}");
                assert!(output.stderr.is_empty(), "{output:?}");
                let trace_text = std::fs::read_to_string(trace.path()).expect("read fault trace");
                assert!(trace_text.contains("INJECTED"), "{trace_text}");
            }
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (
        unsigned_bytes,
        signed_bytes,
        wide_unsigned_bytes,
        wide_signed_bytes,
    );
}

#[test]
fn bounded_narrow_stdin_decimal_executes_on_x86() {
    let fixtures = [
        ("std_io_decimal_read_u8", b"7".as_slice()),
        ("std_io_decimal_read_u16", b"777".as_slice()),
        ("std_io_decimal_read_i8", b"-7".as_slice()),
        ("std_io_decimal_read_i16", b"-777".as_slice()),
    ];
    for (name, fallback) in fixtures {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let executable = write_executable(&bytes, name);
            let cases: &[(&[u8], &[u8])] = match name {
                "std_io_decimal_read_u8" => &[
                    (b"0", b"0"),
                    (b"255", b"255"),
                    (b" +42\n", b"42"),
                    (b"256", fallback),
                    (b"-1", fallback),
                    (b"", fallback),
                    (b"12x", fallback),
                    (b"         255", b"255"),
                    (b"          255", fallback),
                ],
                "std_io_decimal_read_u16" => &[
                    (b"0", b"0"),
                    (b"65535", b"65535"),
                    (b"+42", b"42"),
                    (b"65536", fallback),
                    (b"-1", fallback),
                    (b"", fallback),
                    (b"12x", fallback),
                ],
                "std_io_decimal_read_i8" => &[
                    (b"0", b"0"),
                    (b"-128", b"-128"),
                    (b"127", b"127"),
                    (b"+42", b"42"),
                    (b"-129", fallback),
                    (b"128", fallback),
                    (b"", fallback),
                    (b"12x", fallback),
                ],
                "std_io_decimal_read_i16" => &[
                    (b"0", b"0"),
                    (b"-32768", b"-32768"),
                    (b"32767", b"32767"),
                    (b"+42", b"42"),
                    (b"-32769", fallback),
                    (b"32768", fallback),
                    (b"", fallback),
                    (b"12x", fallback),
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
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, fallback);
    }
}
