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
        .join("tests/fixtures/native_c_callback")
        .join(name)
}

/// Links a callback fixture against libc and returns the executable.
fn link(name: &str) -> common::TempArtifact {
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository().join("stdlib")),
        user_roots: vec![fixture("")],
    };
    let entry = fixture(&format!("{name}.lani"));
    let options = NativeLinkOptions::default();
    let bytes = common::run_gpu_codegen_with_timeout("native C callback", move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
    .unwrap_or_else(|error| panic!("native C callback {name}: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_c_callback", name, None);
    fs::write(executable.path(), bytes).expect("write C callback executable");
    let mut validation = Command::new("python3");
    validation
        .arg(repository().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path());
    let output = common::process_output_with_timeout(
        "validate native C callback linked ELF",
        &mut validation,
        Duration::from_secs(30),
    );
    common::assert_command_success("native C callback linked ELF", &output);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make C callback executable runnable");
    executable
}

fn assert_exits_zero(name: &str, executable: &Path, args: &[&str]) {
    let output = common::process_output_with_timeout(
        format!("execute C callback fixture {name}"),
        Command::new(executable).args(args),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{name} {args:?}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn lanius_functions_are_c_callbacks_for_qsort_bsearch_and_pthread() {
    for name in ["qsort", "bsearch"] {
        let executable = link(name);
        assert_exits_zero(name, executable.path(), &[]);
    }
    // The worker reads argc through R15 on a thread glibc created, so a
    // different argc gives a different, checked result.
    let executable = link("pthread");
    assert_exits_zero("pthread", executable.path(), &[]);
    assert_exits_zero("pthread", executable.path(), &["one", "two", "three"]);
}
