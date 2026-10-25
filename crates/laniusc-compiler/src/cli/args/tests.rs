use std::path::{Path, PathBuf};

use super::{Command, CompileRequest, parse_args};
use crate::cli::common::CliError;

fn compile_request(args: &[&str]) -> CompileRequest {
    match parse_args(args.iter().map(|arg| arg.to_string())).expect("valid compile arguments") {
        Command::Compile(request) => request,
        _ => panic!("expected compile request"),
    }
}

fn assert_diagnostic(args: &[&str], code: &str) {
    let error = match parse_args(args.iter().map(|arg| arg.to_string())) {
        Ok(_) => panic!("arguments should fail: {args:?}"),
        Err(error) => error,
    };
    let CliError::Diagnostic(diagnostic) = error else {
        panic!("CLI validation should return a structured diagnostic");
    };
    assert_eq!(diagnostic.code, code, "arguments: {args:?}");
}

#[test]
fn native_link_flag_selects_profile_without_libraries() {
    let request = compile_request(&["--native-link", "main.lani"]);
    let options = request.native_link.expect("native profile selected");
    assert!(options.libraries.is_empty());
    assert!(options.objects.is_empty());
    assert!(options.library_paths.is_empty());
    assert!(options.linker.is_none());
    assert!(!request.uses_source_pack);
    assert!(compile_request(&["main.lani"]).native_link.is_none());
}

#[test]
fn every_native_option_selects_profile_in_split_and_equals_forms() {
    let source_file = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/lib.rs");
    let source_file = source_file.to_str().expect("UTF-8 source path");
    for (flag, value) in [
        ("--native-library", "crypto"),
        ("--native-object", source_file),
        ("--native-library-path", env!("CARGO_MANIFEST_DIR")),
        ("--native-linker", "cc"),
    ] {
        for args in [
            vec!["main.lani".to_string(), flag.to_string(), value.to_string()],
            vec!["main.lani".to_string(), format!("{flag}={value}")],
        ] {
            let args = args.iter().map(String::as_str).collect::<Vec<_>>();
            let request = compile_request(&args);
            assert!(request.native_link.is_some(), "selector: {flag}");
            assert!(!request.uses_source_pack);
        }
    }
}

#[test]
fn native_link_inputs_preserve_order_and_explicit_flag_preserves_options() {
    let source_file = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/lib.rs");
    let source_file_str = source_file.to_str().expect("UTF-8 source path");
    let request = compile_request(&[
        "main.lani",
        "--native-library=ssl",
        "--native-object",
        source_file_str,
        "--native-link",
        "--native-library",
        "crypto",
        "--native-object",
        source_file_str,
        "--native-library-path",
        env!("CARGO_MANIFEST_DIR"),
        "--native-library-path",
        env!("CARGO_MANIFEST_DIR"),
        "--native-linker=cc",
    ]);
    let options = request.native_link.expect("native profile selected");
    assert_eq!(options.libraries, ["ssl", "crypto"]);
    let canonical_source_file = source_file.canonicalize().unwrap();
    assert_eq!(
        options.objects,
        [canonical_source_file.clone(), canonical_source_file]
    );
    assert_eq!(options.library_paths.len(), 2);
    assert!(options.library_paths.iter().all(|path| path.is_absolute()));
    assert_eq!(options.linker, Some(PathBuf::from("cc")));
}

#[test]
fn native_paths_are_resolved_and_file_directory_mismatches_rejected() {
    let request = compile_request(&[
        "main.lani",
        "--native-object=./Cargo.toml",
        "--native-library-path=.",
        "--native-linker=./Cargo.toml",
    ]);
    let options = request.native_link.expect("native profile selected");
    let file = Path::new("Cargo.toml").canonicalize().unwrap();
    assert_eq!(options.objects, [file.clone()]);
    assert_eq!(
        options.library_paths,
        [Path::new(".").canonicalize().unwrap()]
    );
    assert_eq!(options.linker, Some(file));
    assert_diagnostic(&["main.lani", "--native-object=."], "LNC0040");
    assert_diagnostic(
        &["main.lani", "--native-library-path=Cargo.toml"],
        "LNC0040",
    );
}

