mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_in_directory(bytes: &[u8], directory: &std::path::Path, name: &str) -> std::process::Output {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = directory.join(name);
    std::fs::write(&exe_path, bytes).expect("write native ELF");
    let mut permissions = std::fs::metadata(&exe_path)
        .expect("stat native ELF")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&exe_path, permissions).expect("chmod native ELF");
    let mut command = std::process::Command::new(&exe_path);
    command.current_dir(directory);
    common::short_process_output_with_timeout(format!("run {name}"), &mut command)
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run_in_directory_with_stdin(
    bytes: &[u8],
    directory: &std::path::Path,
    name: &str,
    input: &[u8],
) -> std::process::Output {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = directory.join(name);
    std::fs::write(&exe_path, bytes).expect("write native ELF");
    let mut permissions = std::fs::metadata(&exe_path)
        .expect("stat native ELF")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&exe_path, permissions).expect("chmod native ELF");
    let source = common::TempArtifact::new("laniusc_std_file_copy", "stdin", None);
    source.write_bytes(input);
    let mut command = std::process::Command::new(&exe_path);
    command
        .current_dir(directory)
        .stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).expect("open copy input"),
        ));
    common::short_process_output_with_timeout(format!("run {name}"), &mut command)
}

#[test]
fn std_fs_raw_paths_honor_supplied_lengths_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/fs_path_lengths.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_fs_path_lengths", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile bounded raw filesystem paths");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_fs_path_lengths", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create run directory");
        let output = run_in_directory(&bytes, run_dir.path(), "std_fs_path_lengths");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("new.txt")).unwrap(),
            b"AB"
        );
        assert_eq!(std::fs::read(run_dir.path().join("path.txt")).unwrap(), b"");
        assert!(!run_dir.path().join("old.txt").exists());
        assert!(!run_dir.path().join("copy.txt").exists());
        assert!(!run_dir.path().join("old_dir").exists());
        assert!(!run_dir.path().join("new_dir").exists());
        assert!(!run_dir.path().join("old.txt.trailing").exists());
        assert!(!run_dir.path().join("new.txt.trailing").exists());
        assert!(!run_dir.path().join("copy.txt.trailing").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove run directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_fs_raw_paths_reject_invalid_bounds_and_embedded_nul_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/fs_path_errors.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_fs_path_errors", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile raw filesystem path errors");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_fs_path_errors", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create run directory");
        std::fs::write(run_dir.path().join("embedded.bin"), b"abcd\0tail")
            .expect("seed embedded NUL path bytes");
        let output = run_in_directory(&bytes, run_dir.path(), "std_fs_path_errors");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(std::fs::read_dir(run_dir.path()).unwrap().count(), 2);
        std::fs::remove_dir_all(run_dir.path()).expect("remove run directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_fs_raw_paths_accept_more_than_255_total_bytes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/fs_long_path.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_fs_long_path", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile long raw filesystem path");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let run_dir = common::TempArtifact::new("laniusc_std_fs_long_path", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create run directory");
        let first = "a".repeat(100);
        let second = "b".repeat(100);
        let file = "c".repeat(61);
        let relative = format!("{first}/{second}/{file}");
        assert_eq!(relative.len(), 263);
        std::fs::create_dir_all(run_dir.path().join(&first).join(&second))
            .expect("create long path parents");

        let exe_path = run_dir.path().join("std_fs_long_path");
        std::fs::write(&exe_path, &bytes).expect("write native ELF");
        let mut permissions = std::fs::metadata(&exe_path).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&exe_path, permissions).unwrap();
        let mut command = std::process::Command::new(&exe_path);
        command
            .current_dir(run_dir.path())
            .arg(format!("{relative}.ignored"));
        let output =
            common::short_process_output_with_timeout("run std_fs_long_path", &mut command);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join(&relative)).unwrap(),
            b"long"
        );
        assert!(!run_dir.path().join(format!("{relative}.ignored")).exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove run directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_text_once_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_write", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile std::file write helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create run directory");
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_write");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("note.txt")).expect("read written file"),
            b"xy"
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("empty.txt")).expect("read empty file"),
            b""
        );
        assert!(!run_dir.path().join("missing/child.txt").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove run directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_all_bytes_to_path_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_all_path.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_write_all_path", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile full path writer");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_write_all", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create write directory");
        let input: Vec<u8> = (0..37).map(|index| (index * 37 % 256) as u8).collect();
        std::fs::write(run_dir.path().join("input.bin"), &input).expect("write input file");
        std::fs::write(run_dir.path().join("seed.bin"), b"keep").expect("write seed file");
        std::fs::write(run_dir.path().join("short.bin"), b"a much longer old file")
            .expect("write old short file");

        let output = run_in_directory(&bytes, run_dir.path(), "std_file_write_all_path");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("copy.bin")).expect("read copied file"),
            input
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("short.bin")).expect("read truncated file"),
            input[..2]
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("empty.bin")).expect("read empty file"),
            b""
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("seed.bin")).expect("read unchanged seed"),
            b"keep"
        );
        assert!(!run_dir.path().join("missing/child.bin").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove write directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_all_bytes_to_path_reports_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_all_path_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("std_file_write_all_path_failure", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile full path writer failure fixture");

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
        let run_dir =
            common::TempArtifact::new("laniusc_std_file_write_all_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create write fault directory");
        let executable = run_dir.path().join("std_file_write_all_path_failure");
        std::fs::write(&executable, &bytes).expect("write fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod fault ELF");

        for (injection, expected_file) in [
            ("write:error=EIO:when=1", b"".as_slice()),
            ("close:error=EIO:when=1", b"abcd".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("path write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
            assert_eq!(
                std::fs::read(run_dir.path().join("fault.bin")).expect("read fault output"),
                expected_file,
                "{injection}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove write fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_copy_distinct_with_buffer_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_copy.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_copy", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile std::file copy helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_copy", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create copy run directory");
        let input: Vec<u8> = (0..137).map(|index| (index * 37 % 256) as u8).collect();
        std::fs::write(run_dir.path().join("input.bin"), &input).expect("write copy input");
        std::fs::write(run_dir.path().join("empty.bin"), b"").expect("write empty input");

        let output = run_in_directory(&bytes, run_dir.path(), "std_file_copy");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("copied.bin")).expect("read copied file"),
            input
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("empty-copy.bin")).expect("read empty copy"),
            b""
        );
        for absent in [
            "absent-copy.bin",
            "null-copy.bin",
            "zero-copy.bin",
            "huge-copy.bin",
        ] {
            assert!(!run_dir.path().join(absent).exists(), "unexpected {absent}");
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove copy run directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_once_into_buffer_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_read.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_read", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile std::file read helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_read", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create read run directory");
        let input: Vec<u8> = (0..64).map(|index| (index * 37 % 256) as u8).collect();
        std::fs::write(run_dir.path().join("input.bin"), &input).expect("write read input");
        std::fs::write(run_dir.path().join("short.bin"), b"abc").expect("write short input");
        std::fs::write(run_dir.path().join("empty.bin"), b"").expect("write empty input");

        let output = run_in_directory(&bytes, run_dir.path(), "std_file_read");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("prefix.bin")).expect("read copied prefix"),
            input[..16]
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("exact.bin")).expect("read exact prefix"),
            input[..16]
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("short-copy.bin")).expect("read short copy"),
            b"abc"
        );
        std::fs::remove_dir_all(run_dir.path()).expect("remove read run directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_to_end_into_buffer_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_read_to_end.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_read_to_end", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile read-to-end helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_read_to_end", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create read-to-end directory");
        let input: Vec<u8> = (0..37).map(|index| (index * 37 % 256) as u8).collect();
        std::fs::write(run_dir.path().join("input.bin"), &input).expect("write input file");
        std::fs::write(run_dir.path().join("empty.bin"), b"").expect("write empty file");

        let output = run_in_directory(&bytes, run_dir.path(), "std_file_read_to_end");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("copy.bin")).expect("read copied file"),
            input
        );
        std::fs::remove_dir_all(run_dir.path()).expect("remove read-to-end directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_to_end_into_buffer_handles_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_read_to_end_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_read_to_end_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile read-to-end failure fixture");

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
        let run_dir =
            common::TempArtifact::new("laniusc_std_file_read_to_end_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create read fault directory");
        std::fs::write(run_dir.path().join("input.bin"), [b'x'; 37])
            .expect("write read fault input");
        let executable = run_dir.path().join("std_file_read_to_end_failure");
        std::fs::write(&executable, &bytes).expect("write read fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat read fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod read fault ELF");

        for injection in [
            "read:error=EIO:when=1",
            "read:error=EIO:when=2",
            "close:error=EIO:when=1",
        ] {
            let output = common::short_process_output_with_timeout(
                format!("read-to-end {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove read fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_i32_decimal_or_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked decimal file reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_decimal", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create decimal run directory");
        for (name, contents) in [
            ("small.txt", "-42"),
            ("plus.txt", "+17"),
            ("zero.txt", "-0000"),
            ("max.txt", " \t+2147483647\r\n"),
            ("min.txt", "-2147483648"),
            ("overflow.txt", "2147483648"),
            ("underflow.txt", "-2147483649"),
            ("bad.txt", "12x"),
            ("embedded.txt", "1 2"),
            ("sign.txt", "-"),
            ("empty.txt", ""),
            ("space.txt", " \t\r\n"),
            ("long.txt", "123"),
            ("leading.txt", "0000000000000000000000000000000000000000"),
        ] {
            std::fs::write(run_dir.path().join(name), contents).expect("write decimal fixture");
        }

        let output = run_in_directory(&bytes, run_dir.path(), "std_file_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        std::fs::remove_dir_all(run_dir.path()).expect("remove decimal run directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_u32_decimal_or_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_u32_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_u32_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unsigned decimal file reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_u32", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create unsigned decimal directory");
        for (name, contents) in [
            ("zero.txt", "0"),
            ("plus.txt", " \t+17\r\n"),
            ("max.txt", "4294967295"),
            ("overflow.txt", "4294967296"),
            ("minus.txt", "-1"),
            ("bad.txt", "12x"),
            ("embedded.txt", "1 2"),
            ("sign.txt", "+"),
            ("spaced_sign.txt", "+ 1"),
            ("empty.txt", ""),
            ("space.txt", " \t\r\n"),
            ("long.txt", "123"),
            ("leading.txt", "0000000000000000000000000000000000000000"),
        ] {
            std::fs::write(run_dir.path().join(name), contents)
                .expect("write unsigned decimal fixture");
        }
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_u32_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        std::fs::remove_dir_all(run_dir.path()).expect("remove unsigned decimal directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_i32_decimal_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_write_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed decimal file writer");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_write_decimal", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create write decimal directory");
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_write_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        for (name, expected) in [
            ("zero.txt", "0"),
            ("negative.txt", "-42"),
            ("min.txt", "-2147483648"),
            ("max.txt", "2147483647"),
        ] {
            assert_eq!(
                std::fs::read(run_dir.path().join(name)).expect("read decimal output"),
                expected.as_bytes(),
                "{name}"
            );
        }
        assert!(!run_dir.path().join("missing/child.txt").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove write decimal directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_u32_decimal_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_u32_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_write_u32_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unsigned decimal file writer");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_write_u32", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create unsigned write directory");
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_write_u32_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        for (name, expected) in [
            ("zero.txt", "0"),
            ("forty_two.txt", "42"),
            ("max.txt", "4294967295"),
        ] {
            assert_eq!(
                std::fs::read(run_dir.path().join(name)).expect("read unsigned output"),
                expected.as_bytes(),
                "{name}"
            );
        }
        assert!(!run_dir.path().join("missing/child.txt").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove unsigned write directory");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_wide_decimal_reads_and_writes_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_wide_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_wide_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile two-word decimal file operations");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_wide_decimal", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create two-word decimal directory");
        for (name, contents) in [
            ("u_zero.txt", b"0".as_slice()),
            ("u_plus.txt", b" \t+17\r\n".as_slice()),
            ("u_max.txt", b"18446744073709551615".as_slice()),
            ("u_over.txt", b"18446744073709551616".as_slice()),
            ("u_minus.txt", b"-1".as_slice()),
            ("u_bad.txt", b"12 3".as_slice()),
            ("u_empty.txt", b"".as_slice()),
            ("u_leading.txt", b"00000000000000000042".as_slice()),
            ("i_zero.txt", b"-0".as_slice()),
            ("i_minus.txt", b" \t-42\r\n".as_slice()),
            ("i_max.txt", b"9223372036854775807".as_slice()),
            ("i_min.txt", b"-9223372036854775808".as_slice()),
            ("i_over.txt", b"9223372036854775808".as_slice()),
            ("i_under.txt", b"-9223372036854775809".as_slice()),
            ("i_bad.txt", b"--1".as_slice()),
            ("i_empty.txt", b"".as_slice()),
            ("i_leading.txt", b"-00000000000000000042".as_slice()),
        ] {
            std::fs::write(run_dir.path().join(name), contents).expect("write wide input fixture");
        }
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_wide_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("out_u.txt")).expect("read unsigned output"),
            b"18446744073709551615"
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("out_i.txt")).expect("read signed output"),
            b"-9223372036854775808"
        );
        assert!(!run_dir.path().join("missing/out.txt").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove wide decimal directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_wide_decimal_reports_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    for (name, valid) in [
        (
            "std_file_wide_u64_failure",
            b"18446744073709551615".as_slice(),
        ),
        (
            "std_file_wide_i64_failure",
            b"-9223372036854775808".as_slice(),
        ),
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
        let stdlib_root = stdlib_root.clone();
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile two-word decimal file failure fixture");

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
            let run_dir = common::TempArtifact::new("laniusc_std_file_wide_fault", name, None);
            std::fs::create_dir(run_dir.path()).expect("create wide fault directory");
            std::fs::write(run_dir.path().join("valid.txt"), valid)
                .expect("write valid wide decimal input");
            let executable = run_dir.path().join(name);
            std::fs::write(&executable, &bytes).expect("write wide fault ELF");
            let mut permissions = std::fs::metadata(&executable)
                .expect("stat wide fault ELF")
                .permissions();
            permissions.set_mode(0o700);
            std::fs::set_permissions(&executable, permissions).expect("chmod wide fault ELF");

            let baseline = run_in_directory(&bytes, run_dir.path(), name);
            assert_eq!(baseline.status.code(), Some(1), "{baseline:?}");
            assert_eq!(
                std::fs::read(run_dir.path().join("out.txt")).unwrap(),
                valid
            );
            for injection in [
                "read:error=EIO:when=1",
                "close:error=EIO:when=1",
                "write:error=EIO:when=1",
                "write:retval=0:when=1",
                "close:error=EIO:when=2",
            ] {
                let output = common::short_process_output_with_timeout(
                    format!("wide decimal file {name} {injection}"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-e")
                        .arg("trace=read,write,close")
                        .arg("-e")
                        .arg(format!("inject={injection}"))
                        .arg(&executable)
                        .current_dir(run_dir.path()),
                );
                assert_eq!(
                    output.status.code(),
                    Some(0),
                    "{name} {injection}: {output:?}"
                );
                assert!(
                    String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                    "fault was not injected: {output:?}"
                );
            }
            std::fs::remove_dir_all(run_dir.path()).expect("remove wide fault directory");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, valid);
    }
}

