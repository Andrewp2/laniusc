mod common;

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use laniusc::compiler::{
    PACKAGE_LOCKFILE_LANGUAGE_EDITION,
    PACKAGE_LOCKFILE_VERSION,
    PackageLockfile,
    PackageManifest,
};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_package_manifest_compiles_entry_through_source_roots() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "compile", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");

    fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn add_one(value: i32) -> i32 {
    return value + 1;
}
"#,
    )
    .expect("write helper module");
    fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::add_one(-1);
}
"#,
    )
    .expect("write entry module");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "app",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");
    let output_wasm = root.join("out.wasm");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("wasm")
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output =
        common::command_output_with_timeout("laniusc --package-manifest compile", &mut command);
    common::assert_command_success("laniusc --package-manifest compile", &output);

    let wasm = fs::read(&output_wasm).expect("read emitted WASM");
    assert!(
        wasm.starts_with(&[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]),
        "package manifest compile should emit a WASM module"
    );

    fs::remove_dir_all(&root).expect("remove package manifest compile root");
}

#[test]
fn cli_package_lockfile_compiles_entry_through_resolved_source_roots() {
    let root = common::temp_artifact_path("laniusc_cli_package_lockfile", "compile", None);
    let (_, _, lockfile) = write_package_lockfile_fixture(&root);
    let output_wasm = root.join("out.wasm");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("wasm")
        .arg("--package-lockfile")
        .arg(&lockfile)
        .arg("-o")
        .arg(&output_wasm);
    let output =
        common::command_output_with_timeout("laniusc --package-lockfile compile", &mut command);
    common::assert_command_success("laniusc --package-lockfile compile", &output);

    let wasm = fs::read(&output_wasm).expect("read emitted WASM");
    assert!(
        wasm.starts_with(&[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]),
        "package lockfile compile should emit a WASM module"
    );

    fs::remove_dir_all(&root).expect("remove package lockfile compile root");
}

#[test]
fn cli_package_lock_generates_lockfile_that_existing_compile_path_uses() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "generate", None);
    let (_, _, manifest) = write_package_manifest_fixture(&root);
    let lockfile = root.join("lanius.lock.json");

    let mut lock_command = Command::new(laniusc_bin());
    lock_command
        .arg("package")
        .arg("lock")
        .arg("--manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&lockfile);
    let output = common::command_output_with_timeout("laniusc package lock", &mut lock_command);
    common::assert_command_success("laniusc package lock", &output);
    assert!(
        lockfile.is_file(),
        "package lock command should create {}",
        lockfile.display()
    );

    let generated =
        PackageLockfile::load_json_file(&lockfile).expect("generated lockfile should validate");
    assert_eq!(generated.version, PACKAGE_LOCKFILE_VERSION);
    assert_eq!(
        generated.language_edition,
        PACKAGE_LOCKFILE_LANGUAGE_EDITION
    );
    assert_eq!(generated.compiler_version, env!("CARGO_PKG_VERSION"));
    assert_eq!(generated.package, "metadata-name-not-module-identity");
    assert!(generated.roots.iter().all(|root| root.is_absolute()));
    assert!(generated.entry.is_absolute());

    let output_wasm = root.join("out.wasm");
    let mut compile_command = Command::new(laniusc_bin());
    compile_command
        .arg("--emit")
        .arg("wasm")
        .arg("--package-lockfile")
        .arg(&lockfile)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-lockfile generated lockfile",
        &mut compile_command,
    );
    common::assert_command_success("laniusc --package-lockfile generated lockfile", &output);

    let wasm = fs::read(&output_wasm).expect("read emitted WASM");
    assert!(
        wasm.starts_with(&[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]),
        "generated package lockfile should compile through the existing lockfile path"
    );

    fs::remove_dir_all(&root).expect("remove generated package lock root");
}

