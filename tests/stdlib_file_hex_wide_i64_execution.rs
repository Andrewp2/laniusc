mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed full-width hex file fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], path: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;

    common::x86_jumps::write_x86_64_executable(path, bytes).expect("write native ELF");
    let mut permissions = std::fs::metadata(path)
        .expect("stat native ELF")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(path, permissions).expect("chmod native ELF");
}

#[test]
fn signed_full_width_hex_file_read_and_write_execute_on_x86() {
    let bytes = compile_fixture("std_file_hex_wide_i64");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let dir = common::TempArtifact::new("laniusc_std_file_hex_wide", "run_dir", None);
        std::fs::create_dir(dir.path()).expect("create file fixture directory");
        let pattern = "-123456789abcdef0";
        let pattern_upper = pattern.to_uppercase();
        let max = format!("{:X}", i64::MAX);
        let min = "-8000000000000000";
        let exact = format!("                {max}");
        assert_eq!(exact.len(), 32);
        for (name, input) in [
            ("zero.txt", b"0".as_slice()),
            ("pattern.txt", b"-0x123456789aBcDeF0".as_slice()),
            ("max.txt", max.as_bytes()),
            ("min.txt", b"-0x8000000000000000".as_slice()),
            ("space.txt", b" \t-0X1a2B\r\n".as_slice()),
            ("plus.txt", b"+0X1a2B".as_slice()),
            ("negative_zero.txt", b"-0".as_slice()),
            ("exact32.txt", exact.as_bytes()),
            ("excess33.txt", format!("{exact} ").as_bytes()),
            ("positive_overflow.txt", b"8000000000000000".as_slice()),
            ("negative_overflow.txt", b"-8000000000000001".as_slice()),
            ("prefix.txt", b"-0x".as_slice()),
            ("sign.txt", b"+".as_slice()),
            ("bad.txt", b"0x1 2".as_slice()),
            ("empty.txt", b"".as_slice()),
        ] {
            std::fs::write(dir.path().join(name), input).expect("write hex input");
        }
        let exe = dir.path().join("hex_file_wide");
        executable(&bytes, &exe);
        let output = common::short_process_output_with_timeout(
            "signed full-width hex file round trip",
            std::process::Command::new(&exe).current_dir(dir.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        for (name, expected) in [
            ("zero_out.txt", "0".to_owned()),
            ("pattern_lower_out.txt", pattern.to_owned()),
            ("pattern_upper_out.txt", pattern_upper),
            ("max_out.txt", max),
            ("min_out.txt", min.to_owned()),
        ] {
            assert_eq!(
                std::fs::read(dir.path().join(name)).expect("read hex output"),
                expected.as_bytes()
            );
        }
        assert!(!dir.path().join("missing/child.txt").exists());
        std::fs::remove_dir_all(dir.path()).expect("remove file fixture directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn signed_full_width_hex_file_failures_are_reported_on_x86() {
    let read_bytes = compile_fixture("std_file_hex_wide_i64_read_failure");
    let write_bytes = compile_fixture("std_file_hex_wide_i64_write_failure");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let dir = common::TempArtifact::new("laniusc_std_file_hex_wide", "fault_dir", None);
        std::fs::create_dir(dir.path()).expect("create fault directory");
        std::fs::write(dir.path().join("valid.txt"), b"ABCD").expect("write valid hex input");
        let read_exe = dir.path().join("hex_read_failure");
        let write_exe = dir.path().join("hex_write_failure");
        executable(&read_bytes, &read_exe);
        executable(&write_bytes, &write_exe);
        for injection in [
            "read:error=EIO:when=1",
            "read:retval=2:when=1",
            "close:error=EIO:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed full-width hex file {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&read_exe)
                    .current_dir(dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
        for injection in [
            "write:retval=0:when=1",
            "write:error=EIO:when=2",
            "close:error=EIO:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed full-width hex file {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&write_exe)
                    .current_dir(dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
        std::fs::remove_dir_all(dir.path()).expect("remove fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (read_bytes, write_bytes);
}

#[test]
fn every_public_signed_full_width_hex_file_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/file_hex_wide_i64.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_file_hex_wide_i64.lani"),
        include_str!("fixtures/stdlib_host/std_file_hex_wide_i64_read_failure.lani"),
        include_str!("fixtures/stdlib_host/std_file_hex_wide_i64_write_failure.lani"),
    ]
    .concat();
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 3);
    for name in names {
        assert!(fixtures.contains(&format!("std::file_hex_wide_i64::{name}(")));
    }
}