#[test]
fn std_file_narrow_decimal_reads_and_writes_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_narrow_decimal.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_narrow_decimal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile narrow decimal file operations");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_narrow_decimal", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create narrow decimal directory");
        for (name, contents) in [
            ("u8_max.txt", b"255".as_slice()),
            ("u8_over.txt", b"256".as_slice()),
            ("u16_max.txt", b"65535".as_slice()),
            ("u16_over.txt", b"65536".as_slice()),
            ("i8_min.txt", b"-128".as_slice()),
            ("i8_over.txt", b"-129".as_slice()),
            ("i16_min.txt", b"-32768".as_slice()),
            ("i16_over.txt", b"-32769".as_slice()),
            ("ordinary.txt", b" \t+42\r\n".as_slice()),
            ("bad.txt", b"12x".as_slice()),
            ("out_i8.txt", b"previous longer contents".as_slice()),
        ] {
            std::fs::write(run_dir.path().join(name), contents).expect("write narrow fixture");
        }
        let output = run_in_directory(&bytes, run_dir.path(), "std_file_narrow_decimal");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        for (name, expected) in [
            ("out_u8.txt", b"255".as_slice()),
            ("out_u16.txt", b"65535".as_slice()),
            ("out_i8.txt", b"-128".as_slice()),
            ("out_i16.txt", b"-32768".as_slice()),
        ] {
            assert_eq!(
                std::fs::read(run_dir.path().join(name)).expect("read narrow decimal output"),
                expected,
                "{name}"
            );
        }
        assert!(!run_dir.path().join("missing/out.txt").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove narrow decimal directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_i32_decimal_reports_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_decimal_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_write_decimal_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile decimal write failure fixture");

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
        let run_dir = common::TempArtifact::new("laniusc_std_file_write_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create write fault directory");
        let executable = run_dir.path().join("std_file_write_decimal_failure");
        std::fs::write(&executable, &bytes).expect("write decimal fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat decimal fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod decimal fault ELF");

        for (injection, expected_file) in [
            ("write:retval=0:when=2", b"4".as_slice()),
            ("write:error=EIO:when=2", b"4".as_slice()),
            ("close:error=EIO:when=1", b"42".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("decimal file write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
            assert_eq!(
                std::fs::read(run_dir.path().join("fault.txt")).expect("read written prefix"),
                expected_file,
                "{injection}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove write fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_write_u32_decimal_reports_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_write_u32_decimal_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("std_file_write_u32_decimal_failure", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile unsigned decimal write failure fixture");

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
        let run_dir =
            common::TempArtifact::new("laniusc_std_file_write_u32_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create unsigned write fault directory");
        let executable = run_dir.path().join("std_file_write_u32_decimal_failure");
        std::fs::write(&executable, &bytes).expect("write unsigned fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat unsigned fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod unsigned fault ELF");

        for (injection, expected_file) in [
            ("write:retval=0:when=2", b"4".as_slice()),
            ("write:error=EIO:when=2", b"4".as_slice()),
            ("close:error=EIO:when=1", b"42".as_slice()),
        ] {
            let output = common::short_process_output_with_timeout(
                format!("unsigned file write {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=write,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
            assert_eq!(
                std::fs::read(run_dir.path().join("fault.txt")).expect("read unsigned prefix"),
                expected_file,
                "{injection}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove unsigned write fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_i32_decimal_or_handles_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_decimal_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_decimal_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile decimal host failure fixture");

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
        let run_dir = common::TempArtifact::new("laniusc_std_file_decimal_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create fault run directory");
        std::fs::write(run_dir.path().join("valid.txt"), "42").expect("write valid decimal");
        let executable = run_dir.path().join("std_file_decimal_failure");
        std::fs::write(&executable, &bytes).expect("write decimal fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat decimal fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod decimal fault ELF");

        for injection in ["read:error=EIO:when=1", "close:error=EIO:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("decimal file {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove fault run directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_read_u32_decimal_or_handles_host_failures_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_u32_decimal_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_u32_decimal_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile unsigned decimal read failure fixture");

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
        let run_dir = common::TempArtifact::new("laniusc_std_file_u32_fault", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create unsigned read fault directory");
        std::fs::write(run_dir.path().join("valid.txt"), "42")
            .expect("write valid unsigned decimal");
        let executable = run_dir.path().join("std_file_u32_decimal_failure");
        std::fs::write(&executable, &bytes).expect("write unsigned read fault ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat unsigned read fault ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod unsigned read fault ELF");

        for injection in ["read:error=EIO:when=1", "close:error=EIO:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("unsigned file read {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=read,close")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(&executable)
                    .current_dir(run_dir.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
        }
        std::fs::remove_dir_all(run_dir.path()).expect("remove unsigned read fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_copies_between_files_and_standard_streams_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    let file_entry = root.join("tests/fixtures/stdlib_host/std_file_copy_stdout.lani");
    let file_root = stdlib_root.clone();
    let file_bytes = common::run_gpu_codegen_with_timeout("std_file_copy_stdout", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&file_entry, &file_root))
    })
    .expect("compile file-to-stdout copy");
    let stdin_entry = root.join("tests/fixtures/stdlib_host/std_file_copy_stdin.lani");
    let stdin_bytes = common::run_gpu_codegen_with_timeout("std_file_copy_stdin", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &stdin_entry,
            &stdlib_root,
        ))
    })
    .expect("compile stdin-to-file copy");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_copy", "run_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create copy directory");
        std::fs::write(run_dir.path().join("seed.bin"), b"keep")
            .expect("write unchanged seed file");
        for input in [b"".as_slice(), b"ABC".as_slice()] {
            std::fs::write(run_dir.path().join("input.bin"), input).expect("write file copy input");
            let output = run_in_directory(&file_bytes, run_dir.path(), "std_file_copy_stdout");
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(output.stdout, input);
            let output = run_in_directory_with_stdin(
                &stdin_bytes,
                run_dir.path(),
                "std_file_copy_stdin",
                input,
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert_eq!(
                std::fs::read(run_dir.path().join("output.bin")).unwrap(),
                input
            );
        }
        let binary: Vec<u8> = (0..517).map(|index| ((index * 37) % 256) as u8).collect();
        std::fs::write(run_dir.path().join("input.bin"), &binary).expect("write binary copy input");
        let output = run_in_directory(&file_bytes, run_dir.path(), "std_file_copy_stdout");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, binary);
        let output = run_in_directory_with_stdin(
            &stdin_bytes,
            run_dir.path(),
            "std_file_copy_stdin",
            &binary,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            std::fs::read(run_dir.path().join("output.bin")).unwrap(),
            binary
        );
        assert_eq!(
            std::fs::read(run_dir.path().join("seed.bin")).unwrap(),
            b"keep"
        );
        assert!(!run_dir.path().join("missing/output.bin").exists());
        std::fs::remove_dir_all(run_dir.path()).expect("remove copy directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (file_bytes, stdin_bytes);
}

#[test]
fn std_file_copy_stdin_to_file_reports_write_failure_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_file_copy_stdin_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_file_copy_stdin_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile stdin-to-file failure fixture");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_file_copy", "fault_dir", None);
        std::fs::create_dir(run_dir.path()).expect("create copy fault directory");
        let output = run_in_directory_with_stdin(
            &bytes,
            run_dir.path(),
            "std_file_copy_stdin_failure",
            b"ABCDEFGH",
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        std::fs::remove_dir_all(run_dir.path()).expect("remove copy fault directory");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_file_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/file.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_file_write.lani"),
        include_str!("fixtures/stdlib_host/std_file_write_all_path.lani"),
        include_str!("fixtures/stdlib_host/std_file_copy.lani"),
        include_str!("fixtures/stdlib_host/std_file_read.lani"),
        include_str!("fixtures/stdlib_host/std_file_read_to_end.lani"),
        include_str!("fixtures/stdlib_host/std_file_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_write_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_u32_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_write_u32_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_wide_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_narrow_decimal.lani"),
        include_str!("fixtures/stdlib_host/std_file_copy_stdout.lani"),
        include_str!("fixtures/stdlib_host/std_file_copy_stdin.lani"),
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
            fixtures.contains(&format!("std::file::{name}(")),
            "std::file::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 25);
}
