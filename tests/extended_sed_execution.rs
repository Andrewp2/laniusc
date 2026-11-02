#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
// text_sed (ext::sed) on cases whose expected bytes come from GNU sed 4.9.
// The generated comparison is tests/fixtures/extended/sed_oracle/oracle.py.
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/text_sed.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("text-sed", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("text-sed: {error}"));
        let exe = common::TempArtifact::new("laniusc_text_sed", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("text-sed", command, Duration::from_secs(30))
}
fn invoke(args: &[&str], input: &[u8]) -> Output {
    let data = common::TempArtifact::new("laniusc_text_sed", "input", None);
    data.write_bytes(input);
    run(Command::new(executable().path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())))
}
fn edited(args: &[&str], input: &[u8], status: i32, expected: &[u8]) {
    let output = invoke(args, input);
    assert_eq!(output.status.code(), Some(status), "{args:?} {output:?}");
    assert_eq!(output.stdout, expected, "{args:?} {output:?}");
    assert!(output.stderr.is_empty(), "{args:?} {output:?}");
}

#[test]
fn text_sed_matches_gnu_sed_on_pinned_scripts() {
    edited(&["s/o/0/g"], b"hello world\nfoo bar\n", 0, b"hell0 w0rld\nf00 bar\n");
    edited(&["s/b*/X/g"], b"abc\n", 0, b"XaXcX\n");
    edited(&["-n", "2,3p;$="], b"a\nb\nc\nd\n", 0, b"b\nc\n4\n");
    edited(&["-E", "s/(a)|b/[\\1]/g"], b"ab\n", 0, b"[a][]\n");
    edited(&["s/a/\\n/"], b"ab\n", 0, b"\nb\n");
    edited(&["p"], b"a", 0, b"a\na");
    edited(&["q"], b"a", 0, b"a\n");
    edited(&["2q7"], b"a\nb\nc\n", 7, b"a\nb\n");
    edited(
        &["n;3,5s/^/x/"],
        b"1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n",
        0,
        b"1\n2\n3\nx4\n5\n6\n7\n8\n9\n10\n",
    );
    edited(&["y/aé日/日xé/"], "aé日\n".as_bytes(), 0, "日xé\n".as_bytes());
    edited(
        &["-n", "-e", "/t/{s/\\(.\\)\\(.*\\)/\\2\\1/p;}"],
        b"one\ntwo\nthree\n",
        0,
        b"wot\nhreet\n",
    );
    edited(&["s,[[:digit:],],X,g"], b"a1,b\n", 0, b"aXXb\n");
    for script in ["k", "s/a/b", "s/\\(a\\)/\\2/", "{p", "p}", "-E s/a{2,1}/y/"] {
        let args: Vec<&str> = script.split(' ').collect();
        let output = invoke(&args, b"a\n");
        assert_eq!(output.status.code(), Some(1), "{script} {output:?}");
        assert!(output.stdout.is_empty(), "{script} {output:?}");
        assert!(output.stderr.starts_with(b"text-sed: "), "{script} {output:?}");
    }
}

#[test]
fn text_sed_edits_in_place_and_reports_unreadable_files() {
    let file = common::TempArtifact::new("laniusc_text_sed", "edit", None);
    file.write_bytes(b"a\nb\n");
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o640)).unwrap();
    let path = file.path().to_str().unwrap();
    let output = run(Command::new(executable().path()).args(["-i", "s/a/X/;$=", path]));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert_eq!(std::fs::read(file.path()).unwrap(), b"X\nb\n2\n");
    let mode = std::fs::metadata(file.path()).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o640);
    let missing = format!("{path}.missing");
    let output = run(Command::new(executable().path()).args(["$p", path, &missing]));
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    assert_eq!(output.stdout, b"X\nb\n2\n2\n", "{output:?}");
    assert!(String::from_utf8_lossy(&output.stderr).contains("can't read"), "{output:?}");
    // q never reaches the second operand, so it is not opened.
    let output = run(Command::new(executable().path()).args(["q", path, &missing]));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, b"X\n", "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
