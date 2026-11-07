//! Canonical thread execution, exact raw-thread ownership and real-pthread faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn native(name: &str, objects: Vec<PathBuf>) -> common::TempArtifact {
    let entry = root()
        .join("tests/fixtures/stdlib_thread_lifecycle")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: Vec::new(),
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        objects,
        libraries: vec!["dl".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("canonical thread lifecycle", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let output = common::TempArtifact::new("laniusc_thread_lifecycle", name, None);
    output.write_bytes(bytes);
    std::fs::set_permissions(output.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    output
}
#[test]
fn canonical_thread_ordinary_functions_execute_real_native_threads() {
    let executable = native("admission.lani", Vec::new());
    let output = common::process_output_with_timeout(
        "canonical std::thread admission",
        &mut Command::new(executable.path()),
        Duration::from_secs(6),
    );
    common::assert_command_success("canonical std::thread admission", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn thread_attributes_and_failed_joins_preserve_real_native_owners() {
    let shim = common::TempArtifact::new("laniusc_thread_lifecycle", "thread_probe", Some("o"));
    let output = common::process_output_with_timeout(
        "compile real-pthread probe",
        Command::new("cc")
            .args([
                "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-c",
            ])
            .arg(root().join("tests/fixtures/stdlib_thread_lifecycle/thread_probe.c"))
            .arg("-o")
            .arg(shim.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("real-pthread probe", &output);
    let executable = native("failures.lani", vec![shim.path().to_path_buf()]);
    let output = common::process_output_with_timeout(
        "real-pthread lifecycle faults",
        &mut Command::new(executable.path()),
        Duration::from_secs(15),
    );
    assert!(
        output.status.success(),
        "real-pthread lifecycle faults: {output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        b"thread-lifecycle real-pthreads attributes=7 retained-start=1 join-retry=1\n"
    );
}

#[test]
fn thread_scheduling_preserves_syscall_errors_and_checks_full_width_affinity_counts() {
    let executable = native("scheduling.lani", Vec::new());
    let output = common::process_output_with_timeout(
        "thread scheduling syscall outcomes",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root().join("tests/fixtures/stdlib_thread_lifecycle/scheduling_oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("thread scheduling outcomes", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        b"thread-scheduling cases=13 injected=11 controls=11\n"
    );
}

fn execute_function_address_case(name: &str) {
    let executable = native(name, Vec::new());
    let output = common::process_output_with_timeout(
        "function-address frame control",
        &mut Command::new(executable.path()),
        Duration::from_secs(6),
    );
    assert!(output.status.success(), "{name}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{name}: {output:?}"
    );
}

#[test]
#[ignore = "Compiler dependency: inline function-address Result receiver may store callback at saved RBP"]
fn inline_function_address_result_unwrap_preserves_the_callers_frame() {
    execute_function_address_case("repros/function_address_result_unwrap.lani");
}

#[test]
fn named_function_address_result_unwrap_preserves_the_callers_frame() {
    execute_function_address_case("repros/function_address_named_local.lani");
}

#[test]
fn named_function_address_with_separate_result_preserves_the_callers_frame() {
    execute_function_address_case("repros/function_address_split_result.lani");
}

#[test]
fn named_thread_entry_joins_null_return_and_preserves_the_callers_frame() {
    execute_function_address_case("repros/thread_named_entry.lani");
}
