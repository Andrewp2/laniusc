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
fn sample_programs_compile_to_x86_and_match_stdout_under_100ms() {
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
            let elf = compile_source_to_x86_64_with_gpu_codegen_using(program.source(), &compiler)
                .await
                .unwrap_or_else(|err| {
                    panic!(
                        "{}: compile x86_64 from {}: {err}",
                        program.name(),
                        program.path().display()
                    )
                });
            let elapsed = start.elapsed();
            assert!(
                elapsed < Duration::from_millis(100),
                "{}: x86_64 compile took {elapsed:?}, expected under 100ms",
                program.name()
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
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
fn cli_defaults_to_x86_64_executable() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "cli_default_src", Some("lani"));
    let exe_path = common::TempArtifact::new("laniusc_gpu_x86", "cli_default_exe", None);
    src_path.write_str("fn main() {\n    print(42);\n    return 0;\n}\n");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let output = Command::new(bin)
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg(src_path.path())
        .arg("-o")
        .arg(exe_path.path())
        .output()
        .expect("run laniusc");

    common::assert_command_success("laniusc CLI default x86_64", &output);

    let run = Command::new(exe_path.path())
        .output()
        .unwrap_or_else(|err| panic!("run emitted ELF {}: {err}", exe_path.path().display()));
    common::assert_command_success(format!("emitted ELF {}", exe_path.path().display()), &run);
    assert_eq!(
        common::stdout_utf8("emitted ELF stdout", run.stdout),
        "42\n"
    );
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
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

    let elf = pollster::block_on(async {
        let compiler = GpuCompiler::new_with_device(device::global())
            .await
            .expect("initialize reusable GPU compiler");
        compile_source_to_x86_64_with_gpu_codegen_using(src, &compiler)
            .await
            .expect("compile bool literal x86")
    });

    let stdout = common::run_x86_64_elf("bool_literals: x86_64 sample", "bool_literals", &elf);
    assert_eq!(stdout, "1\n2\n");
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86(program: &SampleProgram, elf: &[u8]) -> String {
    common::run_x86_64_elf(
        format!("{}: x86_64 sample", program.name()),
        program.name(),
        elf,
    )
}
