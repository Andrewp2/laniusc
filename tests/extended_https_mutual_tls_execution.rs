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
fn compile(entry: PathBuf, name: &str) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_https_mutual", name, None);
    std::fs::write(executable.path(), bytes).unwrap();
    let checked = common::process_output_with_timeout(
        format!("{name} linked ELF"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success(format!("{name} linked ELF"), &checked);
    let linked = common::process_output_with_timeout(
        format!("{name} dependencies"),
        Command::new("readelf").arg("-d").arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success(format!("{name} dependencies"), &linked);
    let text = String::from_utf8(linked.stdout).unwrap();
    assert!(
        text.contains("libssl.so.3") && text.contains("libcrypto.so.3"),
        "{text}"
    );
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn fetch() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("sample_programs/library/https_fetch.lani"),
            "mutual-fetch",
        )
    })
}
fn serve() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("sample_programs/library/https_serve.lani"),
            "mutual-serve",
        )
    })
}
fn prepared() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("tests/fixtures/extended/https_mutual_tls/prepared.lani"),
            "mutual-prepared",
        )
    })
}
fn oracle(mode: &str) {
    let mut command = Command::new("python3");
    command
        .arg(root().join("tests/fixtures/extended/https_mutual_tls/oracle.py"))
        .arg(mode);
    if mode == "prepared" {
        command.arg("-").arg("-").arg(prepared().path());
    } else {
        command.arg(fetch().path()).arg(serve().path()).arg("-");
    }
    let output = common::process_output_with_timeout(
        format!("HTTPS mutual {mode}"),
        &mut command,
        Duration::from_secs(70),
    );
    common::assert_command_success(format!("HTTPS mutual {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("https-mutual-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn real_client_credentials_and_required_service_authentication_interoperate() {
    oracle("matrix");
}
#[test]
fn client_and_server_credential_chain_identity_failures_have_no_http_output() {
    oracle("failures");
}
#[test]
fn credential_flags_deadlines_and_budgets_remain_explicit_and_bounded() {
    oracle("limits");
}
#[test]
fn prepared_context_is_borrowed_and_native_session_retains_its_configured_limits() {
    oracle("prepared");
}
