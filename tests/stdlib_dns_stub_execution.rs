//! UDP deadlines, resolv.conf/hosts parsing and the stub resolver; the stub-dig
//! program against fake loopback DNS servers.
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
fn executable(path: &'static str, label: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("dns_stub", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn stub_dig() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/stub_dig.lani", "stub_dig"))
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("stub-dig {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_dns_stub/oracle.py"))
            .arg(mode)
            .arg(stub_dig().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("stub-dig {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("stub-dig-{mode} cases={cases}\n")
    );
}

#[test]
fn udp_deadline_and_resolver_config_contracts_execute() {
    let exe = executable("tests/fixtures/stdlib_dns_stub/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "dns stub contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("dns stub contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn stub_dig_cli_numeric_and_hosts_answers_match_host() {
    oracle("cli", 30);
}
#[test]
fn stub_dig_matches_fake_servers_with_failover_truncation_and_malformed_replies() {
    oracle("dns", 42);
}