#[test]
fn cli_package_manifest_and_lockfile_use_stdlib_as_fallback() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "stdlib_fallback", None);
    let app_root = root.join("src/app");
    let user_core_root = root.join("src/core");
    let stdlib_core_root = root.join("stdlib/core");
    fs::create_dir_all(&app_root).expect("create package app root");
    fs::create_dir_all(&user_core_root).expect("create package core root");
    fs::create_dir_all(&stdlib_core_root).expect("create stdlib core root");

    fs::write(
        user_core_root.join("shadow.lani"),
        r#"
module core::shadow;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write package module that shadows stdlib fallback");
    fs::write(
        stdlib_core_root.join("shadow.lani"),
        r#"
module core::shadow;

fn broken(
"#,
    )
    .expect("write invalid stdlib fallback module");
    fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import core::shadow;

fn main() {
    return core::shadow::VALUE;
}
"#,
    )
    .expect("write package entry");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "stdlib-fallback",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    let mut manifest_command = Command::new(laniusc_bin());
    manifest_command
        .arg("check")
        .arg("--package-manifest")
        .arg(&manifest);
    let output = common::command_output_with_timeout(
        "laniusc check --package-manifest stdlib fallback",
        &mut manifest_command,
    );
    common::assert_command_success("laniusc check --package-manifest stdlib fallback", &output);

    let lockfile = root.join("lanius.lock.json");
    let mut lock_command = Command::new(laniusc_bin());
    lock_command
        .arg("package")
        .arg("lock")
        .arg("--manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&lockfile);
    let output = common::command_output_with_timeout(
        "laniusc package lock stdlib fallback",
        &mut lock_command,
    );
    common::assert_command_success("laniusc package lock stdlib fallback", &output);

    let mut lockfile_command = Command::new(laniusc_bin());
    lockfile_command
        .arg("check")
        .arg("--package-lockfile")
        .arg(&lockfile);
    let output = common::command_output_with_timeout(
        "laniusc check --package-lockfile stdlib fallback",
        &mut lockfile_command,
    );
    common::assert_command_success("laniusc check --package-lockfile stdlib fallback", &output);

    fs::remove_dir_all(&root).expect("remove package stdlib fallback root");
}

#[test]
fn cli_package_lock_rejects_missing_or_bad_arguments() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "bad_args", None);
    let (_, _, manifest) = write_package_manifest_fixture(&root);
    let lockfile = root.join("lanius.lock.json");

    let stderr = assert_package_lock_failure(|command| {
        command.arg("-o").arg(&lockfile);
    });
    assert!(stderr.contains("package lock requires --manifest path"));
    assert!(
        !lockfile.exists(),
        "missing manifest should not create lockfile"
    );

    let stderr = assert_package_lock_failure(|command| {
        command.arg("--manifest").arg(&manifest);
    });
    assert!(stderr.contains("package lock requires -o/--out path"));

    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&lockfile)
            .arg(root.join("src/app/main.lani"));
    });
    assert!(stderr.contains("package lock does not accept positional input file"));
    assert!(
        !lockfile.exists(),
        "bad package lock args should not create lockfile"
    );

    fs::remove_dir_all(&root).expect("remove package lock bad-args root");
}

#[test]
fn cli_package_lock_refuses_to_write_package_source_file() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "source_output", None);
    let (src_root, _, manifest) = write_package_manifest_fixture(&root);
    let source_output = src_root.join("app/unused.lani");

    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&source_output);
    });
    assert!(stderr.contains("lockfile output path"));
    assert!(stderr.contains("package source file"));
    assert!(
        !source_output.exists(),
        "failed package lock should not create source file {}",
        source_output.display()
    );

    fs::write(
        &source_output,
        "module app::unused;\npub const VALUE: i32 = 99;\n",
    )
    .expect("write package source output candidate");
    let original_source =
        fs::read_to_string(&source_output).expect("read package source before lock");

    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&source_output);
    });
    assert!(stderr.contains("lockfile output path"));
    assert!(stderr.contains("package source file"));
    assert_eq!(
        fs::read_to_string(&source_output).expect("read package source after failed lock"),
        original_source,
        "failed package lock should not overwrite source file {}",
        source_output.display()
    );

    fs::remove_dir_all(&root).expect("remove package lock source-output root");
}

