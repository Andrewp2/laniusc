#[cfg(all(unix, target_arch = "x86_64"))]
use std::{
    fs,
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
    let src_path = common::temp_artifact_path("laniusc_gpu_x86", "cli_default", Some("lani"));
    let exe_path = src_path.with_extension("elf");
    fs::write(&src_path, "fn main() {\n    print(42);\n    return 0;\n}\n")
        .expect("write temporary source");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let output = Command::new(bin)
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg(&src_path)
        .arg("-o")
        .arg(&exe_path)
        .output()
        .expect("run laniusc");

    let _ = fs::remove_file(&src_path);
    assert!(
        output.status.success(),
        "laniusc failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let run = Command::new(&exe_path)
        .output()
        .unwrap_or_else(|err| panic!("run emitted ELF {}: {err}", exe_path.display()));
    let _ = fs::remove_file(&exe_path);
    assert!(
        run.status.success(),
        "emitted ELF failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&run.stdout),
        String::from_utf8_lossy(&run.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&run.stdout), "42\n");
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86(program: &SampleProgram, elf: &[u8]) -> String {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = common::temp_artifact_path("laniusc_sample_x86", program.name(), None);
    fs::write(&exe_path, elf).unwrap_or_else(|err| {
        panic!(
            "{}: write temporary ELF {}: {err}",
            program.name(),
            exe_path.display()
        )
    });
    let mut permissions = fs::metadata(&exe_path)
        .unwrap_or_else(|err| {
            panic!(
                "{}: stat temporary ELF {}: {err}",
                program.name(),
                exe_path.display()
            )
        })
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(&exe_path, permissions).unwrap_or_else(|err| {
        panic!(
            "{}: chmod temporary ELF {}: {err}",
            program.name(),
            exe_path.display()
        )
    });

    let output = Command::new(&exe_path).output().unwrap_or_else(|err| {
        panic!(
            "{}: run native ELF {}: {err}",
            program.name(),
            exe_path.display()
        )
    });
    let _ = fs::remove_file(&exe_path);
    assert!(
        output.status.success(),
        "{}: native ELF failed for {}:\nstdout:\n{}\nstderr:\n{}",
        program.name(),
        exe_path.display(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout)
        .unwrap_or_else(|err| panic!("{}: native stdout utf8: {err}", program.name()))
}
