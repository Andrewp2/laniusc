#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{
    io::Write,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    time::Duration,
};

fn executable(entry: &str, name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(entry);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let label = name.to_string();
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{label}: {e}"));
    let exe = common::TempArtifact::new("laniusc_unicode_uconv", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn uconv(exe: &common::TempArtifact, args: &[&str], input: &[u8]) -> std::process::Output {
    let mut child = Command::new(exe.path())
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn uconv_transforms_checks_and_rejects() {
    let exe = executable("sample_programs/library/uconv.lani", "uconv");
    let input = "A\u{30a} e\u{301}\nplain ascii\n\u{fb03} \u{212b}\n".as_bytes();
    let cases: [(&str, &str); 8] = [
        ("any-nfc", "\u{c5} \u{e9}\nplain ascii\n\u{fb03} \u{c5}\n"),
        ("any-nfd", "A\u{30a} e\u{301}\nplain ascii\n\u{fb03} A\u{30a}\n"),
        ("any-nfkc", "\u{c5} \u{e9}\nplain ascii\nffi \u{c5}\n"),
        ("any-nfkd", "A\u{30a} e\u{301}\nplain ascii\nffi A\u{30a}\n"),
        ("any-lower", "a\u{30a} e\u{301}\nplain ascii\n\u{fb03} \u{e5}\n"),
        ("any-upper", "A\u{30a} E\u{301}\nPLAIN ASCII\nFFI \u{212b}\n"),
        ("any-title", "A\u{30a} E\u{301}\nPlain Ascii\nFfi \u{212b}\n"),
        ("any-casefold", "a\u{30a} e\u{301}\nplain ascii\nffi \u{e5}\n"),
    ];
    for (name, want) in cases {
        let out = uconv(&exe, &["-x", name], input);
        assert_eq!(out.status.code(), Some(0), "{name}: {out:?}");
        assert_eq!(String::from_utf8(out.stdout).unwrap(), want, "{name}");
    }
    let out = uconv(&exe, &["--check"], input);
    assert_eq!(out.status.code(), Some(1));
    assert!(out.stdout.is_empty());
    assert_eq!(out.stderr, b"uconv: not-normalized line=1\n");
    assert_eq!(uconv(&exe, &["--check", "-x", "any-nfd"], b"ascii\n").status.code(), Some(0));
    let out = uconv(&exe, &[], b"ok\n\xff");
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(out.stderr, b"uconv: invalid-utf8 byte=3\n");
    assert_eq!(uconv(&exe, &["-x", "bogus"], b"").status.code(), Some(2));
    assert_eq!(uconv(&exe, &["--check", "-x", "any-lower"], b"").status.code(), Some(2));
    assert_eq!(uconv(&exe, &["--max-input-bytes", "2"], b"abc").status.code(), Some(2));
    assert_eq!(uconv(&exe, &[], b"").stdout, b"");
}

#[test]
fn python_unicodedata_oracle_agrees_on_every_code_point_and_generated_strings() {
    let oracle = executable("sample_programs/library/unicode_oracle.lani", "unicode-oracle");
    let tool = executable("sample_programs/library/uconv.lani", "uconv");
    let output = common::process_output_with_timeout(
        "python oracle",
        Command::new("python3")
            .args(["-I", "tools/unicode17/python_oracle.py"])
            .arg(oracle.path())
            .args(["--strings", "5000", "--uconv"])
            .arg(tool.path())
            .current_dir(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(280),
    );
    let report = String::from_utf8_lossy(&output.stdout);
    assert_eq!(output.status.code(), Some(0), "{report}\n{}", String::from_utf8_lossy(&output.stderr));
    assert!(report.contains("defects: 0"), "{report}");
    for generator in ["generate_properties.py", "generate_quick_check.py", "generate_normalization.py", "generate_case_fast.py"] {
        let check = common::short_process_output_with_timeout(
            generator,
            Command::new("python3")
                .arg("-I")
                .arg(format!("tools/unicode17/{generator}"))
                .arg("--check")
                .current_dir(env!("CARGO_MANIFEST_DIR")),
        );
        assert!(check.status.success(), "{generator}: {check:?}");
    }
}
