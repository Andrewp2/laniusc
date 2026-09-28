mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn selected_std_io_and_args_functions_have_runtime_cases() {
    let io_cases = format!(
        "{}{}",
        include_str!("fixtures/stdlib_host/std_io_lines.lani"),
        include_str!("fixtures/stdlib_host/std_io_flush_print.lani")
    );
    for name in [
        "write_line",
        "println",
        "eprintln",
        "flush_stdout",
        "flush_stderr",
        "print_i32",
    ] {
        assert!(
            io_cases.contains(&format!("std::io::{name}(")),
            "std::io::{name} lacks a runtime case"
        );
    }

    let args_source = include_str!("../stdlib/std/args_checked.lani");
    let args_cases = include_str!("fixtures/stdlib_host/std_args_checked.lani");
    let mut count = 0;
    for line in args_source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        assert!(
            args_cases.contains(&format!("std::args_checked::{name}(")),
            "std::args_checked::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}

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
fn std_io_flush_and_print_execute_with_real_stdlib_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_flush_print.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_flush_print", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile std::io flush and print helpers from the real stdlib");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_io_flush_print", "std_io_flush_print", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"before -42\n", "{output:?}");
        assert_eq!(output.stderr, b"error\n", "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_args_read_exact_into_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_args_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_args_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile bounded argument reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output_with_args(
            "std_args_checked",
            "std_args_checked",
            &bytes,
            &["alpha", ""],
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"alpha");
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
fn std_io_write_i32_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_i32.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_i32", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed decimal writer");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_io_i32", "std_io_i32", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout,
            b"0\n-42\n-2147483648\n2147483647\n-1000000000\n"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_io_write_wide_decimal_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_wide_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_wide_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile two-word decimal writers");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_io_wide_decimal", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout,
            b"0\n18446744073709551615\n-9223372036854775808\n9223372036854775807\n"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_io_narrow_decimal_writers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_narrow_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_narrow_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile narrow decimal writers");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_io_narrow_decimal", "std_io_narrow_decimal", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"0\n255\n65535\n-128\n127\n-32768\n32767\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_io_write_i32_reports_partial_write_failure_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_io_i32_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_io_i32_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed decimal failure fixture");

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
        let executable = common::TempArtifact::new("laniusc_std_io", "std_io_i32_failure", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat signed decimal fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod signed decimal fixture");

        for (injection, expected_exit, expected_stdout) in [
            ("write:retval=0:when=1", 1, b"".as_slice()),
            ("write:error=EIO:when=1", 5, b"".as_slice()),
            ("write:retval=0:when=2", 1, b"-".as_slice()),
            ("write:error=EIO:when=2", 5, b"-".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("signed decimal write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(expected_exit), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
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

#[test]
fn std_io_decimal_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/io_decimal.lani");
    let fixture = [
        include_str!("fixtures/stdlib_host/std_io_u32.lani"),
        include_str!("fixtures/stdlib_host/std_io_i32.lani"),
        include_str!("fixtures/stdlib_host/std_io_narrow_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_u32.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_i32.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_u8.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_u16.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_i8.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_i16.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_wide_u64.lani"),
        include_str!("fixtures/stdlib_host/std_io_decimal_read_wide_i64.lani"),
        include_str!("fixtures/stdlib_host/std_io_wide_decimal.lani"),
        include_str!("fixtures/stdlib_foundation/wide_u64_decimal_double.lani"),
        include_str!("fixtures/stdlib_foundation/wide_i64_decimal_double.lani"),
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
            fixture.contains(&format!("std::io_decimal::{name}(")),
            "std::io_decimal::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 16);
}
