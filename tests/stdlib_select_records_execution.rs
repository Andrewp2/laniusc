//! Binary delimited record selection through a buffered input protocol.
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
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/select_records.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "bounded delimited record selection application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("select records: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "select records must compile to an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("select_records", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(
        format!("select records {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/select_records/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("select records {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    if let Some(count) = count {
        assert!(
            summary.starts_with(&format!("select-records-{mode} cases={count} evidence=")),
            "{summary}"
        );
    } else {
        let fields = summary.split_whitespace().collect::<Vec<_>>();
        assert_eq!(fields.len(), 4, "{summary}");
        assert_eq!(fields[0], "select-records-io", "{summary}");
        let cases: usize = fields[1].strip_prefix("cases=").unwrap().parse().unwrap();
        let allocations: usize = fields[2]
            .strip_prefix("reached_allocations=")
            .unwrap()
            .parse()
            .unwrap();
        assert!(
            allocations > 0 && fields[3].starts_with("evidence="),
            "{summary}"
        );
        assert_eq!(cases, 13 + allocations, "{summary}");
    }
    eprint!("{summary}");
}
#[test]
fn select_records_binary_selection_and_stream_boundaries_match_independent_model() {
    oracle("model", Some(33));
}
#[test]
fn select_records_selected_skipped_and_total_limits_publish_nothing() {
    oracle("limits", Some(8));
}
#[test]
fn select_records_strict_cli_and_help_preflight_execute() {
    oracle("cli", Some(33));
}
#[test]
fn select_records_reached_owner_faults_io_retries_and_actual_prefix_execute() {
    oracle("io", None);
}
