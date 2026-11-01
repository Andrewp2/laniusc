#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    io::Write,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/bc.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("bc", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("bc: {error}"));
        let exe = common::TempArtifact::new("laniusc_bc", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

fn run(args: &[&str], input: &str) -> (i32, String, String) {
    let mut child = Command::new(executable().path())
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input.as_bytes()).unwrap();
    let output = child.wait_with_output().unwrap();
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8(output.stdout).unwrap(),
        String::from_utf8(output.stderr).unwrap(),
    )
}

#[test]
fn python_integer_oracle_across_karatsuba_threshold_radices_and_errors() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = Command::new("python3")
        .arg("-I")
        .arg(root.join("tests/oracles/bc_oracle.py"))
        .arg(executable().path())
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "{stdout}{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(stdout.contains("checked 9526 values and 103 diagnostics across 6 radices"), "{stdout}");
}

#[test]
fn precedence_comments_quit_and_diagnostics() {
    let (status, out, err) = run(
        &[],
        "1+2*3\n-2^2\n2^3^2\n7/-2\n-7%3\n# note\n\n1/0\nmodpow(-3,5,-7)\n12&10|1\nquit\n5\n",
    );
    assert_eq!(status, 1);
    assert_eq!(out, "7\n-4\n512\n-3\n-1\n-5\n9\n");
    assert_eq!(err, "bc: division-by-zero line=8 byte=1\n");
    let (status, out, err) = run(&["--ibase", "16", "--obase", "2"], "FF+1\n");
    assert_eq!((status, out.as_str(), err.as_str()), (0, "100000000\n", ""));
    let (status, _, err) = run(&["--obase", "37"], "1\n");
    assert_eq!(status, 2);
    assert!(err.starts_with("bc: invalid-arguments"), "{err}");
}
