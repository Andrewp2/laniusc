//! Reached constructor/node OOM and post-commit wake failures in real channels.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn thread_channels_recover_before_publication_and_trap_failed_committed_wakes() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_thread_channel_allocation");
    let entry = fixtures.join("probe.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["atomic".into()],
        ..Default::default()
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("thread channel allocation probe", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("thread channel allocation probe: {error}"));
    let executable = common::TempArtifact::new("laniusc_thread_channel", "allocation", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "thread channel allocation and wake oracle",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(fixtures.join("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("thread channel allocation and wake oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let report = String::from_utf8(output.stdout).unwrap();
    assert!(
        report.starts_with(
            "thread-channel-allocation: profiles=12 reached-oom=6 reached-wake-eio=6 "
        ),
        "{report}"
    );
    assert!(report.ends_with("\n"), "{report}");
    eprint!("{report}");
}
