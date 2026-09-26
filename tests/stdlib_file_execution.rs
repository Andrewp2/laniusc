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
fn std_file_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/file.lani");
    let fixtures = format!(
        "{}{}{}",
        include_str!("fixtures/stdlib_host/std_file_write.lani"),
        include_str!("fixtures/stdlib_host/std_file_copy.lani"),
        include_str!("fixtures/stdlib_host/std_file_read.lani")
    );
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
    assert_eq!(count, 5);
}
