//! Bounded binary chunk checksums through real native pool workers.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
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

fn executable(probe: bool) -> &'static common::TempArtifact {
    static PLAIN: OnceLock<common::TempArtifact> = OnceLock::new();
    static PROBE: OnceLock<common::TempArtifact> = OnceLock::new();
    let slot = if probe { &PROBE } else { &PLAIN };
    slot.get_or_init(|| {
        let object = common::TempArtifact::new("parallel_checksums", "thread_probe", Some("o"));
        let mut objects = Vec::new();
        let mut libraries = vec!["atomic".into()];
        if probe {
            let output = common::process_output_with_timeout(
                "parallel checksums pthread probe",
                Command::new("cc")
                    .args([
                        "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-c",
                    ])
                    .arg(root().join("tests/fixtures/stdlib_thread_lifecycle/thread_probe.c"))
                    .arg("-o")
                    .arg(object.path()),
                Duration::from_secs(20),
            );
            common::assert_command_success("parallel checksums pthread probe", &output);
            objects.push(object.path().to_path_buf());
            libraries.push("dl".into());
        }
        let entry = root().join("sample_programs/library/parallel_checksums.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            objects,
            libraries,
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("parallel checksums", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("parallel checksums: {error}"));
        let artifact = common::TempArtifact::new(
            "parallel_checksums",
            if probe { "probe" } else { "plain" },
            None,
        );
        std::fs::write(artifact.path(), bytes).unwrap();
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn oracle(group: &str, probe: bool) {
    let output = common::process_output_with_timeout(
        format!("parallel checksums {group}"),
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root().join("tests/fixtures/stdlib_execution/parallel_checksums/oracle.py"))
            .arg(group)
            .arg(executable(probe).path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("parallel checksums {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("parallel-checksums-{group} cases=")),
        "{summary}"
    );
    assert!(summary.contains(" evidence="), "{summary}");
    eprint!("{summary}");
}

#[test]
fn parallel_checksums_matches_zlib_for_binary_chunks() {
    oracle("model", false);
}
#[test]
fn parallel_checksums_validates_cli_before_input_or_output() {
    oracle("admission", false);
}
#[test]
fn parallel_checksums_enforces_input_chunk_and_worker_bounds() {
    oracle("limits", false);
}
#[test]
fn parallel_checksums_reached_allocations_and_io_failures_retire_owners() {
    oracle("resources", true);
}
#[test]
fn parallel_checksums_runs_real_workers_handles_spawn_fallback_and_traps_on_failed_join() {
    oracle("threads", true);
}