#[test]
fn cli_package_lock_refuses_to_overwrite_manifest_file() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "manifest_output", None);
    let (_, _, manifest) = write_package_manifest_fixture(&root);
    let original_manifest =
        fs::read_to_string(&manifest).expect("read package manifest before package lock");

    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&manifest);
    });
    assert!(stderr.contains("package lock output path"));
    assert!(stderr.contains("would overwrite package manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert_eq!(
        fs::read_to_string(&manifest).expect("read package manifest after failed package lock"),
        original_manifest,
        "failed package lock should not overwrite manifest {}",
        manifest.display()
    );

    fs::remove_dir_all(&root).expect("remove package lock manifest-output root");
}

#[test]
fn cli_package_lock_creates_missing_output_directories() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "nested_output", None);
    let (_, _, manifest) = write_package_manifest_fixture(&root);
    let lockfile = root
        .join("target")
        .join("package")
        .join("generated")
        .join("lanius.lock.json");
    assert!(
        !lockfile
            .parent()
            .expect("nested lockfile should have a parent")
            .exists(),
        "test fixture should start without the nested output directory"
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("package")
        .arg("lock")
        .arg("--manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&lockfile);
    let output =
        common::command_output_with_timeout("laniusc package lock nested output", &mut command);
    common::assert_command_success("laniusc package lock nested output", &output);
    assert!(
        lockfile.is_file(),
        "package lock command should create {}",
        lockfile.display()
    );
    PackageLockfile::load_json_file(&lockfile).expect("nested generated lockfile should validate");

    fs::remove_dir_all(&root).expect("remove package lock nested-output root");
}

#[test]
fn cli_package_lock_refuses_manifest_overwrite_through_missing_parent_path() {
    let root =
        common::temp_artifact_path("laniusc_cli_package_lock", "manifest_output_alias", None);
    let (_, _, manifest) = write_package_manifest_fixture(&root);
    let original_manifest =
        fs::read_to_string(&manifest).expect("read package manifest before package lock");
    let missing_parent = root.join("missing-output-parent");
    let manifest_alias = missing_parent.join("..").join("lanius.package.json");

    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&manifest_alias);
    });
    assert!(stderr.contains("package lock output path"));
    assert!(stderr.contains("would overwrite package manifest"));
    assert_eq!(
        fs::read_to_string(&manifest).expect("read package manifest after failed package lock"),
        original_manifest,
        "failed package lock should not overwrite manifest {}",
        manifest.display()
    );
    assert!(
        !missing_parent.exists(),
        "failed package lock should not create {}",
        missing_parent.display()
    );

    fs::remove_dir_all(&root).expect("remove package lock manifest-output-alias root");
}

#[test]
fn cli_package_manifest_and_lock_report_overlapping_stdlib_root() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "stdlib_overlap", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create overlapping package app root");
    fs::write(
        app_root.join("main.lani"),
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "overlap",
  "roots": ["src"],
  "stdlib_root": "src/app",
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write overlapping package manifest");

    let lockfile = root.join("lanius.lock.json");
    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&lockfile);
    });
    assert!(stderr.contains("package lock --manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("stdlib root"));
    assert!(stderr.contains("overlaps source root"));
    assert!(
        !lockfile.exists(),
        "invalid package manifest should not create a lockfile"
    );

    let output_wasm = root.join("out.wasm");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest overlapping stdlib root",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "overlapping package manifest should fail before compile\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("stdlib root"));
    assert!(stderr.contains("overlaps source root"));
    assert!(
        !output_wasm.exists(),
        "invalid package manifest should not emit {}",
        output_wasm.display()
    );

    fs::remove_dir_all(&root).expect("remove overlapping package manifest root");
}

