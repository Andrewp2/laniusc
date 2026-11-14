#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]

//! A native build elaborates the files of all its units in one run of each
//! rewrite (closures, generators, machines) before the first unit compiles.

use crate::common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    NativeLinkOptions,
    compile_entry_to_x86_64_with_native_link,
};

fn repository() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    repository().join("tests/fixtures/native_c_elaboration").join(name)
}

fn build(name: &str) -> Result<Vec<u8>, CompileError> {
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository().join("stdlib")),
        user_roots: vec![fixture("")],
    };
    let entry = fixture(&format!("{name}.lani"));
    common::run_gpu_codegen_with_timeout("native elaboration", move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry,
            &roots,
            &NativeLinkOptions::default(),
        ))
    })
}

fn assert_runs(name: &str) {
    let bytes = build(name).unwrap_or_else(|error| panic!("native elaboration {name}: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_elaboration", name, None);
    fs::write(executable.path(), bytes).expect("write executable");
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make executable runnable");
    let output = common::process_output_with_timeout(
        format!("execute native elaboration fixture {name}"),
        &mut Command::new(executable.path()),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
}

#[test]
fn a_native_build_rewrites_the_files_of_its_units_together() {
    assert_runs("rewrites");
}

/// When the program does not parse, the joint run reads no file as
/// rewritten or unchanged. Each unit then rewrites its own files, the build
/// reports the parse error, and the standard library's machine still
/// expands in the next build.
#[test]
fn a_unit_that_does_not_parse_leaves_the_other_units_rewrites_to_them() {
    let error = build("unparsed").expect_err("the program does not parse");
    assert!(format!("{error:?}").contains("unparsed.lani"), "{error:?}");
    assert_runs("rewrites");
}
