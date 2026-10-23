mod common;

use std::{
    path::{Path, PathBuf},
    process::{Command, Output},
};

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn compile(name: &str) -> Vec<u8> {
    let entry = root().join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root().join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"))
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run(bytes: &[u8], args: &[&str]) -> Output {
    common::run_x86_64_elf_output_with_args("development suite", "development", bytes, args)
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn assert_status(output: &Output, status: i32) -> String {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout.clone()).expect("UTF-8 report")
}

#[test]
fn source_suites_filter_count_skip_fail_and_reproduce_properties() {
    let bytes = compile("development_suite");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let report = assert_status(&run(&bytes, &[]), 1);
        assert!(report.contains("PASS passing\nFAIL failing\n"), "{report}");
        assert!(
            report.contains("detail: deliberate failure\\x0aline\n"),
            "{report}"
        );
        assert!(report.contains("expected=9 actual=-8\n"), "{report}");
        assert!(report.contains("SKIP skipped\n"), "{report}");
        assert!(report.ends_with("summary selected=4 passed=1 failed=2 skipped=1 filtered=0\n"));
        for (filter, status, summary) in [
            (
                "passing",
                0,
                "selected=1 passed=1 failed=0 skipped=0 filtered=3",
            ),
            (
                "skipped",
                0,
                "selected=1 passed=0 failed=0 skipped=1 filtered=3",
            ),
            (
                "missing",
                3,
                "selected=0 passed=0 failed=0 skipped=0 filtered=4",
            ),
        ] {
            let report = assert_status(&run(&bytes, &["--filter", filter]), status);
            assert!(report.contains(summary), "{report}");
        }
        let listed = assert_status(&run(&bytes, &["--filter", "failing", "--list"]), 0);
        assert!(
            listed.contains("LIST failing\n") && !listed.contains("FAIL "),
            "{listed}"
        );
        for seed in [0_u32, 42, u32::MAX] {
            let seed_text = seed.to_string();
            let args = [
                "--filter", "property", "--seed", &seed_text, "--cases", "10",
            ];
            let first = assert_status(&run(&bytes, &args), 1);
            let second = assert_status(&run(&bytes, &args), 1);
            assert_eq!(first, second, "seed {seed} is not reproducible");
            let input = (0..4).fold(seed, |s, _| {
                s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223)
            });
            assert!(
                first.contains(&format!(
                    "counterexample seed={seed} case=3 input={input} executed=4\n"
                )),
                "{first}"
            );
        }
        let bounded = assert_status(&run(&bytes, &["--filter", "property", "--cases", "3"]), 0);
        assert!(bounded.contains("PASS property\n"), "{bounded}");
        for args in [
            vec!["--cases", "0"],
            vec!["--cases", "10001"],
            vec!["--cases", "-1"],
            vec!["--seed", "4294967296"],
            vec!["--seed", ""],
            vec!["--seed", "1", "--seed", "2"],
            vec!["--filter"],
            vec!["--unknown"],
            vec!["--list", "--list"],
        ] {
            let output = run(&bytes, &args);
            assert_eq!(output.status.code(), Some(2), "{args:?}: {output:?}");
            assert!(output.stdout.is_empty(), "{args:?}: {output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("test arguments:"));
        }
        let too_long = "x".repeat(257);
        assert_eq!(run(&bytes, &["--filter", &too_long]).status.code(), Some(2));
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn properties_enforce_bounds_and_benches_measure_completed_work() {
    for name in [
        "development_property",
        "development_bench",
        "development_native_bench",
        "development_vec_callback",
        "development_vec_control",
    ] {
        let bytes = compile(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let report = assert_status(&run(&bytes, &[]), 0);
            if name == "development_bench" {
                assert!(
                    report.starts_with("bench iterations=10000 work=30000 elapsed_seconds="),
                    "{report}"
                );
                let nanos: u32 = report
                    .split(" elapsed_nanos=")
                    .nth(1)
                    .unwrap()
                    .trim()
                    .parse()
                    .unwrap();
                assert!(
                    nanos < 1_000_000_000,
                    "fractional nanoseconds are normalized"
                );
            }
            if name == "development_native_bench" {
                let exe = executable(&bytes);
                let output = common::short_process_output_with_timeout(
                    "native benchmark full device",
                    Command::new("bash")
                        .arg("-c")
                        .arg("exec \"$@\" > /dev/full")
                        .arg("bench-fault")
                        .arg(exe.path()),
                );
                assert_eq!(output.status.code(), Some(2), "{output:?}");
                if Command::new("strace").arg("-V").output().is_ok() {
                    for when in [1, 2] {
                        let output = common::short_process_output_with_timeout(
                            "native benchmark clock fault",
                            Command::new("strace")
                                .args(["-qq", "-e", "trace=clock_gettime", "-e"])
                                .arg(format!("inject=clock_gettime:error=EIO:when={when}"))
                                .arg(exe.path()),
                        );
                        assert_eq!(output.status.code(), Some(20), "{output:?}");
                        assert!(
                            String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                            "{output:?}"
                        );
                    }
                }
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn primitive_runner_rejects_invalid_transitions_and_traps_end_the_process() {
    let bytes = compile("development_runner");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let report = assert_status(&run(&bytes, &[]), 0);
        assert!(report.contains("PASS escaped\\x0acase\n"), "{report}");
        assert_eq!(report.matches("summary ").count(), 1, "{report}");
        assert!(!report.contains("PASS pending\n"), "{report}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
    let bytes = compile("development_trap");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::process::ExitStatusExt;
        let output = common::run_x86_64_elf_output_expecting_signal(
            "suite trap",
            "development_trap",
            &bytes,
        );
        assert_eq!(output.status.signal(), Some(4), "{output:?}");
        assert!(!String::from_utf8_lossy(&output.stdout).contains("summary"));
        let report = assert_status(&run(&bytes, &["--filter", "after"]), 0);
        assert!(report.contains("PASS after\n"), "{report}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8]) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let artifact = common::TempArtifact::new("laniusc_development", "fault", None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}

#[test]
fn report_errors_never_turn_failed_or_incomplete_output_into_success() {
    let bytes = compile("development_suite");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let exe = executable(&bytes);
        let output = common::short_process_output_with_timeout(
            "development report full device",
            Command::new("bash")
                .arg("-c")
                .arg("exec \"$@\" > /dev/full")
                .arg("report-fault")
                .arg(exe.path())
                .args(["--filter", "passing"]),
        );
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        // Force zero progress, a short header and an I/O error. Each is an
        // explicit report failure even when the selected test would pass.
        if Command::new("strace").arg("-V").output().is_ok() {
            for injection in [
                "write:retval=0:when=1",
                "write:retval=1:when=1",
                "write:error=EIO:when=3",
            ] {
                let output = common::short_process_output_with_timeout(
                    injection,
                    Command::new("strace")
                        .args(["-qq", "-e", "trace=write", "-e"])
                        .arg(format!("inject={injection}"))
                        .arg(exe.path())
                        .args(["--filter", "passing"]),
                );
                assert_eq!(output.status.code(), Some(2), "{injection}: {output:?}");
                assert!(
                    String::from_utf8_lossy(&output.stderr).contains("INJECTED"),
                    "{output:?}"
                );
            }
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn driver(source: &Path, args: &[&str]) -> Output {
    common::command_output_with_timeout(
        "native development driver",
        Command::new(root().join("tools/lanius-test"))
            .env("LANIUSC", env!("CARGO_BIN_EXE_laniusc"))
            .env_remove("LANIUS_TEST_COMPILE_SECONDS")
            .env_remove("LANIUS_TEST_RUN_SECONDS")
            .arg(source)
            .args(args),
    )
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_driver_runs_real_library_acceptance_and_preserves_statuses() {
    // Exercise the default combined budget through the complete native path.
    let source = root().join("sample_programs/library/library_tests.lani");
    let output = driver(&source, &["--seed", "42", "--cases", "73"]);
    let report = assert_status(&output, 0);
    assert!(report.contains("PASS option_result.fallback\n"), "{report}");
    assert!(report.contains("PASS format.signed_parse\n"), "{report}");
    assert!(
        report.contains("PASS property.decimal_roundtrip\n"),
        "{report}"
    );
    assert!(report.contains("PASS vec.stack_model\n"), "{report}");
    assert!(
        report.contains("bench iterations=10000 work=10000 elapsed_seconds="),
        "{report}"
    );
    assert!(
        report.ends_with("summary selected=5 passed=5 failed=0 skipped=0 filtered=0\n"),
        "{report}"
    );
    let source = common::TempArtifact::new(
        "laniusc_development",
        "quoted",
        Some(" source;literal.lani"),
    );
    source.write_str(include_str!(
        "fixtures/stdlib_foundation/development_suite.lani"
    ));
    assert_status(&driver(source.path(), &["--filter", "failing"]), 1);
    assert_status(&driver(source.path(), &["--filter", "missing"]), 3);
    source.write_str("module app::main; fn main() -> i32 { return unknown; }");
    let output = driver(source.path(), &[]);
    assert_eq!(output.status.code(), Some(4), "{output:?}");
    assert!(String::from_utf8_lossy(&output.stderr).contains("compilation failed"));
    let output = common::short_process_output_with_timeout(
        "driver phase limit validation",
        Command::new(root().join("tools/lanius-test"))
            .env("LANIUS_TEST_RUN_SECONDS", "101")
            .arg(source.path()),
    );
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    for (compile_seconds, run_seconds) in [("80", "31"), ("100", "30"), ("100", "100")] {
        let output = common::short_process_output_with_timeout(
            "driver combined phase limit validation",
            Command::new(root().join("tools/lanius-test"))
                .env("LANIUSC", env!("CARGO_BIN_EXE_laniusc"))
                .env("LANIUS_TEST_COMPILE_SECONDS", compile_seconds)
                .env("LANIUS_TEST_RUN_SECONDS", run_seconds)
                .arg(source.path()),
        );
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("combined compile and run limits"),
            "{output:?}"
        );
        assert!(output.stdout.is_empty(), "{output:?}");
    }
    source.write_str("module app::main; fn main() -> i32 { while (true) {} return 0; }");
    let output = common::command_output_with_timeout(
        "driver run timeout",
        Command::new(root().join("tools/lanius-test"))
            .env("LANIUSC", env!("CARGO_BIN_EXE_laniusc"))
            .env("LANIUS_TEST_RUN_SECONDS", "1")
            .arg(source.path()),
    );
    assert_eq!(output.status.code(), Some(124), "{output:?}");
}
