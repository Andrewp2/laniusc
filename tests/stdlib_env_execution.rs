mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn std_env_var_read_exact_into_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile bounded environment reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_std_env", "std_env_checked", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat environment fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod environment fixture");

        let output = common::short_process_output_with_timeout(
            "std_env_checked",
            std::process::Command::new(executable.path())
                .env("L", "bravo")
                .env("E", "")
                .env_remove("M"),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"bravo");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_env_var_key_read_exact_into_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_keys_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_keys_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked environment key reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_std_env", "std_env_keys_checked", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat environment key fixture")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod environment key fixture");

        let output = common::short_process_output_with_timeout(
            "std_env_keys_checked",
            std::process::Command::new(executable.path())
                .env_clear()
                .env("A", "alpha")
                .env("B", "beta"),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout == b"AB" || output.stdout == b"BA",
            "{output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_env_current_dir_read_into_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_current_dir_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_current_dir_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked current directory reader");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let run_dir = common::TempArtifact::new("lcwd", "run", None);
        std::fs::create_dir(run_dir.path()).expect("create current directory fixture");
        let executable = run_dir.path().join("std_env_current_dir_checked");
        std::fs::write(&executable, &bytes).expect("write current directory ELF");
        let mut permissions = std::fs::metadata(&executable)
            .expect("stat current directory ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&executable, permissions).expect("chmod current directory ELF");

        let output = common::short_process_output_with_timeout(
            "std_env_current_dir_checked",
            std::process::Command::new(&executable).current_dir(run_dir.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        let mut expected = run_dir
            .path()
            .to_str()
            .expect("UTF-8 temp directory")
            .as_bytes()
            .to_vec();
        expected.push(0);
        assert_eq!(output.stdout, expected);
        std::fs::remove_dir_all(run_dir.path()).expect("remove current directory fixture");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_env_current_dir_read_into_reports_host_failure_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_current_dir_failure.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_current_dir_failure", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile current directory failure fixture");

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
        let executable =
            common::TempArtifact::new("laniusc_std_env", "std_env_current_dir_failure", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path())
            .expect("stat current directory failure ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions)
            .expect("chmod current directory failure ELF");

        let output = common::short_process_output_with_timeout(
            "current directory host failure",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-e")
                .arg("trace=getcwd")
                .arg("-e")
                .arg("inject=getcwd:error=EIO:when=1")
                .arg(executable.path())
                .current_dir("/tmp"),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
            "fault was not injected: {output:?}"
        );
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_env_current_dir_len_reports_allocation_failure_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_host/std_env_current_dir_len.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("std_env_current_dir_len", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile current directory length fixture");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_std_env", "std_env_current_dir_len", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        let normal = common::short_process_output_with_timeout(
            "current directory length normal",
            &mut std::process::Command::new(executable.path()),
        );
        assert_eq!(normal.status.code(), Some(0), "{normal:?}");

        if std::process::Command::new("strace").arg("-V").output().is_err() {
            return;
        }
        let fault = common::short_process_output_with_timeout(
            "current directory length allocation failure",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-e")
                .arg("trace=mmap")
                .arg("-e")
                .arg("inject=mmap:error=ENOMEM:when=1")
                .arg(executable.path()),
        );
        assert_eq!(fault.status.code(), Some(77), "{fault:?}");
        assert!(
            String::from_utf8_lossy(&fault.stderr).contains("INJECTED"),
            "allocation fault was not injected: {fault:?}"
        );
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_env_checked_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/env_checked.lani");
    let fixtures = format!(
        "{}{}{}",
        include_str!("fixtures/stdlib_host/std_env_checked.lani"),
        include_str!("fixtures/stdlib_host/std_env_keys_checked.lani"),
        include_str!("fixtures/stdlib_host/std_env_current_dir_checked.lani")
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
            fixtures.contains(&format!("std::env_checked::{name}(")),
            "std::env_checked::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 3);
}
