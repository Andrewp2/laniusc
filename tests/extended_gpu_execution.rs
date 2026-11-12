//! The first native Vulkan profile: hardware work, pixels, ownership and failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(path: &str, probe: bool) -> common::TempArtifact {
    let object = common::TempArtifact::new("gpu", "probe", Some("o"));
    // Explicit versioned loader path also works without a development symlink.
    let loader = std::env::var_os("LANIUS_VULKAN_LOADER")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/lib/x86_64-linux-gnu/libvulkan.so.1"));
    let mut objects = vec![loader];
    if probe {
        let include =
            std::env::var_os("LANIUS_VULKAN_INCLUDE").unwrap_or_else(|| "/usr/include".into());
        let output = common::process_output_with_timeout(
            "Vulkan observer",
            Command::new("cc")
                .args([
                    "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-I",
                ])
                .arg(include)
                .arg("-c")
                .arg(root().join("tests/fixtures/extended/gpu/probe.c"))
                .arg("-o")
                .arg(object.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("Vulkan observer", &output);
        objects.push(object.path().to_path_buf());
    }
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![
            root().join("extended"),
            root().join("sample_programs/library"),
        ],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        objects,
        libraries: vec!["X11".into(), "dl".into(), "pthread".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("native Vulkan", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|e| panic!("GPU example compilation: {e}"));
    let exe = common::TempArtifact::new("gpu", "native", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(exe: &common::TempArtifact, args: &[&str], interactive: bool) {
    let mut cmd = Command::new(exe.path());
    cmd.args(args);
    // Limit validation to the generated program; compiler shaders have their own checks.
    cmd.env("VK_INSTANCE_LAYERS", "VK_LAYER_KHRONOS_validation")
        .env("VK_LAYER_VALIDATE_SYNC", "true")
        .env(
            "VK_LAYER_ENABLES",
            "VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT",
        );
    if interactive {
        cmd.env("GPU_PROBE_INTERACTIVE", "1");
    }
    let output = common::process_output_with_timeout(
        "Vulkan native execution",
        &mut cmd,
        Duration::from_secs(25),
    );
    common::assert_command_success("Vulkan native execution", &output);
    // Validation diagnostics, including layer load failures, fail this gate.
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
#[ignore = "requires Vulkan 1.1, maintenance extensions and Khronos validation; run explicitly"]
fn buffers_copy_on_gpu_and_read_back() {
    run(
        &compile("tests/fixtures/extended/gpu/buffer.lani", false),
        &[],
        false,
    );
}
#[test]
#[ignore = "requires X11, Vulkan headers/driver and Khronos validation; run explicitly"]
fn pixels_resize_events_and_reached_failures() {
    run(
        &compile("tests/fixtures/extended/gpu/contracts.lani", true),
        &[],
        false,
    );
}
#[test]
#[ignore = "requires X11, Vulkan headers/driver and Khronos validation; run explicitly"]
fn interactive_triangle_handles_resize_close_and_frame_limit() {
    let exe = compile("sample_programs/library/gpu_triangle.lani", true);
    run(&exe, &["--frames", "3"], false);
    run(&exe, &[], true);
    for args in [
        vec!["--frames", "0"],
        vec!["--frames", "601"],
        vec!["--frames"],
        vec!["--oops"],
    ] {
        let output = common::process_output_with_timeout(
            "GPU example arguments",
            Command::new(exe.path())
                .args(args)
                .env("DISPLAY", "invalid-display-name"),
            Duration::from_secs(5),
        );
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(String::from_utf8_lossy(&output.stderr).contains("Usage:"));
    }
}
#[test]
#[ignore = "requires Vulkan headers/driver and Khronos validation; run explicitly"]
fn asynchronous_copies_retain_resources() {
    run(&compile("tests/fixtures/extended/gpu/async.lani", true), &[], false);
}
#[test]
#[ignore = "requires Vulkan headers/driver and Khronos validation; run explicitly"]
fn compute_writes_buffer_and_texture() {
    run(&compile("tests/fixtures/extended/gpu/compute.lani", true), &[], false);
}
#[test]
#[ignore = "requires Vulkan headers/driver and Khronos validation; run explicitly"]
fn texture_transfers_bindings_and_failure_cleanup() {
    run(&compile("tests/fixtures/extended/gpu/resources.lani", true), &[], false);
}
#[test]
#[ignore = "requires X11, Vulkan headers/driver and Khronos validation; run explicitly"]
fn compute_texture_sampling_and_async_presentation() {
    run(&compile("tests/fixtures/extended/gpu/present_async.lani", true), &[], false);
}
#[test]
#[ignore = "requires X11, Vulkan headers/driver and Khronos validation; run explicitly"]
fn compute_example_handles_resize_close_and_frame_limit() {
    let exe = compile("sample_programs/library/gpu_compute.lani", true);
    run(&exe, &["--frames", "3"], false);
    run(&exe, &[], true);
}
#[test]
#[ignore = "requires Vulkan headers/driver and Khronos validation; run explicitly"]
fn game_of_life_generations_match_reference() {
    run(&compile("tests/fixtures/extended/gpu/life.lani", true), &[], false);
}
#[test]
#[ignore = "requires X11, Vulkan headers/driver and Khronos validation; run explicitly"]
fn game_of_life_window_and_frame_limit() {
    let exe = compile("sample_programs/library/gpu_life.lani", true);
    run(&exe, &["--frames", "6"], false);
    run(&exe, &[], true);
    for args in [vec!["--frames", "0"], vec!["--frames", "601"], vec!["--frames"], vec!["--oops"]] {
        let output = common::process_output_with_timeout("Life arguments", Command::new(exe.path()).args(args).env("DISPLAY", "invalid-display-name"), Duration::from_secs(5));
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(String::from_utf8_lossy(&output.stderr).contains("Usage:"));
    }
}
