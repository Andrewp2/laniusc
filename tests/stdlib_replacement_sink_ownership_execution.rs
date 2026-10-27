//! Real replacement owners, explicit recovery and reached allocation failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn probe() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_execution/replacement_sinks/probe.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("replacement sink owners", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("replacement sink owner probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_replacement_sink_owners", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "replacement sink ownership oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/stdlib_execution/replacement_sinks/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("replacement sink ownership oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("PASS replacement-sinks group={group} cases=");
    let receipts: Vec<(usize, usize)> = summary
        .lines()
        .filter_map(|line| line.strip_prefix(&prefix))
        .map(|receipt| {
            let (numbers, _classes) = receipt.split_once(" classes=").expect("fault role counts");
            let (cases, denials) = numbers
                .split_once(" reached-oom=")
                .expect("finite cases/denials");
            (cases.parse().unwrap(), denials.parse().unwrap())
        })
        .collect();
    assert_eq!(receipts.len(), 1, "{summary}");
    let (cases, denials) = receipts[0];
    if group == "lifecycle" {
        assert_eq!((cases, denials), (20, 0), "{summary}");
    } else {
        assert!(denials > 0 && cases == denials + 4, "{summary}");
    }
    print!("{summary}");
}

#[test]
fn complete_replacement_owners_survive_recovery_and_release_before_exit() {
    gate("lifecycle");
}

#[test]
fn hash_map_replacement_and_history_each_reached_allocation_is_recoverable() {
    gate("hash-map-oom");
}

#[test]
fn tree_map_replacement_and_history_each_reached_allocation_is_recoverable() {
    gate("tree-map-oom");
}

#[test]
fn hash_set_representative_and_history_each_reached_allocation_is_recoverable() {
    gate("hash-set-oom");
}

#[test]
fn tree_set_representative_and_history_each_reached_allocation_is_recoverable() {
    gate("tree-set-oom");
}
