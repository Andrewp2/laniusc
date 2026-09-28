mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile wide timespec fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;

    let exe = common::TempArtifact::new("laniusc_std_time_wide", name, None);
    exe.write_bytes(bytes);
    let mut permissions = std::fs::metadata(exe.path()).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(exe.path(), permissions).unwrap();
    exe
}

#[test]
fn every_public_wide_time_function_has_a_runtime_call() {
    let source = include_str!("../stdlib/std/time_wide.lani");
    let fixture = include_str!("fixtures/stdlib_host/std_time_wide.lani");
    let names: Vec<_> = source
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 5);
    for name in names {
        assert!(fixture.contains(&format!("std::time_wide::{name}(")));
    }
}

#[test]
fn wide_timespec_decoding_and_clock_reads_execute_on_x86() {
    let bytes = compile_fixture("std_time_wide");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide timespec", "std_time_wide", &bytes);
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
fn overstated_timespec_view_traps_before_host_read_on_x86() {
    let bytes = compile_fixture("std_time_wide_bounds");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("wide timespec bounds", "std_time_wide_bounds", &bytes);
        assert_eq!(output.status.code(), Some(101), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn wide_clock_reads_report_host_failures_on_x86() {
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
            "std_time_wide_monotonic_failure",
            "std_time_wide_system_failure",
        ] {
            let bytes = compile_fixture(name);
            let exe = executable(&bytes, name);
            let output = common::short_process_output_with_timeout(
                format!("wide time {name} host failure"),
                std::process::Command::new("strace")
                    .arg("-qq")
                    .arg("-e")
                    .arg("trace=clock_gettime")
                    .arg("-e")
                    .arg("inject=clock_gettime:error=EIO:when=1")
                    .arg(exe.path()),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("INJECTED"));
        }
    }
}
