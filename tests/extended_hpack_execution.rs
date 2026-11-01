#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn driver() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let path = "tests/fixtures/extended/hpack/driver.lani";
        let entry = root().join(path);
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(path, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("{path}: {e}"));
        let exe = common::TempArtifact::new("laniusc_hpack", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

// The oracle compares against RFC 7541 Appendix C and, both ways, against
// libnghttp2's HPACK deflater and inflater (through ctypes).
fn group(name: &str, expected: &str) {
    let out = common::process_output_with_timeout(
        "HPACK oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root().join("tests/fixtures/extended/hpack/oracle.py"))
            .arg(name)
            .arg(driver().path()),
        Duration::from_secs(90),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim(),
        format!("hpack-{name} {expected}")
    );
}

#[test]
fn hpack_matches_rfc_7541_appendix_c_examples() {
    group("rfc", "cases=8 blocks=39");
}

#[test]
fn hpack_agrees_with_nghttp2_in_both_directions() {
    group("nghttp2", "cases=3 blocks=2512");
}

#[test]
fn hpack_rejects_malformed_blocks_like_nghttp2() {
    group("malformed", "cases=17 blocks=624");
}
