//! ext::url (WHATWG URLs) and ext::idna (UTS #46): API contracts, the generated
//! IDNA table, and url-parse compared with the Node.js WHATWG URL implementation.
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
    let artifact = common::TempArtifact::new("extended_url", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn url_parse() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/url_parse.lani", "url_parse"))
}
fn has_node() -> bool {
    ["node", "nodejs"].iter().any(|name| {
        Command::new(name)
            .arg("--version")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    })
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("url-parse {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_url/oracle.py"))
            .arg(mode)
            .arg(url_parse().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("url-parse {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("url-{mode} cases={cases}\n")
    );
}

#[test]
fn url_api_contracts_execute() {
    let exe = executable("tests/fixtures/extended_url/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "url contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("url contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn url_parse_command_line_matches_expected_output() {
    oracle("cli", 25);
}
#[test]
fn url_parse_matches_node_whatwg_url_on_the_generated_corpus() {
    if !has_node() {
        eprintln!("skipping: node is not installed");
        return;
    }
    oracle("whatwg", 9174);
}
#[test]
fn url_parse_matches_node_on_internationalized_hosts() {
    if !has_node() {
        eprintln!("skipping: node is not installed");
        return;
    }
    oracle("idna", 46060);
}
#[test]
fn generated_idna_table_is_current_and_matches_node_per_scalar() {
    let check = common::short_process_output_with_timeout(
        "generate_idna.py",
        Command::new("python3")
            .arg("-I")
            .arg("tools/unicode17/generate_idna.py")
            .arg("--check")
            .current_dir(root()),
    );
    assert!(check.status.success(), "{check:?}");
    if !has_node() {
        eprintln!("skipping the per-scalar comparison: node is not installed");
        return;
    }
    oracle("table", 1111937);
}
