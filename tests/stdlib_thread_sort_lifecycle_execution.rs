//! Sort semantics and synchronous caller-backing lifetime under real pthread faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
use crate::common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn threaded_sort_preserves_owners_until_join_and_traps_on_unprovable_quiescence() {
    let mut objects = Vec::new();
    for (name, source) in [
        ("thread_probe", "stdlib_thread_lifecycle/thread_probe.c"),
        ("deny_wake", "stdlib_thread_sort_lifecycle/deny_wake.c"),
    ] {
        let object = common::TempArtifact::new("laniusc_thread_sort", name, Some("o"));
        // Keep helper-to-libc edges as calls for the native source-site verifier.
        let output = common::process_output_with_timeout(
            "compile sort fault observation helper",
            Command::new("cc")
                .args([
                    "-std=c11",
                    "-O2",
                    "-fno-optimize-sibling-calls",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fPIC",
                    "-c",
                ])
                .arg(root().join("tests/fixtures").join(source))
                .arg("-o")
                .arg(object.path()),
            Duration::from_secs(15),
        );
        common::assert_command_success("sort fault observation helper", &output);
        objects.push(object);
    }
    let entry = root().join("tests/fixtures/stdlib_thread_sort_lifecycle/sort.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: Vec::new(),
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        objects: objects
            .iter()
            .map(|object| object.path().to_path_buf())
            .collect(),
        libraries: vec!["dl".into(), "atomic".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("threaded sort lifecycle", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("threaded sort lifecycle: {error}"));
    let executable = common::TempArtifact::new("laniusc_thread_sort", "sort", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "threaded sort values and lifetime",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root().join("tests/fixtures/stdlib_thread_sort_lifecycle/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(80),
    );
    common::assert_command_success("threaded sort values and lifetime", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        b"thread-sort normal=38 admission=12 worker-error=1 faults=10 traced=11\n"
    );
}
