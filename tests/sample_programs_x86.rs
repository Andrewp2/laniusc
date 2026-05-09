use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::{Duration, Instant},
};

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
        let programs = sample_programs();
        assert_eq!(
            programs.len(),
            14,
            "expected exactly the 14 checked-in sample programs"
        );

        let sources = programs
            .iter()
            .map(|program| {
                let src = fs::read_to_string(program)
                    .unwrap_or_else(|err| panic!("read {}: {err}", program.display()));
                (program.clone(), src)
            })
            .collect::<Vec<_>>();
        let warm_src = sources
            .iter()
            .max_by_key(|(_, src)| src.len())
            .map(|(_, src)| src.as_str())
            .expect("sample source for native warmup");
        compile_source_to_x86_64_with_gpu_codegen_using(warm_src, &compiler)
            .await
            .expect("warm up reusable x86 compiler");

        for (program, src) in sources {
            let name = program
                .file_stem()
                .and_then(|stem| stem.to_str())
                .expect("sample program file stem");
            let expected_path = program.with_extension("stdout");
            let expected = fs::read_to_string(&expected_path)
                .unwrap_or_else(|err| panic!("{name}: read {}: {err}", expected_path.display()));

            let start = Instant::now();
            let elf = compile_source_to_x86_64_with_gpu_codegen_using(&src, &compiler)
                .await
                .unwrap_or_else(|err| panic!("{name}: compile x86_64: {err}"));
            let elapsed = start.elapsed();
            assert!(
                elapsed < Duration::from_millis(100),
                "{name}: x86_64 compile took {elapsed:?}, expected under 100ms"
            );
            println!(
                "{name}: x86_compile_ms={:.3}",
                elapsed.as_secs_f64() * 1000.0
            );

            let stdout = run_x86(name, &elf);
            assert_eq!(stdout, expected, "{name}: x86_64 stdout mismatch");
        }
    });
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
fn cli_defaults_to_x86_64_executable() {
    let src_path = std::env::temp_dir().join(format!(
        "laniusc_gpu_x86_{}_{}.lani",
        std::process::id(),
        unique_suffix()
    ));
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

fn sample_programs() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("sample_programs");
    let mut programs = fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("read sample_programs dir {}: {err}", root.display()))
        .map(|entry| {
            entry
                .unwrap_or_else(|err| panic!("read sample_programs entry: {err}"))
                .path()
        })
        .filter(|path| path.extension().is_some_and(|ext| ext == "lani"))
        .collect::<Vec<_>>();
    programs.sort();
    programs
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86(name: &str, elf: &[u8]) -> String {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = std::env::temp_dir().join(format!(
        "laniusc_sample_x86_{name}_{}_{}",
        std::process::id(),
        unique_suffix()
    ));
    fs::write(&exe_path, elf)
        .unwrap_or_else(|err| panic!("{name}: write temporary ELF {}: {err}", exe_path.display()));
    let mut permissions = fs::metadata(&exe_path)
        .unwrap_or_else(|err| panic!("{name}: stat temporary ELF {}: {err}", exe_path.display()))
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(&exe_path, permissions)
        .unwrap_or_else(|err| panic!("{name}: chmod temporary ELF {}: {err}", exe_path.display()));

    let output = Command::new(&exe_path)
        .output()
        .unwrap_or_else(|err| panic!("{name}: run native ELF {}: {err}", exe_path.display()));
    let _ = fs::remove_file(&exe_path);
    assert!(
        output.status.success(),
        "{name}: native ELF failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap_or_else(|err| panic!("{name}: stdout utf8: {err}"))
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}
