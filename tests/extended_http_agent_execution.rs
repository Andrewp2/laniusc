#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn client() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let path = "sample_programs/library/http_curl.lani";
        let entry = root().join(path);
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        // ext::url_connect resolves names through libc; https:// goes through
        // ext::tls_stream, so the client links OpenSSL 3.
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["ssl".into(), "crypto".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout(path, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("{path}: {e}"));
        let exe = common::TempArtifact::new("laniusc_http_agent", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

fn group(name: &str, expected: &str) {
    let out = common::process_output_with_timeout(
        "HTTP agent loopback oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/http_agent/oracle.py"))
            .arg(name)
            .arg(client().path()),
        Duration::from_secs(90),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim(),
        format!("http-agent-{name} {expected}")
    );
}

#[test]
fn keep_alive_pool_reuses_expires_evicts_and_retries_stale_connections() {
    group("pool", "cases=18 connections=33 requests=44");
}

#[test]
fn redirects_follow_limits_method_rules_and_origin_policy() {
    group("redirect", "cases=29 connections=31 requests=67");
}

#[test]
fn chunked_and_fixed_uploads_including_early_final_responses() {
    group("upload", "cases=10 connections=8 requests=9");
}

#[test]
fn broken_servers_map_to_typed_errors_and_curl_exit_codes() {
    group("broken", "cases=21 connections=18 requests=1");
}

#[test]
fn https_pools_tls_connections_and_follows_scheme_redirects() {
    group("https", "cases=17 connections=22 requests=27");
}

// HTTP/2 over TLS with ALPN against libnghttp2's server session.
#[test]
fn https_negotiates_http2_multiplexes_streams_and_falls_back_to_http11() {
    let out = common::process_output_with_timeout(
        "HTTP/2 agent loopback oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/http2/agent_oracle.py"))
            .arg("h2")
            .arg(client().path()),
        Duration::from_secs(120),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim(),
        "http2-agent-h2 cases=21 connections=23 requests=43"
    );
}
