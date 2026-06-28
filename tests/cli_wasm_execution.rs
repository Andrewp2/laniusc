mod common;

use std::{fs, path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_wasm_sample_build_command_runs_top_level_script() {
    common::require_node();

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let sample = repo_root.join("sample_programs/top_level_script.lani");
    let expected_stdout =
        fs::read_to_string(repo_root.join("sample_programs/top_level_script.stdout"))
            .expect("read top_level_script expected stdout");
    let wasm = common::TempArtifact::new("laniusc_cli_wasm", "top_level_script", Some("wasm"));

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("wasm")
        .arg("-o")
        .arg(wasm.path())
        .arg(&sample);
    let output = common::codegen_command_output_with_timeout(
        "laniusc --emit wasm top_level_script",
        &mut command,
    );
    common::assert_command_success("laniusc --emit wasm top_level_script", &output);

    let wasm_bytes = fs::read(wasm.path())
        .unwrap_or_else(|err| panic!("read emitted WASM {}: {err}", wasm.path().display()));
    let stdout = common::run_wasm_main_with_node(
        "cli wasm top_level_script",
        "cli_top_level_script",
        &wasm_bytes,
    );
    assert_eq!(stdout, expected_stdout);
}

#[test]
fn cli_wasm_stdlib_root_sample_build_command_runs_stdio_print_i32() {
    common::require_node();

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let sample = repo_root.join("sample_programs/stdio_print_i32.lani");
    let expected_stdout =
        fs::read_to_string(repo_root.join("sample_programs/stdio_print_i32.stdout"))
            .expect("read stdio_print_i32 expected stdout");
    let wasm = common::TempArtifact::new("laniusc_cli_wasm", "stdio_print_i32", Some("wasm"));

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--stdlib-root")
        .arg(repo_root.join("stdlib"))
        .arg("--emit")
        .arg("wasm")
        .arg("-o")
        .arg(wasm.path())
        .arg(&sample);
    let output = common::codegen_command_output_with_timeout(
        "laniusc --stdlib-root stdio_print_i32 --emit wasm",
        &mut command,
    );
    common::assert_command_success("laniusc --stdlib-root stdio_print_i32 --emit wasm", &output);

    let wasm_bytes = fs::read(wasm.path())
        .unwrap_or_else(|err| panic!("read emitted WASM {}: {err}", wasm.path().display()));
    let stdout = common::run_wasm_main_with_node(
        "cli wasm stdio_print_i32",
        "cli_stdio_print_i32",
        &wasm_bytes,
    );
    assert_eq!(stdout, expected_stdout);
}
