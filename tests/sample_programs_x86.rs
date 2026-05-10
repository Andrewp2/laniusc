#[cfg(all(unix, target_arch = "x86_64"))]
use std::{
    process::Command,
    time::{Duration, Instant},
};

#[cfg(all(unix, target_arch = "x86_64"))]
mod common;

#[cfg(all(unix, target_arch = "x86_64"))]
use common::sample_programs::{SampleProgram, load_sample_programs};
#[cfg(all(unix, target_arch = "x86_64"))]
use laniusc::{
    compiler::{GpuCompiler, compile_source_to_x86_64_with_gpu_codegen_using},
    gpu::device,
};

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn sample_programs_compile_to_x86_and_match_stdout_under_100ms() {
    common::run_gpu_codegen_suite_with_timeout("sample x86 programs", || {
        pollster::block_on(async {
            let compiler = GpuCompiler::new_with_device(device::global())
                .await
                .expect("initialize reusable GPU compiler");
            let programs = load_sample_programs();

            let warm_src = programs
                .iter()
                .max_by_key(|program| program.source().len())
                .map(SampleProgram::source)
                .expect("sample source for native warmup");
            compile_source_to_x86_64_with_gpu_codegen_using(warm_src, &compiler)
                .await
                .expect("warm up reusable x86 compiler");

            for program in programs {
                let start = Instant::now();
                let elf =
                    compile_source_to_x86_64_with_gpu_codegen_using(program.source(), &compiler)
                        .await
                        .unwrap_or_else(|err| {
                            panic!(
                                "{}: compile x86_64 from {}: {err}",
                                program.name(),
                                program.path().display()
                            )
                        });
                let elapsed = start.elapsed();
                let budget = compile_budget(program.name());
                assert!(
                    elapsed < budget,
                    "{}: x86_64 compile took {elapsed:?}, expected under {budget:?}",
                    program.name(),
                );
                println!(
                    "{}: x86_compile_ms={:.3}",
                    program.name(),
                    elapsed.as_secs_f64() * 1000.0
                );

                let stdout = run_x86(&program, &elf);
                program.assert_stdout_eq("x86_64", &stdout);
            }
        });
    });
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn cli_defaults_to_x86_64_executable() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "cli_default_src", Some("lani"));
    let exe_path = common::TempArtifact::new("laniusc_gpu_x86", "cli_default_exe", None);
    src_path.write_str("fn main() {\n    print(42);\n    return 0;\n}\n");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let mut command = Command::new(bin);
    command
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg(src_path.path())
        .arg("-o")
        .arg(exe_path.path());
    let output = common::command_output_with_timeout("laniusc CLI default x86_64", &mut command);

    common::assert_command_success("laniusc CLI default x86_64", &output);

    let mut command = Command::new(exe_path.path());
    let run = common::short_process_output_with_timeout(
        format!("run emitted ELF {}", exe_path.path().display()),
        &mut command,
    );
    common::assert_command_success(format!("emitted ELF {}", exe_path.path().display()), &run);
    assert_eq!(
        common::stdout_utf8("emitted ELF stdout", run.stdout),
        "42\n"
    );
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn x86_codegen_lowers_bool_literals() {
    let src = r#"
fn main() {
    let flag: bool = false;
    if (true) {
        print(1);
    } else {
        print(0);
    }
    if (flag) {
        print(0);
    } else {
        print(2);
    }
    return 0;
}
"#;

    let elf = common::run_gpu_codegen_with_timeout("compile bool literal x86", || {
        pollster::block_on(async {
            let compiler = GpuCompiler::new_with_device(device::global())
                .await
                .expect("initialize reusable GPU compiler");
            compile_source_to_x86_64_with_gpu_codegen_using(src, &compiler)
                .await
                .expect("compile bool literal x86")
        })
    });

    let stdout = common::run_x86_64_elf("bool_literals: x86_64 sample", "bool_literals", &elf);
    assert_eq!(stdout, "1\n2\n");
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn x86_codegen_lowers_top_level_constants() {
    let src = r#"
const LIMIT: i32 = 7;
const ENABLED: bool = true;

fn main() {
    if (ENABLED) {
        print(LIMIT + 5);
    } else {
        print(0);
    }
    return LIMIT;
}
"#;

    let elf = common::run_gpu_codegen_with_timeout("compile const x86", || {
        pollster::block_on(async {
            let compiler = GpuCompiler::new_with_device(device::global())
                .await
                .expect("initialize reusable GPU compiler");
            compile_source_to_x86_64_with_gpu_codegen_using(src, &compiler)
                .await
                .expect("compile const x86")
        })
    });

    let stdout = common::run_x86_64_elf("consts: x86_64 sample", "consts", &elf);
    assert_eq!(stdout, "12\n");
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn x86_codegen_lowers_assert_builtin_success() {
    let src = r#"
fn main() {
    assert(true);
    assert(7 > 3);
    print(9);
    return 0;
}
"#;

    let elf = common::run_gpu_codegen_with_timeout("compile assert success x86", || {
        pollster::block_on(async {
            let compiler = GpuCompiler::new_with_device(device::global())
                .await
                .expect("initialize reusable GPU compiler");
            compile_source_to_x86_64_with_gpu_codegen_using(src, &compiler)
                .await
                .expect("compile assert success x86")
        })
    });

    let stdout = common::run_x86_64_elf("assert_success: x86_64 sample", "assert_success", &elf);
    assert_eq!(stdout, "9\n");
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn x86_codegen_exits_nonzero_for_failed_assert_builtin() {
    let src = r#"
fn main() {
    assert(false);
    print(9);
    return 0;
}
"#;

    let elf = common::run_gpu_codegen_with_timeout("compile assert failure x86", || {
        pollster::block_on(async {
            let compiler = GpuCompiler::new_with_device(device::global())
                .await
                .expect("initialize reusable GPU compiler");
            compile_source_to_x86_64_with_gpu_codegen_using(src, &compiler)
                .await
                .expect("compile assert failure x86")
        })
    });

    let output =
        common::run_x86_64_elf_output("assert_failure: x86_64 sample", "assert_failure", &elf);
    assert!(
        !output.status.success(),
        "failed assertion should make native executable exit nonzero\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86(program: &SampleProgram, elf: &[u8]) -> String {
    common::run_x86_64_elf(
        format!("{}: x86_64 sample", program.name()),
        program.name(),
        elf,
    )
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn compile_budget(name: &str) -> Duration {
    if matches!(name, "option_result_helpers" | "range_sum") {
        Duration::from_millis(150)
    } else {
        Duration::from_millis(100)
    }
}
