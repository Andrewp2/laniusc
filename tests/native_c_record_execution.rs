#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]

use crate::common;

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
        .join("tests/fixtures/native_c_record")
        .join(name)
}

/// A record with one integer or pointer field crosses the C boundary as that
/// field: in a register, on the stack, as a result, and from another module.
#[test]
fn one_field_records_cross_the_c_boundary_by_value() {
    let objects = ["probes.c", "probes.S"]
        .into_iter()
        .map(|source| {
            let object = common::TempArtifact::new("laniusc_native_c_record", source, Some("o"));
            let mut command = Command::new("cc");
            command
                .args([
                    "-c",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fno-stack-protector",
                ])
                .arg(fixture(source))
                .arg("-o")
                .arg(object.path());
            let output = common::process_output_with_timeout(
                format!("compile record C ABI probe {source}"),
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
    let bytes = common::run_gpu_codegen_with_timeout("native C record ABI", move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
    .unwrap_or_else(|error| panic!("native C record ABI: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_c_record", "record_contracts", None);
    fs::write(executable.path(), bytes).expect("write record C ABI executable");
    let mut validation = Command::new("python3");
    validation
        .arg(repository().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path());
    let output = common::process_output_with_timeout(
        "validate native C record linked ELF",
        &mut validation,
        Duration::from_secs(30),
    );
    common::assert_command_success("native C record linked ELF", &output);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make record C ABI executable runnable");
    let output = common::process_output_with_timeout(
        "execute record C ABI register, stack, import and field width contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(2),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "record ABI stages: register=1..6, stack=11..12, imported=21..24, wide fields=31..35; {output:?}"
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

/// A public C declaration is part of its module's interface, so a private
/// record in it is reported like any private type in a public signature.
#[test]
fn a_public_c_declaration_needs_a_public_record() {
    let source = "module app::main;\n\
        struct Cookie { sequence: u32 }\n\
        pub extern \"C\" fn make_cookie(value: u32) -> Cookie;\n\
        fn main() -> i32 { return 0; }\n";
    let error = common::semantic_interface_with_timeout(76, &[source])
        .expect_err("a private record in a public C declaration must be rejected");
    match error {
        laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0075", "{diagnostic:?}");
        }
        other => panic!("expected a diagnostic, got {other:?}"),
    }
}