#[test]
fn cli_package_manifest_and_lock_reject_non_lani_entry_path() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "entry_extension", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    fs::write(
        app_root.join("main.txt"),
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write package entry with ambiguous source extension");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "entry-extension",
  "roots": ["src"],
  "entry": "src/app/main.txt"
}"#,
    )
    .expect("write package manifest");

    let lockfile = root.join("lanius.lock.json");
    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&lockfile);
    });
    assert!(stderr.contains("package lock --manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("entry"));
    assert!(stderr.contains(".lani source file extension"));
    assert!(
        !lockfile.exists(),
        "invalid package manifest should not create a lockfile"
    );

    let output_wasm = root.join("out.wasm");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest non-lani entry",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package manifest with non-.lani entry should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("entry"));
    assert!(stderr.contains(".lani source file extension"));
    assert!(
        !output_wasm.exists(),
        "invalid package manifest should not emit {}",
        output_wasm.display()
    );

    fs::remove_dir_all(&root).expect("remove package entry-extension root");
}

#[test]
fn cli_package_manifest_invalid_metadata_can_render_json_without_compiling_source() {
    let root = common::temp_artifact_path(
        "laniusc_cli_package_manifest",
        "metadata_json_diagnostic",
        None,
    );
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    fs::write(
        app_root.join("main.txt"),
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write package entry with invalid package metadata extension");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "metadata-json-diagnostic",
  "roots": ["src"],
  "entry": "src/app/main.txt"
}"#,
    )
    .expect("write package manifest");
    let output_wasm = root.join("out.wasm");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest invalid metadata JSON",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "invalid package metadata should fail before compile\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "invalid package metadata should not write target bytes on stdout"
    );
    assert!(
        !output_wasm.exists(),
        "invalid package metadata should not emit {}",
        output_wasm.display()
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON package metadata diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0037");
    assert_eq!(diagnostic["title"], "package metadata invalid");
    assert_eq!(diagnostic["category"], "package/import loading");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("package metadata diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--package-manifest")),
        "diagnostic notes should identify the package manifest selector\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains(&manifest.display().to_string())),
        "diagnostic notes should identify the package manifest path\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains(".lani source file extension")),
        "diagnostic notes should preserve the public manifest validation reason\nstderr:\n{stderr}"
    );

    fs::remove_dir_all(&root).expect("remove package metadata diagnostic root");
}

#[test]
fn cli_package_manifest_and_lock_reject_entry_paths_that_cannot_map_to_import_roots() {
    let root =
        common::temp_artifact_path("laniusc_cli_package_manifest", "entry_module_segment", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    fs::write(
        app_root.join("main-file.lani"),
        r#"
module app::main_file;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry with non-importable file segment");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "entry-module-segment",
  "roots": ["src"],
  "entry": "src/app/main-file.lani"
}"#,
    )
    .expect("write package manifest");

    let lockfile = root.join("lanius.lock.json");
    let stderr = assert_package_lock_failure(|command| {
        command
            .arg("--manifest")
            .arg(&manifest)
            .arg("-o")
            .arg(&lockfile);
    });
    assert!(stderr.contains("package lock --manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("package entry source-root relative path"));
    assert!(stderr.contains("invalid module path segment"));
    assert!(
        !lockfile.exists(),
        "invalid package manifest should not create a lockfile"
    );

    let output_wasm = root.join("out.wasm");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest invalid import-root entry",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package manifest with non-importable entry should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-manifest"));
    assert!(stderr.contains(&manifest.display().to_string()));
    assert!(stderr.contains("package entry source-root relative path"));
    assert!(stderr.contains("invalid module path segment"));
    assert!(
        !output_wasm.exists(),
        "invalid package manifest should not emit {}",
        output_wasm.display()
    );

    fs::remove_dir_all(&root).expect("remove package entry-module-segment root");
}

