#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
// sample_programs/library/agent_fetch.lani (ext::http_agent's streamed
// response bodies, std::cli options) against Python http.server,
// libnghttp2's server session over TLS, and the ext::http_proxy fixtures.
use crate::common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn build(path: &'static str, stem: &str, tls: bool) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        if tls {
            // ext::openssl_tls (and libc name resolution) need native linking.
            let options = laniusc_compiler::compiler::NativeLinkOptions {
                libraries: vec!["ssl".into(), "crypto".into()],
                ..Default::default()
            };
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ))
        } else {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
            )
        }
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_agent_fetch", stem, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn client() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| build("sample_programs/library/agent_fetch.lani", "agent_fetch", true))
}

fn group(args: &[&std::ffi::OsStr], expected: &str) {
    let out = common::process_output_with_timeout(
        "agent-fetch oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/http_agent/fetch_oracle.py"))
            .args(args),
        Duration::from_secs(120),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(String::from_utf8(out.stdout).unwrap().trim(), expected);
}

#[test]
fn streams_bodies_from_python_http_server_with_keep_alive_redirects_and_timeouts() {
    group(&["http".as_ref(), client().path().as_os_str()], "agent-fetch-http cases=12");
}

#[test]
fn streams_http2_bodies_from_nghttp2_through_flow_control() {
    group(&["h2".as_ref(), client().path().as_os_str()], "agent-fetch-h2 cases=6");
}

#[test]
fn streams_through_the_reverse_proxy_and_its_tls_front_end() {
    let proxy = build("tests/fixtures/extended/http_proxy/proxy_main.lani", "proxy", false);
    let tls = build("tests/fixtures/extended/http_proxy/tls_main.lani", "tls_proxy", true);
    group(
        &["proxy".as_ref(), client().path().as_os_str(), proxy.path().as_os_str(), tls.path().as_os_str()],
        "agent-fetch-proxy cases=4",
    );
}
