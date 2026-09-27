mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked secure random fixture")
}

#[cfg(target_os = "linux")]
fn write_executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let executable = common::TempArtifact::new("laniusc_std_random", name, None);
    executable.write_bytes(bytes);
    let mut permissions = std::fs::metadata(executable.path())
        .expect("stat random fixture")
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(executable.path(), permissions).expect("chmod random fixture");
    executable
}

#[test]
fn std_random_secure_u32_or_executes_on_x86() {
    let bytes = compile_fixture("std_random_checked");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_random_checked", "std_random_checked", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_random_fill_secure_exact_executes_on_x86() {
    let bytes = compile_fixture("std_random_fill_exact");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_random_fill_exact", "std_random_fill_exact", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout.len(), 16);
        assert_ne!(output.stdout, [0x55; 16]);
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_random_secure_u32_or_handles_host_failure_on_x86() {
    let bytes = compile_fixture("std_random_checked_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "std_random_checked_failure");
        for injection in ["getrandom:error=EIO:when=1", "getrandom:retval=0:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("checked secure random {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
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
fn std_random_fill_secure_exact_handles_host_failure_on_x86() {
    let bytes = compile_fixture("std_random_fill_exact_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let executable = write_executable(&bytes, "std_random_fill_exact_failure");
        for injection in ["getrandom:error=EIO:when=1", "getrandom:retval=0:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("secure fill {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
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
fn std_random_checked_retries_short_host_reads_on_x86() {
    let fill_bytes = compile_fixture("std_random_fill_exact");
    let scalar_bytes = compile_fixture("std_random_checked_short");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, bytes) in [
            ("std_random_fill_exact_short", fill_bytes.as_slice()),
            ("std_random_checked_scalar_short", scalar_bytes.as_slice()),
        ] {
            let executable = write_executable(bytes, name);
            let output = common::short_process_output_with_timeout(
                format!("short secure read {name}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg("inject=getrandom:retval=2:when=1")
                    .arg(executable.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            let trace = String::from_utf8_lossy(&output.stderr);
            assert!(
                trace.contains("INJECTED"),
                "fault was not injected: {output:?}"
            );
            assert!(
                trace.matches("getrandom(").count() >= 2,
                "short read was not retried: {output:?}"
            );
            if name == "std_random_fill_exact_short" {
                assert_eq!(output.stdout.len(), 16);
                assert_ne!(output.stdout, [0x55; 16]);
            }
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (fill_bytes, scalar_bytes);
}

#[test]
fn std_random_secure_u32_below_executes_on_x86() {
    let bytes = compile_fixture("std_random_below");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("std_random_below", "std_random_below", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_random_secure_u32_below_handles_failure_and_rejection_on_x86() {
    let failure_bytes = compile_fixture("std_random_below_failure");
    let rejection_bytes = compile_fixture("std_random_below_rejection");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let failure = write_executable(&failure_bytes, "std_random_below_failure");
        for injection in ["getrandom:error=EIO:when=1", "getrandom:retval=0:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("bounded random {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(failure.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }

        let rejection = write_executable(&rejection_bytes, "std_random_below_rejection");
        let output = common::short_process_output_with_timeout(
            "bounded random rejection",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-e")
                .arg("trace=getrandom")
                .arg("-e")
                .arg("inject=getrandom:retval=4:when=1")
                .arg(rejection.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        let trace = String::from_utf8_lossy(&output.stderr);
        assert!(trace.contains("INJECTED"), "{output:?}");
        assert!(trace.matches("getrandom(").count() >= 2, "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (failure_bytes, rejection_bytes);
}

#[test]
fn std_random_shuffle_i32_executes_on_x86() {
    let bytes = compile_fixture("std_random_shuffle");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("std_random_shuffle", "std_random_shuffle", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn std_random_shuffle_i32_swaps_and_reports_host_failure_on_x86() {
    let swap_bytes = compile_fixture("std_random_shuffle_swap");
    let failure_bytes = compile_fixture("std_random_shuffle_failure");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        let swap = write_executable(&swap_bytes, "std_random_shuffle_swap");
        let output = common::short_process_output_with_timeout(
            "forced random shuffle swap",
            std::process::Command::new("strace")
                .arg("-qq")
                .arg("-e")
                .arg("trace=getrandom")
                .arg("-e")
                .arg("inject=getrandom:retval=4:when=1")
                .arg(swap.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));

        let failure = write_executable(&failure_bytes, "std_random_shuffle_failure");
        for injection in ["getrandom:error=EIO:when=1", "getrandom:retval=0:when=1"] {
            let output = common::short_process_output_with_timeout(
                format!("random shuffle {injection}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(failure.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (swap_bytes, failure_bytes);
}

#[test]
fn std_random_checked_public_functions_have_runtime_cases() {
    let source = include_str!("../stdlib/std/random_checked.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_random_fill_exact.lani"),
        include_str!("fixtures/stdlib_host/std_random_checked.lani"),
        include_str!("fixtures/stdlib_host/std_random_below.lani"),
        include_str!("fixtures/stdlib_host/std_random_shuffle.lani"),
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
            fixtures.contains(&format!("std::random_checked::{name}(")),
            "std::random_checked::{name} lacks a runtime case"
        );
        count += 1;
    }
    assert_eq!(count, 4);
}
