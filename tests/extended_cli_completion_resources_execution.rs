//! Real KV completion query allocation and output failures, with full traces.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
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
        let entry = root.join("sample_programs/library/kv_tool.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("KV completion resources", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("KV completion resource executable: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("cli_completion_resources", "kv", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "KV completion resource oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/extended/cli_complete/resources_oracle.py"))
            .arg(executable().path())
            .arg(group),
        Duration::from_secs(95),
    );
    common::assert_command_success("KV completion resource oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII resource receipt");
    assert_eq!(summary.lines().count(), 1, "{summary}");
    let prefix = format!("cli-completion resources group={group} cases=");
    let receipt = summary
        .trim_end()
        .strip_prefix(&prefix)
        .expect("group receipt");
    let (numbers, evidence) = receipt
        .split_once(" evidence=")
        .expect("evidence directory");
    let (cases, denials) = numbers.split_once(" reached-oom=").expect("finite counts");
    let cases: usize = cases.parse().unwrap();
    let denials: usize = denials.parse().unwrap();
    assert!(!evidence.is_empty());
    if group == "allocations" {
        assert!(denials > 0 && cases == denials + 3, "{summary}");
    } else {
        assert_eq!((cases, denials), (12, 0), "{summary}");
    }
    print!("{summary}");
}

#[test]
fn completion_query_each_reached_source_allocation_fails_without_partial_reply_or_file_access() {
    gate("allocations");
}

#[test]
fn completion_query_output_failures_release_decoded_candidate_and_reply_owners() {
    gate("output");
}