#[test]
fn cli_package_manifest_missing_import_json_keeps_package_context() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "missing_import", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    let entry = app_root.join("main.lani");
    fs::write(
        &entry,
        r#"
module app::main;

import app::missing;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry with missing import");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "missing-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");
    let output_wasm = root.join("out.wasm");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format")
        .arg("json")
        .arg("--package-manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&output_wasm);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest missing import JSON",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package manifest missing import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        !output_wasm.exists(),
        "failed package manifest compile should not emit {}",
        output_wasm.display()
    );

    let diagnostic: serde_json::Value =
        serde_json::from_slice(&output.stderr).expect("diagnostic stderr should be JSON");
    assert_eq!(diagnostic["code"], "LNC0001");
    assert_eq!(
        diagnostic["message"],
        "missing source-root module app::missing"
    );
    let entry_display = entry.display().to_string();
    assert_eq!(
        diagnostic["primary_label"]["path"].as_str(),
        Some(entry_display.as_str())
    );
    assert_eq!(
        diagnostic["primary_label"]["message"].as_str(),
        Some("imported here")
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("diagnostic notes should be an array");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.starts_with("searched ") && note.contains("app/missing.lani")
            })
        }),
        "missing-import diagnostic should keep searched source-root candidates: {notes:?}"
    );
    let manifest_display = manifest.display().to_string();
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("--package-manifest") && note.contains(manifest_display.as_str())
            })
        }),
        "missing-import diagnostic should name the package manifest context: {notes:?}"
    );

    fs::remove_dir_all(&root).expect("remove missing-import package manifest root");
}

#[test]
fn cli_package_manifest_string_import_json_stays_gpu_resolver_diagnostic() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "string_import", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    let entry = app_root.join("main.lani");
    fs::write(
        &entry,
        r#"
module app::main;

import "app/helper.lani";

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry with quoted import");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "quoted-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format")
        .arg("json")
        .arg("--package-manifest")
        .arg(&manifest);
    let output = common::command_output_with_timeout(
        "laniusc check --package-manifest quoted import JSON",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package manifest quoted import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let diagnostic: serde_json::Value =
        serde_json::from_slice(&output.stderr).expect("diagnostic stderr should be JSON");
    assert_eq!(diagnostic["code"], "LNC0011");
    assert_eq!(diagnostic["message"], "unsupported import form");
    let entry_display = entry.display().to_string();
    assert_eq!(
        diagnostic["primary_label"]["path"].as_str(),
        Some(entry_display.as_str())
    );
    assert_eq!(
        diagnostic["primary_label"]["message"].as_str(),
        Some("only module-path imports are supported here")
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("diagnostic notes should be an array");
    assert!(
        notes.iter().any(|note| {
            note.as_str()
                .is_some_and(|note| note.contains("quoted imports are not loaded"))
        }),
        "quoted-import diagnostic should explain the resolver boundary: {notes:?}"
    );
    let manifest_display = manifest.display().to_string();
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("--package-manifest") && note.contains(manifest_display.as_str())
            })
        }),
        "quoted-import diagnostic should name the package manifest context: {notes:?}"
    );

    fs::remove_dir_all(&root).expect("remove quoted-import package manifest root");
}

