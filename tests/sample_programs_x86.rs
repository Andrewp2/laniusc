mod common;

use std::{fs, path::Path, process::Command};

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn x86_sample_programs_compile_run_and_match_stdout() {
    for sample in common::sample_programs::load_sample_programs() {
        if !sample.checked_for_target("x86_64") {
            continue;
        }
        if !sample.selected_by_env_filter() {
            continue;
        }

        let name = sample.name().to_owned();
        let path = sample.path().to_path_buf();
        let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let context = format!("x86 sample {name}");
        let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let result = run_sample_x86(&context, &format!("x86_sample_{name}"), &bytes, &sample);
            sample.assert_exit_code_eq("x86", result.exit_code);
            sample.assert_stdout_eq("x86", &result.stdout);
        }
    }
}

#[cfg(all(unix, target_arch = "x86_64"))]
struct SampleRunResult {
    stdout: String,
    exit_code: i32,
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_sample_x86(
    context: &str,
    artifact_stem: &str,
    bytes: &[u8],
    sample: &common::sample_programs::SampleProgram,
) -> SampleRunResult {
    use std::os::unix::fs::PermissionsExt;

    let work_dir = TempDir::new("sample_program");
    sample.stage_input_files(work_dir.path());
    let exe_path = work_dir.path().join(artifact_stem);
    fs::write(&exe_path, bytes)
        .unwrap_or_else(|err| panic!("{context}: write native ELF {}: {err}", exe_path.display()));
    let mut permissions = fs::metadata(&exe_path)
        .unwrap_or_else(|err| panic!("{context}: stat native ELF {}: {err}", exe_path.display()))
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(&exe_path, permissions)
        .unwrap_or_else(|err| panic!("{context}: chmod native ELF {}: {err}", exe_path.display()));

    let mut command = Command::new(&exe_path);
    let stdin_path = work_dir.path().join("stdin.txt");
    fs::write(&stdin_path, b"S")
        .unwrap_or_else(|err| panic!("{context}: write native stdin fixture: {err}"));
    let stdin = fs::File::open(&stdin_path)
        .unwrap_or_else(|err| panic!("{context}: open native stdin fixture: {err}"));
    command
        .current_dir(work_dir.path())
        .arg("LANIUS_TEST_ENV")
        .env("LANIUS_TEST_ENV", "present")
        .stdin(stdin);
    let output = common::short_process_output_with_timeout(
        format!("{context}: run native ELF {}", exe_path.display()),
        &mut command,
    );
    let exit_code = output.status.code().unwrap_or_else(|| {
        panic!(
            "{context}: native ELF terminated without an exit code\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
    });
    sample.assert_output_files_eq_dir("x86", work_dir.path());
    SampleRunResult {
        stdout: common::stdout_utf8(format!("{context}: native stdout"), output.stdout),
        exit_code,
    }
}

#[cfg(all(unix, target_arch = "x86_64"))]
struct TempDir {
    path: std::path::PathBuf,
}

#[cfg(all(unix, target_arch = "x86_64"))]
impl TempDir {
    fn new(stem: &str) -> Self {
        let path = common::temp_artifact_path("laniusc_sample_x86", stem, None);
        fs::create_dir(&path)
            .unwrap_or_else(|err| panic!("create temp directory {}: {err}", path.display()));
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(all(unix, target_arch = "x86_64"))]
impl Drop for TempDir {
    fn drop(&mut self) {
        match fs::remove_dir_all(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => eprintln!(
                "failed to remove temp directory {}: {err}",
                self.path.display()
            ),
        }
    }
}
