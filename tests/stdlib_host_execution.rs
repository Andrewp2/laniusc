mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn std_io_lines_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_lines.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_lines", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile std::io line helpers");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_io_lines", "std_io_lines", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"alpha\ngamma\n\nomega-42!\n");
        assert_eq!(output.stderr, b"beta\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_io_write_u32_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_u32.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_u32", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unsigned decimal writer");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_io_u32", "std_io_u32", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"0\n42\n1000000000\n4294967295\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_io_write_u32_reports_partial_write_failure_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_u32_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_u32_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unsigned decimal failure fixture");

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
        let executable = common::TempArtifact::new("laniusc_std_io", "std_io_u32_failure", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat unsigned decimal fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod unsigned decimal fixture");

        for (injection, expected_exit) in
            [("write:retval=0:when=2", 1), ("write:error=EIO:when=2", 5)]
        {
            let output = common::short_process_output_with_timeout(
                format!("unsigned decimal write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(expected_exit), "{output:?}");
            assert_eq!(output.stdout, b"4", "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