#[test]
fn cli_package_lock_rejects_quoted_import_json_before_writing_lockfile() {
    let root = common::temp_artifact_path("laniusc_cli_package_lock", "string_import", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    fs::create_dir_all(&app_root).expect("create package app source root");
    fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    let entry = app_root.join("main.lani");
    fs::write(
        &entry,
        r#"
module app::main;

import "app/helper.lani";

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry with quoted import");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "quoted-import-lockfile",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write quoted-import package manifest");
    let lockfile_path = root.join("lanius.lock.json");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("package")
        .arg("lock")
        .arg("--diagnostic-format")
        .arg("json")
        .arg("--manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&lockfile_path);
    let output = common::command_output_with_timeout(
        "laniusc package lock quoted import JSON",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package lock should reject quoted imports before writing a lockfile\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "package lock quoted-import diagnostics should not write stdout"
    );
    assert!(
        !lockfile_path.exists(),
        "failed package lock should not write {}",
        lockfile_path.display()
    );

    let diagnostic: serde_json::Value =
        serde_json::from_slice(&output.stderr).expect("diagnostic stderr should be JSON");
    assert_eq!(diagnostic["code"], "LNC0011");
    assert_eq!(diagnostic["message"], "unsupported import form");
    let entry_display = entry.display().to_string();
    assert_eq!(
        diagnostic["primary_label"]["path"].as_str(),
        Some(entry_display.as_str())
    );
    assert_eq!(
        diagnostic["primary_label"]["message"].as_str(),
        Some("package lockfiles require module-path imports here")
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("diagnostic notes should be an array");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("package lockfile import graphs record module-path imports")
            })
        }),
        "quoted-import diagnostic should explain the lockfile import-graph boundary: {notes:?}"
    );
    let manifest_display = manifest.display().to_string();
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("package lock --manifest") && note.contains(manifest_display.as_str())
            })
        }),
        "quoted-import diagnostic should name the package lock manifest context: {notes:?}"
    );

    fs::remove_dir_all(&root).expect("remove quoted-import package lockfile root");
}

#[test]
fn cli_package_lockfile_rejects_mixed_input_modes() {
    let root = common::temp_artifact_path("laniusc_cli_package_lockfile", "conflict", None);
    let (src_root, entry, lockfile) = write_package_lockfile_fixture(&root);

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "app",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    let stdlib_root = root.join("stdlib");
    fs::create_dir_all(&stdlib_root).expect("create stdlib root");
    let explicit_stdlib = root.join("explicit-stdlib.lani");
    fs::write(&explicit_stdlib, "module core::stub;\n").expect("write explicit stdlib source");

    let stderr = assert_lockfile_conflict(&lockfile, &root.join("manifest.wasm"), |command| {
        command.arg("--package-manifest").arg(&manifest);
    });
    assert!(stderr.contains("--package-lockfile describes the resolved entry"));
    assert!(stderr.contains("--package-manifest"));

    let stderr = assert_lockfile_conflict(&lockfile, &root.join("positional.wasm"), |command| {
        command.arg(&entry);
    });
    assert!(stderr.contains("positional input files"));

    let stderr = assert_lockfile_conflict(&lockfile, &root.join("source-root.wasm"), |command| {
        command.arg("--source-root").arg(&src_root);
    });
    assert!(stderr.contains("--source-root"));

    let stderr = assert_lockfile_conflict(&lockfile, &root.join("stdlib-root.wasm"), |command| {
        command.arg("--stdlib-root").arg(&stdlib_root);
    });
    assert!(stderr.contains("--stdlib-root"));

    let stderr = assert_lockfile_conflict(&lockfile, &root.join("stdlib.wasm"), |command| {
        command.arg("--stdlib").arg(&explicit_stdlib);
    });
    assert!(stderr.contains("--stdlib"));

    fs::remove_dir_all(&root).expect("remove package lockfile conflict root");
}

#[test]
fn cli_package_manifest_rejects_extra_positional_inputs() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "conflict", None);
    let src_root = root.join("src/app");
    fs::create_dir_all(&src_root).expect("create package source root");
    let entry = src_root.join("main.lani");
    fs::write(&entry, "module app::main;\nfn main() { return 0; }\n").expect("write entry module");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "app",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    let mut command = Command::new(laniusc_bin());
    command.arg("--package-manifest").arg(&manifest).arg(&entry);
    let output =
        common::command_output_with_timeout("laniusc --package-manifest extra input", &mut command);
    assert!(
        !output.status.success(),
        "package manifest with positional input should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-manifest describes the entry"));
    assert!(stderr.contains("do not also pass positional input files"));

    fs::remove_dir_all(&root).expect("remove package manifest conflict root");
}

