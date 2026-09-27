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
fn hexadecimal_stream_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_hex.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_io_hex.lani");
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
    assert_eq!(count, 6);
}
