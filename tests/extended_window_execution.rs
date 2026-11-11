//! Native X11 windows, event ABI, pixel readback and reached failure ownership.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(path: &str, probe: bool) -> common::TempArtifact {
    let object = common::TempArtifact::new("window", "probe", Some("o"));
    let mut objects = Vec::new();
    if probe {
        let output = common::process_output_with_timeout(
            "X11 window observer",
            Command::new("cc")
                .args([
                    "-std=c11",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fPIC",
                    "-fno-optimize-sibling-calls",
                    "-c",
                ])
                .arg(root().join("tests/fixtures/extended/window/probe.c"))
                .arg("-o")
                .arg(object.path()),
            Duration::from_secs(15),
        );
        common::assert_command_success("X11 window observer", &output);
        objects.push(object.path().to_path_buf());
    }
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        objects,
        libraries: vec!["X11".into(), "dl".into(), "pthread".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("X11 window", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|e| panic!("window compile: {e}"));
    let exe = common::TempArtifact::new("window", "native", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(exe: &common::TempArtifact, args: &[&str], close: bool) {
    let mut command = Command::new(exe.path());
    command.args(args);
    if close {
        command.env("WINDOW_PROBE_CLOSE", "1");
    }
    let output = common::process_output_with_timeout(
        "X11 window execution",
        &mut command,
        Duration::from_secs(15),
    );
    common::assert_command_success("X11 window execution", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
#[ignore = "requires an X11 display (real X11/XWayland or Xvfb at depth 24); run with --include-ignored"]
fn windows_events_pixels_and_reached_failures_preserve_ownership() {
    run(
        &compile("tests/fixtures/extended/window/contracts.lani", true),
        &[],
        false,
    );
}
#[test]
fn missing_display_is_an_explicit_error() {
    let exe = compile("tests/fixtures/extended/window/unavailable.lani", false);
    let output = common::process_output_with_timeout(
        "unavailable display",
        Command::new(exe.path()).env("DISPLAY", "invalid-display-name"),
        Duration::from_secs(10),
    );
    common::assert_command_success("unavailable display", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
#[ignore = "requires an X11 display; run with --include-ignored"]
fn plain_window_opens_presents_and_closes() {
    run(
        &compile("tests/fixtures/extended/window/smoke.lani", false),
        &[],
        false,
    );
}
#[test]
#[ignore = "requires an X11 display; run with --include-ignored"]
fn interactive_sample_handles_close_and_bounded_frames() {
    let exe = compile("sample_programs/library/window_demo.lani", true);
    run(&exe, &["--frames", "3"], false);
    run(&exe, &[], true);
    for args in [
        vec!["--frames", "0"],
        vec!["--frames", "601"],
        vec!["--frames"],
        vec!["--bad", "3"],
    ] {
        let output = common::process_output_with_timeout(
            "invalid canvas arguments",
            Command::new(exe.path())
                .args(args)
                .env("DISPLAY", "invalid-display-name"),
            Duration::from_secs(5),
        );
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty());
        assert!(String::from_utf8_lossy(&output.stderr).contains("Usage:"));
    }
}