#[test]
fn cli_package_manifest_mixed_input_mode_can_render_json_without_loading_source() {
    let root = common::temp_artifact_path("laniusc_cli_package_manifest", "json_conflict", None);
    let missing_manifest = root.join("missing-package.json");
    let missing_input = root.join("missing-input.lani");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--package-manifest")
        .arg(&missing_manifest)
        .arg(&missing_input);
    let output = common::command_output_with_timeout(
        "laniusc --package-manifest mixed input JSON",
        &mut command,
    );

    assert!(
        !output.status.success(),
        "package manifest mixed input modes should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "package manifest mixed input diagnostic should not write target bytes"
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("incompatible package-manifest diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--package-manifest")),
        "diagnostic notes should identify the package manifest selector\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("positional input files")),
        "diagnostic notes should identify the incompatible input mode\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_package_lockfile_mixed_input_mode_can_render_json_without_loading_source() {
    let root =
        common::temp_artifact_path("laniusc_cli_package_manifest", "lock_json_conflict", None);
    let missing_lockfile = root.join("missing-lock.json");
    let missing_input = root.join("missing-input.lani");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--package-lockfile")
        .arg(&missing_lockfile)
        .arg(&missing_input);
    let output = common::command_output_with_timeout(
        "laniusc --package-lockfile mixed input JSON",
        &mut command,
    );

    assert!(
        !output.status.success(),
        "package lockfile mixed input modes should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "package lockfile mixed input diagnostic should not write target bytes"
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("missing-lock.json") && !stderr.contains("missing-input.lani"),
        "package lockfile mixed-input validation should run before lockfile or source loading\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("incompatible package-lockfile diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--package-lockfile")),
        "diagnostic notes should identify the package lockfile selector\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("positional input files")),
        "diagnostic notes should identify the incompatible input mode\nstderr:\n{stderr}"
    );
}

fn write_package_manifest_fixture(root: &Path) -> (PathBuf, PathBuf, PathBuf) {
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    fs::create_dir_all(&app_root).expect("create package app source root");

    fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn add_one(value: i32) -> i32 {
    return value + 1;
}
"#,
    )
    .expect("write helper module");

    let entry = app_root.join("main.lani");
    fs::write(
        &entry,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::add_one(-1);
}
"#,
    )
    .expect("write entry module");

    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "metadata-name-not-module-identity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    (src_root, entry, manifest)
}

fn write_package_lockfile_fixture(root: &Path) -> (PathBuf, PathBuf, PathBuf) {
    let (src_root, entry, manifest) = write_package_manifest_fixture(root);

    let resolved = PackageManifest::load_json_file(&manifest).expect("load package manifest");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_path = root.join("lanius.lock.json");
    lockfile
        .write_json_file(&lockfile_path)
        .expect("write package lockfile");
    (src_root, entry, lockfile_path)
}

fn assert_package_lock_failure(configure: impl FnOnce(&mut Command)) -> String {
    let mut command = Command::new(laniusc_bin());
    command.arg("package").arg("lock");
    configure(&mut command);

    let output = common::command_output_with_timeout("laniusc package lock bad args", &mut command);
    assert!(
        !output.status.success(),
        "package lock command should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn assert_lockfile_conflict(
    lockfile: &Path,
    output_path: &Path,
    configure: impl FnOnce(&mut Command),
) -> String {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--package-lockfile")
        .arg(lockfile)
        .arg("-o")
        .arg(output_path);
    configure(&mut command);

    let output =
        common::command_output_with_timeout("laniusc --package-lockfile conflict", &mut command);
    assert!(
        !output.status.success(),
        "package lockfile with mixed input mode should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        !output_path.exists(),
        "failed lockfile conflict should not emit {}",
        output_path.display()
    );
    String::from_utf8_lossy(&output.stderr).into_owned()
}
