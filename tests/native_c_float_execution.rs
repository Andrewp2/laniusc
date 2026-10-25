#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]

mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use laniusc_compiler::compiler::{
    EntrySourceRoots,
    NativeLinkOptions,
    compile_entry_to_x86_64_with_native_link,
};

fn repository() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    repository()
        .join("tests/fixtures/native_c_float")
        .join(name)
}

#[test]
fn native_c_floats_preserve_bits_mixed_banks_stack_and_generic_replay() {
    let objects = ["probes.c", "probes.S"]
        .into_iter()
        .map(|source| {
            let object = common::TempArtifact::new("laniusc_native_c_float", source, Some("o"));
            let mut command = Command::new("cc");
            command
                .args([
                    "-c",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fno-stack-protector",
                    "-fno-fast-math",
                ])
                .arg(fixture(source))
                .arg("-o")
                .arg(object.path());
            let output = common::process_output_with_timeout(
                format!("compile independent floating C ABI probe {source}"),
                &mut command,
                Duration::from_secs(20),
            );
            common::assert_command_success(source, &output);
            object
        })
        .collect::<Vec<_>>();
    let options = NativeLinkOptions {
        objects: objects
            .iter()
            .map(|object| object.path().to_path_buf())
            .collect(),
        ..NativeLinkOptions::default()
    };
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository().join("stdlib")),
        user_roots: vec![fixture("")],
    };
    let entry = fixture("main.lani");
    let bytes = common::run_gpu_codegen_with_timeout("native C floating scalar ABI", move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
    .unwrap_or_else(|error| panic!("native C floating scalar ABI: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_c_float", "float_contracts", None);
    // A CRT-linked executable contains valid PLT/CRT tail jumps. Check its
    // sized Lanius symbols with the linked profile instead of the raw profile.
    fs::write(executable.path(), bytes).expect("write floating C ABI executable");
    let mut validation = Command::new("python3");
    validation
        .arg(repository().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path());
    let output = common::process_output_with_timeout(
        "validate native C floating linked ELF",
        &mut validation,
        Duration::from_secs(30),
    );
    common::assert_command_success("native C floating linked ELF", &output);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make floating C ABI executable runnable");
    let output = common::process_output_with_timeout(
        "execute floating C ABI bit, bank, stack, liveness and generic contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(2),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "float ABI stages: bits=1..10, banks/stack=21..24, liveness=41..45, generic=61; {output:?}"
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
