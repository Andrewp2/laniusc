mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile binary file fixture")
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
fn binary_file_readers_and_writers_execute_on_x86() {
    let bytes = compile_fixture("std_file_binary");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let dir = common::TempArtifact::new("laniusc_std_file_binary", "run_dir", None);
        std::fs::create_dir(dir.path()).expect("create file fixture directory");
        for (name, input) in [
            ("space.txt", b" \t0B10100101\r\n".as_slice()),
            ("max.txt", b"11111111111111111111111111111111".as_slice()),
            ("zero.txt", b"0".as_slice()),
            (
                "overflow.txt",
                b"100000000000000000000000000000000".as_slice(),
            ),
            ("prefix.txt", b"0b".as_slice()),
            ("bad.txt", b"0b1 0".as_slice()),
            ("empty.txt", b"".as_slice()),
            ("byte.txt", b"0b11111111".as_slice()),
            ("wide.txt", b"100000000".as_slice()),
            ("half.txt", b"1000000000000001".as_slice()),
            ("too_wide.txt", b"10000000000000000".as_slice()),
        ] {
            std::fs::write(dir.path().join(name), input).expect("write binary input");
        }
        let exe = dir.path().join("binary_file");
        executable(&bytes, &exe);
        let output = common::short_process_output_with_timeout(
            "binary file round trip",
            std::process::Command::new(&exe).current_dir(dir.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        for (name, expected) in [
            ("byte_out.txt", b"11111111".as_slice()),
            ("half_out.txt", b"1000000000000001".as_slice()),
            ("zero_out.txt", b"0".as_slice()),
            (
                "max_out.txt",
                b"11111111111111111111111111111111".as_slice(),
            ),
        ] {
            assert_eq!(
                std::fs::read(dir.path().join(name)).expect("read binary output"),
                expected
            );
        }
        assert!(!dir.path().join("missing/child.txt").exists());
        std::fs::remove_dir_all(dir.path()).expect("remove file fixture directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn binary_file_failures_are_reported_on_x86() {
    let read_bytes = compile_fixture("std_file_binary_read_failure");
    let write_bytes = compile_fixture("std_file_binary_write_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let dir = common::TempArtifact::new("laniusc_std_file_binary", "fault_dir", None);
        std::fs::create_dir(dir.path()).expect("create fault directory");
        std::fs::write(dir.path().join("valid.txt"), b"1010").expect("write valid binary input");
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
                format!("binary file {injection}"),
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
        for injection in ["write:error=EIO:when=1", "close:error=EIO:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("binary file {injection}"),
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
fn binary_file_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/file_binary.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_file_binary.lani");
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
            fixture.contains(&format!("std::file_binary::{name}(")),
            "std::file_binary::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 6);
}
