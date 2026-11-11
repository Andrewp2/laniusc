#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
// ext::http_proxy and its TLS front ends against Python oracles: asyncio
// upstreams (upstream.py), raw HTTP/1.1 sockets, libnghttp2 sessions
// (ctypes) and Python's ssl module with ALPN.
use crate::common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn roots() -> laniusc_compiler::compiler::EntrySourceRoots {
    laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    }
}

fn save(bytes: Vec<u8>, stem: &str) -> common::TempArtifact {
    let exe = common::TempArtifact::new("laniusc_http_proxy", stem, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn build(path: &'static str, stem: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = roots();
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    save(bytes, stem)
}

// Programs that use ext::openssl_tls link libssl and libcrypto.
fn build_tls(path: &'static str, stem: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let roots = roots();
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    save(bytes, stem)
}

fn proxy() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| build("tests/fixtures/extended/http_proxy/proxy_main.lani", "proxy"))
}

fn tls_proxy() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| build_tls("tests/fixtures/extended/http_proxy/tls_main.lani", "tls_proxy"))
}

fn python(what: &str, args: &[&std::ffi::OsStr], seconds: u64) -> String {
    let out = common::process_output_with_timeout(
        what,
        Command::new("python3").arg("-I").args(args),
        Duration::from_secs(seconds),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    String::from_utf8(out.stdout).unwrap()
}

fn fixture(name: &str) -> std::path::PathBuf {
    root().join("tests/fixtures/extended/http_proxy").join(name)
}

#[test]
fn http_body_framer_matches_rfc9112_reading_at_every_piece_size() {
    let exe = build("tests/fixtures/extended/http_proxy/body_driver.lani", "body");
    let out = python("http_body oracle", &[fixture("body_oracle.py").as_os_str(), exe.path().as_os_str()], 120);
    assert_eq!(out.trim(), "http-body cases=151");
}

#[test]
fn http_rewrite_drops_hop_by_hop_fields_and_appends_forwarding() {
    let exe = build("tests/fixtures/extended/http_proxy/rewrite_driver.lani", "rewrite");
    let out = python("http_rewrite oracle", &[fixture("rewrite_oracle.py").as_os_str(), exe.path().as_os_str()], 60);
    assert_eq!(out.trim(), "http-rewrite cases=11");
}

fn group(name: &str, expected: &str) {
    let out = python(
        "HTTP proxy oracle",
        &[fixture("proxy_oracle.py").as_os_str(), std::ffi::OsStr::new(name), proxy().path().as_os_str()],
        120,
    );
    assert_eq!(out.lines().last(), Some(expected), "{out}");
}

#[test]
fn http_proxy_forwards_http1_with_pools_rewrites_and_streamed_bodies() {
    group("h1", "http-proxy-h1 cases=19 requests=23 connects=5 reused=20 retries=2");
}

#[test]
fn http_proxy_maps_upstream_failures_and_timeouts_to_502_504() {
    group("errors", "http-proxy-errors cases=12 bad_gateway=2 gateway_timeout=1 rejected=5");
}

#[test]
fn http_proxy_serves_h2c_clients_over_http1_upstreams() {
    group("h2", "http-proxy-h2 cases=13 requests=33 connects=6 reused=28");
}

#[test]
fn http_proxy_tls_front_end_negotiates_h2_and_http1_by_alpn() {
    let out = python("HTTP proxy TLS oracle", &[fixture("tls_oracle.py").as_os_str(), tls_proxy().path().as_os_str()], 120);
    assert_eq!(out.lines().last(), Some("http-proxy-tls cases=13 handshakes=5 h2=2 requests=33 failures=1"), "{out}");
}

#[test]
fn http_service_tls_serves_h2_and_http1_by_alpn_on_one_loop() {
    let exe = build_tls("tests/fixtures/extended/http2_server/tls_events.lani", "tls_events");
    let script = root().join("tests/fixtures/extended/http2_server/tls_oracle.py");
    let out = python("HTTP service TLS oracle", &[script.as_os_str(), exe.path().as_os_str()], 120);
    assert_eq!(out.lines().last(), Some("http-service-tls cases=8 handshakes=3 h2=1 requests=40"), "{out}");
}

// 100 h2c clients with 20 multiplexed requests each, then 100 HTTP/1.1
// keep-alive clients with 20 requests each, through the proxy; then the
// same two phases over TLS. Timings are printed; counters and bodies are
// checked.
#[test]
fn http_proxy_load_100_clients_plain_and_tls() {
    let out = python("HTTP proxy load test", &[fixture("load.py").as_os_str(), proxy().path().as_os_str()], 150);
    assert_eq!(out.lines().last(), Some("load-check clients=100 requests=20 proxied=4000 h2_requests=2000 errors=0"), "{out}");
    let tls = python(
        "HTTP proxy TLS load test",
        &[fixture("load.py").as_os_str(), tls_proxy().path().as_os_str(), std::ffi::OsStr::new("100"), std::ffi::OsStr::new("20"), std::ffi::OsStr::new("--tls")],
        150,
    );
    assert_eq!(tls.lines().last(), Some("load-check-tls clients=100 requests=20 proxied=4000 h2_requests=2000 errors=0"), "{tls}");
}
