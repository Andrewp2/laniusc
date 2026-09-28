mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let exe = common::TempArtifact::new("laniusc_std_random_wide", name, None);
    exe.write_bytes(bytes);
    let mut permissions = std::fs::metadata(exe.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(exe.path(), permissions).unwrap();
    exe
}

#[test]
fn every_public_wide_random_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/random_wide.lani");
    let fixtures = [
        include_str!("fixtures/stdlib_host/std_random_wide.lani"),
        include_str!("fixtures/stdlib_host/std_random_wide_u64_failure.lani"),
        include_str!("fixtures/stdlib_host/std_random_wide_i64_failure.lani"),
        include_str!("fixtures/stdlib_host/std_random_wide_below_failure.lani"),
        include_str!("fixtures/stdlib_host/std_random_wide_inclusive_failure.lani"),
        include_str!("fixtures/stdlib_host/std_random_wide_signed_inclusive_failure.lani"),
    ]
    .concat();
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 5);
    for name in names {
        assert!(
            fixtures.contains(&format!("std::random_wide::{name}(")),
            "{name}"
        );
    }
}

#[test]
fn wide_secure_draws_and_ranges_execute_on_x86() {
    let bytes = compile_fixture("std_random_wide");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide secure random", "std_random_wide", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn wide_random_range_sample_prints_a_value_and_reports_host_failure() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/random_wide_range_draw.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide random range sample", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide random range sample");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let exe = executable(&bytes, "wide_random_range_sample");
        let output = common::short_process_output_with_timeout(
            "wide random range sample",
            &mut std::process::Command::new(exe.path()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        let value: u32 = std::str::from_utf8(&output.stdout)
            .expect("UTF-8 decimal output")
            .trim_end_matches('\n')
            .parse()
            .expect("decimal output");
        assert!((2..=12).contains(&value), "{output:?}");
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_ok()
        {
            let failed = common::short_process_output_with_timeout(
                "wide random range sample host error",
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg("inject=getrandom:error=EIO:when=1")
                    .arg(exe.path()),
            );
            assert_eq!(failed.status.code(), Some(1), "{failed:?}");
            assert!(failed.stdout.is_empty(), "{failed:?}");
            assert!(String::from_utf8_lossy(&failed.stderr).contains("INJECTED"));
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn wide_secure_draws_report_host_failures_on_x86() {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for name in [
            "std_random_wide_u64_failure",
            "std_random_wide_i64_failure",
            "std_random_wide_below_failure",
            "std_random_wide_inclusive_failure",
            "std_random_wide_signed_inclusive_failure",
        ] {
            let bytes = compile_fixture(name);
            let exe = executable(&bytes, name);
            let normal = common::short_process_output_with_timeout(
                format!("{name} normal draw"),
                &mut std::process::Command::new(exe.path()),
            );
            assert_eq!(normal.status.code(), Some(1), "{name}: {normal:?}");
            for injection in ["getrandom:error=EIO:when=1", "getrandom:retval=0:when=1"] {
                let output = common::short_process_output_with_timeout(
                    format!("{name} {injection}"),
                    std::process::Command::new("strace")
                        .arg("-qq")
                        .arg("-e")
                        .arg("trace=getrandom")
                        .arg("-e")
                        .arg(format!("inject={injection}"))
                        .arg(exe.path()),
                );
                assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
                assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
            }
        }
    }
}

#[test]
fn wide_secure_fill_retries_short_reads_and_bounded_draw_rejects_bias_on_x86() {
    let raw_bytes = compile_fixture("std_random_wide_u64_failure");
    let rejection_bytes = compile_fixture("std_random_wide_rejection");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        if std::process::Command::new("strace")
            .arg("-V")
            .output()
            .is_err()
        {
            return;
        }
        for (name, bytes, injection, expected_exit) in [
            (
                "short_read",
                raw_bytes.as_slice(),
                "getrandom:retval=2:when=1",
                1,
            ),
            (
                "rejection",
                rejection_bytes.as_slice(),
                "getrandom:retval=8:when=1",
                0,
            ),
        ] {
            let exe = executable(bytes, name);
            let output = common::short_process_output_with_timeout(
                format!("wide random {name}"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=getrandom")
                    .arg("-e")
                    .arg(format!("inject={injection}"))
                    .arg(exe.path()),
            );
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            let trace = String::from_utf8_lossy(&output.stderr);
            assert!(
                trace.contains("INJECTED") && trace.matches("getrandom(").count() >= 2,
                "{name}: {output:?}"
            );
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (raw_bytes, rejection_bytes);
}
