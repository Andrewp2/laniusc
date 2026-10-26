#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(entry: PathBuf, label: &str) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions::default();
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let executable = common::TempArtifact::new("laniusc_resolve_host", label, None);
    std::fs::write(executable.path(), bytes).unwrap();
    let checked = common::process_output_with_timeout(
        format!("{label} linked ELF"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success(format!("{label} linked ELF"), &checked);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("sample_programs/library/resolve_host.lani"),
            "cli",
        )
    })
}
fn native_helper(source: &str, label: &str, shared: bool) -> common::TempArtifact {
    let artifact = common::TempArtifact::new(
        "laniusc_resolve_host",
        label,
        if shared { Some("so") } else { None },
    );
    let mut command = Command::new("cc");
    command.args(["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2"]);
    if shared {
        command.args(["-shared", "-fPIC"]);
    }
    command
        .arg(root().join(source))
        .arg("-o")
        .arg(artifact.path());
    if shared {
        command.arg("-ldl");
    }
    let result = common::process_output_with_timeout(
        format!("{label} test helper"),
        &mut command,
        Duration::from_secs(20),
    );
    common::assert_command_success(format!("{label} test helper"), &result);
    artifact
}
fn observer() -> &'static common::TempArtifact {
    static SO: OnceLock<common::TempArtifact> = OnceLock::new();
    SO.get_or_init(|| {
        native_helper(
            "tests/fixtures/stdlib_foundation/resolve/observer.c",
            "observer",
            true,
        )
    })
}
fn native_oracle() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        native_helper(
            "tests/fixtures/stdlib_foundation/resolve/oracle.c",
            "native-oracle",
            false,
        )
    })
}
fn oracle(mode: &str) {
    let output = common::process_output_with_timeout(
        format!("resolve-host {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/stdlib_foundation/resolve_host/oracle.py"))
            .arg(mode)
            .arg(cli().path())
            .arg(observer().path())
            .arg(native_oracle().path()),
        Duration::from_secs(70),
    );
    common::assert_command_success(format!("resolve-host {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("resolve-host-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn ordered_numeric_local_named_service_and_passive_results_match_native_resolver() {
    oracle("matrix");
}
#[test]
fn arguments_result_caps_staged_output_and_native_failures_publish_no_partial_list() {
    oracle("limits");
}
#[test]
fn real_output_faults_and_global_attempt_budgets_preserve_confirmed_prefix() {
    oracle("io");
}
#[test]
fn every_observed_local_allocation_failure_releases_mappings_and_native_list() {
    oracle("resources");
}
#[test]
fn actual_output_helper_handles_short_writes_interruptions_counts_and_final_flush() {
    let source =
        std::fs::read_to_string(root().join("sample_programs/library/resolve_host.lani")).unwrap();
    let (helpers, _) = source
        .rsplit_once("fn main() -> i32 {")
        .expect("production entry follows helpers");
    let fixtures = std::fs::read_to_string(
        root().join("tests/fixtures/stdlib_foundation/resolve_host/scripted.lani"),
    )
    .unwrap();
    let entry = common::TempArtifact::new("laniusc_resolve_host", "scripted", Some("lani"));
    entry.write_str(&format!("{helpers}\n{fixtures}"));
    let executable = compile(entry.path().to_path_buf(), "scripted");
    let output = common::process_output_with_timeout(
        "resolve-host scripted",
        &mut Command::new(executable.path()),
        Duration::from_secs(8),
    );
    common::assert_command_success("resolve-host scripted", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    eprintln!("resolve-host-scripted cases=1 (24 helper scenarios)");
}
