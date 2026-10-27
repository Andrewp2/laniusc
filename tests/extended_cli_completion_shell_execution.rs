//! Actual Bash 5.2/helper integration and controlling-terminal Readline checks.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn kv() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let entry = root().join("sample_programs/library/kv_tool.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("completion actual KV", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("completion actual KV: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("cli_completion_shell", "kv", None);
        // The shared writer applies the complete function-jump ELF validator.
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn run(mode: &str, seconds: u64) -> Vec<u8> {
    let program = if mode == "deadline" {
        PathBuf::from("-")
    } else {
        kv().path().to_owned()
    };
    let output = common::process_output_with_timeout(
        &format!("actual Bash completion {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/cli_complete/shell_oracle.py"))
            .arg(mode)
            .arg(program)
            .arg(root().join("extended/shell/lanius-completion.bash")),
        Duration::from_secs(seconds),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}

#[test]
fn reserved_query_frames_do_not_load_response_files_or_database() {
    assert_eq!(
        run("query", 20),
        b"cli-completion shell queries cases=18 no-file-traces=3\n"
    );
}

#[test]
fn bash_function_rejects_partial_frames_and_preserves_parent_options() {
    assert_eq!(
        run("function", 35),
        b"cli-completion shell functions cases=51 option-profiles=2\n"
    );
}

#[test]
fn failed_or_missing_deadline_helper_reaps_stalled_producer_before_reply() {
    assert_eq!(
        run("deadline", 12),
        b"cli-completion shell deadline cases=2 pre-exit-groups-empty=2\n"
    );
}

#[test]
fn readline_inserts_literal_binary_filenames_and_preserves_cursor_suffix() {
    assert_eq!(
        run("pty", 45),
        b"cli-completion shell pty cases=26 locale=C.UTF-8\n"
    );
}

#[test]
fn readline_leading_quote_transitions_preserve_first_filename_byte() {
    assert_eq!(
        run("boundary", 15),
        b"cli-completion shell boundary cases=2 fresh-cwds=2\n"
    );
}