#[test]
fn native_link_accepts_source_roots_and_linux_target() {
    let request = compile_request(&[
        "main.lani",
        "--native-link",
        "--source-root",
        env!("CARGO_MANIFEST_DIR"),
        "--stdlib-root",
        env!("CARGO_MANIFEST_DIR"),
        "--target=x86_64-unknown-linux-gnu",
    ]);
    assert!(request.native_link.is_some());
    assert_eq!(request.source_roots.len(), 1);
    assert!(request.stdlib_root.is_some());
    assert!(!request.uses_source_pack);
}

#[test]
fn native_link_accepts_package_input_selectors() {
    for flag in ["--package-manifest", "--package-lockfile"] {
        let request = compile_request(&[flag, "package.json", "--native-library=crypto"]);
        assert!(request.native_link.is_some());
        assert!(!request.uses_source_pack);
        assert!(request.inputs.is_empty());
    }
}

#[test]
fn native_link_rejects_check_and_wasm() {
    for args in [
        vec!["check", "main.lani", "--native-link"],
        vec![
            "check",
            "--package-manifest=p.json",
            "--native-library=crypto",
        ],
        vec!["main.lani", "--emit=wasm", "--native-link"],
        vec![
            "main.lani",
            "--emit=wasm",
            "--target=wasm32-unknown-unknown",
            "--native-linker=cc",
        ],
    ] {
        assert_diagnostic(&args, "LNC0032");
    }
    assert_diagnostic(
        &[
            "main.lani",
            "--target=wasm32-unknown-unknown",
            "--native-link",
        ],
        "LNC0018",
    );
}

#[test]
fn native_link_requires_one_entry_or_package_input() {
    assert_diagnostic(&["--native-link"], "LNC0026");
    assert_diagnostic(&["--native-linker=cc"], "LNC0026");
    assert_diagnostic(&["one.lani", "two.lani", "--native-link"], "LNC0031");
    assert_diagnostic(
        &["main.lani", "--package-manifest=p.json", "--native-link"],
        "LNC0032",
    );
}

#[test]
fn native_link_rejects_every_explicit_source_pack_option() {
    for option in [
        "--source-pack-descriptors",
        "--emit-contract",
        "--source-pack-manifest=pack.json",
        "--source-pack-library-manifest=library.jsonl",
        "--source-pack-metadata-only",
        "--source-pack-prepare-only",
        "--source-pack-build-from-metadata",
        "--source-pack-build-prepare-only",
        "--source-pack-metadata-max-libraries=64",
        "--source-pack-metadata-max-source-files=64",
        "--source-pack-build-max-items=64",
        "--source-pack-artifact-root=artifacts",
        "--source-pack-max-items=64",
        "--source-pack-max-ready-items=64",
        "--stdlib=stdlib.lani",
    ] {
        assert_diagnostic(&["main.lani", "--native-link", option], "LNC0032");
        assert_diagnostic(&[option, "--native-link", "main.lani"], "LNC0032");
    }
}

#[test]
fn native_value_options_require_nonempty_values() {
    for flag in [
        "--native-library",
        "--native-object",
        "--native-library-path",
        "--native-linker",
    ] {
        assert_diagnostic(&["main.lani", flag], "LNC0023");
        assert_diagnostic(&["main.lani", &format!("{flag}=")], "LNC0023");
        assert_diagnostic(&["main.lani", flag, "--emit", "x86_64"], "LNC0023");
    }
    assert_diagnostic(&["main.lani", "--native-link=true"], "LNC0020");
}

#[test]
fn native_link_help_skips_compile_mode_validation() {
    assert!(matches!(
        parse_args(["--native-link", "--emit=wasm", "--help"].map(String::from)),
        Ok(Command::Help)
    ));
}
