//! One composed TLS1.3 authentication flight, independently checked at every boundary.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/extended/tls_auth_integration/flight.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("composed TLS authentication flight", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("TLS authentication integration: {error}"));
        let exe = common::TempArtifact::new("laniusc_tls_auth", "flight", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn hex(text: &str) -> Vec<u8> {
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
fn certificate() -> &'static Vec<u8> {
    static CERT: OnceLock<Vec<u8>> = OnceLock::new();
    CERT.get_or_init(|| {
        // The same public RFC8032 seed used by the independent DER anchor.
        // OpenSSL constructs and signs the complete real X.509 certificate.
        let mut private = hex("302e020100300506032b657004220420");
        private.extend(hex(
            "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
        ));
        let key = common::TempArtifact::new("laniusc_tls_auth", "test_key", None);
        key.write_bytes(private);
        let config = common::TempArtifact::new("laniusc_tls_auth", "openssl_config", None);
        config.write_bytes(
            b"[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=DER anchor\nO=Borrowed reader\n",
        );
        let output = common::process_output_with_timeout(
            "OpenSSL fixed-key test certificate",
            Command::new("openssl")
                .args(["req", "-new", "-x509", "-keyform", "DER", "-key"])
                .arg(key.path())
                .arg("-config")
                .arg(config.path())
                .args([
                    "-subj",
                    "/CN=DER anchor/O=Borrowed reader",
                    "-days",
                    "1",
                    "-set_serial",
                    "128",
                    "-addext",
                    "basicConstraints=critical,CA:TRUE",
                    "-outform",
                    "DER",
                ]),
            Duration::from_secs(10),
        );
        assert!(
            output.status.success(),
            "OpenSSL certificate: {:?}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(output.stdout.len() > 200 && output.stdout.len() < 3000);
        output.stdout
    })
}
const PEER: &str = include_str!("fixtures/extended/tls_auth_integration/peer.py");
const FIELDS: [&str; 40] = [
    "client X25519 public",
    "server X25519 public",
    "client shared secret",
    "server shared secret",
    "ClientHello",
    "CH hash",
    "ServerHello",
    "CH+SH hash",
    "early secret",
    "handshake secret",
    "client HS traffic",
    "server HS traffic",
    "master secret",
    "EncryptedExtensions",
    "through EE hash",
    "Certificate",
    "through Certificate hash",
    "DER SPKI public key",
    "CV signed input",
    "CertificateVerify",
    "through CV hash",
    "server Finished",
    "through server Finished hash",
    "client app traffic",
    "server app traffic",
    "exporter master",
    "exported48",
    "client Finished",
    "through client Finished hash",
    "resumption master",
    "ticket PSK",
    "NewSessionTicket",
    "server HS record",
    "client HS record",
    "server app record",
    "client app record",
    "ticket record",
    "accepted transcript hash",
    "publication buffer",
    "receiver status/count/sequences/poison/publication length",
];
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdoutlen={}, prefix={:?}, stderr={:?}",
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(32)],
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "stderr={:?}",
        String::from_utf8_lossy(&output.stderr)
    );
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    assert!(*at + 8 <= bytes.len(), "truncated response at{at}");
    let result = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    result
}
fn compare(variants: &[u64]) {
    let cert = certificate();
    let mut input = (cert.len() as u64).to_le_bytes().to_vec();
    input.extend(cert);
    input.extend(((variants.len() * 2) as u64).to_le_bytes());
    let mut cases = Vec::new();
    for &variant in variants {
        for layout in [0u64, 1] {
            input.extend(layout.to_le_bytes());
            input.extend(variant.to_le_bytes());
            cases.push((layout, variant));
        }
    }
    let source = common::TempArtifact::new("laniusc_tls_auth", "input", None);
    source.write_bytes(input);
    let peer = common::process_output_with_timeout(
        "independent TLS authentication peer",
        Command::new("python3")
            .args(["-c", PEER])
            .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())),
        Duration::from_secs(15),
    );
    checked(&peer);
    let trace = common::TempArtifact::new("laniusc_tls_auth", "memory", None);
    let native = common::process_output_with_timeout(
        "composed native TLS authentication flight",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&native);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "composed flight must allocate no memory: {events}"
    );
    let mut actual_at = 0;
    let mut expected_at = 0;
    for (layout, variant) in cases.iter().copied() {
        for expected in [layout, variant] {
            assert_eq!(word(&native.stdout, &mut actual_at), expected);
            assert_eq!(word(&peer.stdout, &mut expected_at), expected);
        }
        let stride = word(&native.stdout, &mut actual_at) as i64;
        if layout == 0 {
            assert!(stride < 0, "native strided arena");
        } else {
            assert_eq!(stride, 1, "packed arena");
        }
        for (index, name) in FIELDS.iter().enumerate() {
            let id = (index + 1) as u64;
            assert_eq!(word(&native.stdout, &mut actual_at), id);
            assert_eq!(word(&peer.stdout, &mut expected_at), id);
            let actual_length = word(&native.stdout, &mut actual_at) as usize;
            let expected_length = word(&peer.stdout, &mut expected_at) as usize;
            assert_eq!(
                actual_length, expected_length,
                "variant{variant}/layout{layout}/{name}"
            );
            assert_eq!(
                &native.stdout[actual_at..actual_at + actual_length],
                &peer.stdout[expected_at..expected_at + expected_length],
                "variant{variant}/layout{layout}/{name}"
            );
            actual_at += actual_length;
            expected_at += expected_length;
        }
    }
    assert_eq!(actual_at, native.stdout.len());
    assert_eq!(expected_at, peer.stdout.len());
    eprintln!(
        "composed TLS authentication cases={}, byte fields={}",
        cases.len(),
        cases.len() * 40
    );
}
#[test]
fn composed_tls13_authentication_flight_matches_independent_peer() {
    compare(&[0]);
}
#[test]
fn tampered_authentication_checkpoints_reject_before_publication() {
    compare(&[1, 2, 3, 4, 5, 6, 7, 8]);
}
