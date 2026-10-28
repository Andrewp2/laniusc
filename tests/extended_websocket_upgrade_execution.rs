//! WebSocket upgrade wire contracts and a real OpenSSL accept calculation.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root().join("tests/fixtures/extended/websocket_upgrade").join(name)
}
fn compile(name: &str, native: bool) -> common::TempArtifact {
    let entry = fixture(&format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("WebSocket upgrade", move || {
        if native {
            let options = laniusc_compiler::compiler::NativeLinkOptions {
                libraries: vec!["crypto".into()],
                ..Default::default()
            };
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        } else {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        }
    }).unwrap_or_else(|error| panic!("WebSocket upgrade {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_websocket_upgrade", name, None);
    if native {
        std::fs::write(executable.path(), bytes).unwrap();
        let output = common::process_output_with_timeout(
            "WebSocket upgrade linked ELF",
            Command::new("python3")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(executable.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("WebSocket upgrade linked ELF", &output);
    } else {
        executable.write_bytes(bytes);
    }
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn response_validation_and_encoding_preserve_protocol_selection_and_trailing_frame() {
    let executable = compile("contracts", false);
    let output = common::process_output_with_timeout(
        "WebSocket response contracts", &mut Command::new(executable.path()), Duration::from_secs(10),
    );
    common::assert_command_success("WebSocket response contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}

#[test]
fn native_accept_matches_independent_sha1_and_preserves_output_on_all_failures() {
    let executable = compile("accept_probe", true);
    let shim = common::TempArtifact::new("laniusc_websocket_upgrade", "so", None);
    let compiled = common::process_output_with_timeout(
        "WebSocket OpenSSL test interposer",
        Command::new("cc")
            .args(["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-shared", "-fPIC"])
            .arg(fixture("fault_interposer.c"))
            .arg("-o").arg(shim.path())
            .args(["-ldl", "-lcrypto"]),
        Duration::from_secs(20),
    );
    common::assert_command_success("WebSocket OpenSSL test interposer", &compiled);
    let output = common::process_output_with_timeout(
        "WebSocket accept differential oracle",
        Command::new("python3").arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path())
            .arg("--shim").arg(shim.path()),
        Duration::from_secs(45),
    );
    common::assert_command_success("WebSocket accept differential oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(summary.contains("websocket-accept cases=310 layouts=2 overlap=yes"), "{summary}");
    assert!(summary.contains("websocket-accept injected-cases=24 atomic=yes"), "{summary}");
    eprint!("{summary}");
}
