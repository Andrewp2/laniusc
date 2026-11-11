//! Recursive consumer contracts for std::walk, through the real text_grep app.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/text_grep.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("recursive text-grep", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry,
                    &roots,
                    &Default::default(),
                ),
            )
        })
        .unwrap_or_else(|error| panic!("recursive text-grep: {error}"));
        let executable = common::TempArtifact::new("laniusc_text_grep_walk", "consumer", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn check(mode: &str, prefix: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "recursive text-grep focused oracle",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root.join("tests/fixtures/extended/text_grep_walk/oracle.py"))
            .arg(executable().path())
            .arg(mode),
        Duration::from_secs(70),
    );
    common::assert_command_success("recursive text-grep", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(summary.starts_with(prefix), "{summary}");
    assert!(summary.ends_with(" failures=0\n"), "{summary}");
    eprint!("{summary}");
}

#[test]
fn recursive_text_grep_preserves_gnu_order_filters_symlinks_and_git_scopes() {
    check("compare", "text-grep-walk compare=");
}

#[test]
fn recursive_text_grep_recovers_child_faults_and_releases_owners_on_fatal_errors() {
    check("faults", "text-grep-walk faults=");
}
