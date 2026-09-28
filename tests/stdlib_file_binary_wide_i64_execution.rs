mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed full-width binary file fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], path: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;

    std::fs::write(path, bytes).expect("write native ELF");
    let mut permissions = std::fs::metadata(path)
        .expect("stat native ELF")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(path, permissions).expect("chmod native ELF");
}

#[test]
fn signed_full_width_binary_file_read_and_write_execute_on_x86() {
    let bytes = compile_fixture("std_file_binary_wide_i64");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let dir = common::TempArtifact::new("laniusc_std_file_binary_wide", "run_dir", None);
        std::fs::create_dir(dir.path()).expect("create file fixture directory");
        let boundary = format!("-{:b}", 1u64 << 32);
        let negative = "-1101";
        let maximum = format!("{:b}", i64::MAX);
        let minimum = format!("-1{}", "0".repeat(63));
        let minimum_prefixed = format!("-0b1{}", "0".repeat(63));
        let exact = format!("             {minimum_prefixed}");
        assert_eq!(exact.len(), 80);
        for (name, input) in [
            ("zero.txt", b"0".as_slice()),
            ("negative.txt", b"-0b1101".as_slice()),
            ("boundary.txt", format!("-0B1{}", "0".repeat(32)).as_bytes()),
            ("max.txt", maximum.as_bytes()),
            ("min.txt", minimum_prefixed.as_bytes()),
            ("space.txt", b" \t-0B10100101\r\n".as_slice()),
            ("plus.txt", b"+0B1101".as_slice()),
            ("negative_zero.txt", b"-0".as_slice()),
            ("exact80.txt", exact.as_bytes()),
            ("excess81.txt", format!("{exact} ").as_bytes()),
            (
                "positive_overflow.txt",
                format!("1{}", "0".repeat(63)).as_bytes(),
            ),
            (
                "negative_overflow.txt",
                format!("-1{}1", "0".repeat(62)).as_bytes(),
            ),
            ("prefix.txt", b"-0b".as_slice()),
            ("sign.txt", b"+".as_slice()),
            ("bad.txt", b"0b1 0".as_slice()),
            ("empty.txt", b"".as_slice()),
        ] {
            std::fs::write(dir.path().join(name), input).expect("write signed binary input");
        }
        let exe = dir.path().join("binary_file_wide");
        executable(&bytes, &exe);
        let output = common::short_process_output_with_timeout(
            "signed full-width binary file round trip",
            std::process::Command::new(&exe).current_dir(dir.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        for (name, expected) in [
            ("zero_out.txt", "0".to_owned()),
            ("negative_out.txt", negative.to_owned()),
            ("boundary_out.txt", boundary),
            ("max_out.txt", maximum),
            ("min_out.txt", minimum),
        ] {
            assert_eq!(
                std::fs::read(dir.path().join(name)).expect("read signed binary output"),
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
fn signed_full_width_binary_file_failures_are_reported_on_x86() {
    let read_bytes = compile_fixture("std_file_binary_wide_i64_read_failure");
    let write_bytes = compile_fixture("std_file_binary_wide_i64_write_failure");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let dir = common::TempArtifact::new("laniusc_std_file_binary_wide", "fault_dir", None);
        std::fs::create_dir(dir.path()).expect("create fault directory");
        std::fs::write(dir.path().join("valid.txt"), b"-10101").expect("write valid binary input");
        let read_exe = dir.path().join("binary_read_failure");
        let write_exe = dir.path().join("binary_write_failure");
        executable(&read_bytes, &read_exe);
        executable(&write_bytes, &write_exe);
        for injection in [
            "read:error=EIO:when=1",
            "read:retval=2:when=1",
            "close:error=EIO:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed full-width binary file {injection}"),
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
                format!("signed full-width binary file {injection}"),
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
fn every_public_signed_full_width_binary_file_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/file_binary_wide_i64.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_file_binary_wide_i64.lani"),
        include_str!("fixtures/stdlib_host/std_file_binary_wide_i64_read_failure.lani"),
        include_str!("fixtures/stdlib_host/std_file_binary_wide_i64_write_failure.lani"),
    ]
    .concat();
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 2);
    for name in names {
        assert!(fixtures.contains(&format!("std::file_binary_wide_i64::{name}(")));
    }
}
