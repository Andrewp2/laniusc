mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed full-width binary stream fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_io_binary_wide_i64", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).unwrap();
    executable
}

#[test]
fn signed_full_width_binary_writer_executes_on_x86() {
    let bytes = compile_fixture("std_io_binary_wide_i64_write");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "signed wide binary writer",
            "wide_i64_binary_writer",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        let expected = format!("0\n-1\n-1101\n{}\n-1{}\n", "1".repeat(63), "0".repeat(63));
        assert_eq!(output.stdout, expected.as_bytes());
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn bounded_signed_full_width_binary_reader_executes_on_x86() {
    let bytes = compile_fixture("std_io_binary_wide_i64_read");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let executable = write_executable(&bytes, "wide_i64_binary_reader");
        let maximum = "1".repeat(63);
        let minimum = format!("-0b1{}", "0".repeat(63));
        let canonical_minimum = format!("-1{}", "0".repeat(63));
        let cases: Vec<(Vec<u8>, Vec<u8>)> = vec![
            (b"0".to_vec(), b"0".to_vec()),
            (b"-0".to_vec(), b"0".to_vec()),
            (b"+0B1101".to_vec(), b"1101".to_vec()),
            (b" \t-0b1101\r\n".to_vec(), b"-1101".to_vec()),
            (maximum.as_bytes().to_vec(), maximum.as_bytes().to_vec()),
            (
                minimum.as_bytes().to_vec(),
                canonical_minimum.as_bytes().to_vec(),
            ),
            (b"-00".to_vec(), b"0".to_vec()),
            (b"".to_vec(), b"111111101110".to_vec()),
            (b"+".to_vec(), b"111111101110".to_vec()),
            (b"-0b".to_vec(), b"111111101110".to_vec()),
            (b"0b1 0".to_vec(), b"111111101110".to_vec()),
            (b"0b0b1".to_vec(), b"111111101110".to_vec()),
            (b"0b-1".to_vec(), b"111111101110".to_vec()),
            (
                format!("1{}", "0".repeat(63)).into_bytes(),
                b"111111101110".to_vec(),
            ),
            (
                format!("-1{}1", "0".repeat(62)).into_bytes(),
                b"111111101110".to_vec(),
            ),
            (
                format!("1{}", "0".repeat(64)).into_bytes(),
                b"111111101110".to_vec(),
            ),
            (b"0b12".to_vec(), b"111111101110".to_vec()),
        ];
        for (input, expected) in cases {
            let source = common::TempArtifact::new("laniusc_std_io_binary_wide_i64", "input", None);
            source.write_bytes(&input);
            let output = common::short_process_output_with_timeout(
                format!("signed wide binary stdin {input:?}"),
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(source.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(0), "{input:?}: {output:?}");
            assert_eq!(output.stdout, expected, "{input:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{input:?}: {output:?}");
        }
        let mut exact = vec![b' '; 18];
        exact.extend_from_slice(minimum.as_bytes());
        assert_eq!(exact.len(), 85);
        let source = common::TempArtifact::new("laniusc_std_io_binary_wide_i64", "exact", None);
        source.write_bytes(&exact);
        let output = common::short_process_output_with_timeout(
            "signed wide binary exact limit",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(source.path()).unwrap(),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, canonical_minimum.as_bytes(), "{output:?}");
        exact.push(b' ');
        source.write_bytes(&exact);
        let output = common::short_process_output_with_timeout(
            "signed wide binary over limit",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(source.path()).unwrap(),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"111111101110", "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn signed_full_width_binary_io_reports_host_failures_on_x86() {
    let write_bytes = compile_fixture("std_io_binary_wide_i64_write_failure");
    let read_bytes = compile_fixture("std_io_binary_wide_i64_read");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let writer = write_executable(&write_bytes, "wide_i64_binary_write_failure");
        for (injection, expected_stdout) in [
            ("write:retval=0:when=1", b"".as_slice()),
            ("write:error=EIO:when=1", b"".as_slice()),
            ("write:retval=0:when=2", b"-".as_slice()),
            ("write:error=EIO:when=2", b"-".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed wide binary write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(writer.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
        let reader = write_executable(&read_bytes, "wide_i64_binary_read_failure");
        let source =
            common::TempArtifact::new("laniusc_std_io_binary_wide_i64", "fault_input", None);
        source.write_bytes(b"-1101");
        for injection in [
            "read:error=EIO:when=1",
            "read:error=EIO:when=2",
            "read:retval=0:when=1",
            "read:retval=2:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed wide binary read {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(reader.path())
                    .stdin(std::process::Stdio::from(
                        std::fs::File::open(source.path()).unwrap(),
                    )),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, b"111111101110", "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (write_bytes, read_bytes);
}

#[test]
fn every_public_signed_full_width_binary_io_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/io_binary_wide_i64.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_io_binary_wide_i64_write.lani"),
        include_str!("fixtures/stdlib_host/std_io_binary_wide_i64_write_failure.lani"),
        include_str!("fixtures/stdlib_host/std_io_binary_wide_i64_read.lani"),
    ]
    .concat();
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 2);
    for name in names {
        assert!(fixtures.contains(&format!("std::io_binary_wide_i64::{name}(")));
    }
}
