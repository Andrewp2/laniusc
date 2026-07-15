mod common;

use std::path::{Path, PathBuf};

use laniusc_compiler::compiler::{
    CompileError,
    PACKAGE_LOCKFILE_LANGUAGE_EDITION,
    PACKAGE_LOCKFILE_VERSION,
    PackageLockfile,
    PackageLockfileArtifact,
    PackageManifest,
    load_entry_path_manifest_with_source_root,
};

fn assert_package_diagnostic(err: &CompileError, code: &str, message: &str, note: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured package diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, code);
    assert_eq!(diagnostic.message, message);
    assert!(
        diagnostic.primary_label.is_none(),
        "package control-plane diagnostics should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(note),
        "diagnostic should include detailed note {note:?}: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

#[test]
fn package_manifest_errors_are_structured() {
    let parse_err = PackageManifest::parse_json("{")
        .expect_err("malformed manifest JSON should produce a diagnostic");
    assert_package_diagnostic(
        &parse_err,
        "LNC0053",
        "package manifest invalid",
        "parse package manifest JSON",
    );

    let missing_manifest =
        common::temp_artifact_path("laniusc_package_manifest", "missing_manifest", Some("json"));
    let read_err = PackageManifest::load_json_file(&missing_manifest)
        .expect_err("missing package manifest should produce a diagnostic");
    assert_package_diagnostic(
        &read_err,
        "LNC0054",
        "package manifest could not be read",
        &missing_manifest.display().to_string(),
    );
}

#[test]
fn package_lockfile_errors_are_structured() {
    let parse_err = PackageLockfile::parse_json("{")
        .expect_err("malformed lockfile JSON should produce a diagnostic");
    assert_package_diagnostic(
        &parse_err,
        "LNC0055",
        "package lockfile invalid",
        "parse package lockfile JSON",
    );

    let missing_lockfile =
        common::temp_artifact_path("laniusc_package_manifest", "missing_lockfile", Some("json"));
    let read_err = PackageLockfile::load_json_file(&missing_lockfile)
        .expect_err("missing package lockfile should produce a diagnostic");
    assert_package_diagnostic(
        &read_err,
        "LNC0056",
        "package lockfile could not be read or written",
        &missing_lockfile.display().to_string(),
    );
}

#[test]
fn package_lockfile_write_errors_are_structured() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "lockfile_write_io", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "lockfile-write-io");
    let lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    let blocked_parent = root.join("blocked-parent");
    std::fs::write(&blocked_parent, b"not a directory")
        .expect("create blocking file at output parent path");
    let output_path = blocked_parent.join("lanius.lock.json");

    let write_err = lockfile
        .write_json_file(&output_path)
        .expect_err("package lockfile write failures should produce a diagnostic");
    assert_package_diagnostic(
        &write_err,
        "LNC0056",
        "package lockfile could not be read or written",
        "create package lockfile directory",
    );

    std::fs::remove_dir_all(&root).expect("remove package lockfile write temp root");
}

#[test]
fn package_lockfile_rejects_module_declaration_file_mapping_mismatch() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "control_plane", None);
    let src_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create package stdlib root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::renamed;

pub fn one() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::one();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "manifest-name-is-not-a-module",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile = PackageLockfile::from_resolved_manifest(&resolved)
        .expect("package lockfile should record resolved manifest metadata");
    assert_eq!(lockfile.version, PACKAGE_LOCKFILE_VERSION);
    assert_eq!(lockfile.language_edition, PACKAGE_LOCKFILE_LANGUAGE_EDITION);
    assert_eq!(lockfile.compiler_version, env!("CARGO_PKG_VERSION"));
    assert_eq!(lockfile.package, "manifest-name-is-not-a-module");
    assert!(lockfile.roots.iter().all(|root| root.is_absolute()));
    assert!(lockfile.entry.is_absolute());

    let roots = lockfile.to_entry_source_roots();
    assert_eq!(
        roots.user_roots,
        vec![std::fs::canonicalize(&src_root).unwrap()]
    );
    assert_eq!(
        roots.stdlib_root,
        Some(std::fs::canonicalize(&stdlib_root).unwrap())
    );

    let err = lockfile
        .load_path_manifest()
        .expect_err("package lockfiles should reject module declarations that do not match source-root file paths before compiling");
    assert_source_spanned_module_file_mapping_error(&err, "app::renamed", "app::helper");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should not persist mismatched module/file metadata",
    );
    assert_source_spanned_module_file_mapping_error(&err, "app::renamed", "app::helper");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_dotted_module_declarations_before_package_normalization() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "dotted_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app.main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with a dotted module declaration");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "dotted-module",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "package replay should reject package-name-shaped module declarations before normalization",
    );
    assert_source_spanned_module_path_separator_error(&err, &entry_path, "module app.main;");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should not persist dotted module declaration metadata",
    );
    assert_source_spanned_module_path_separator_error(&err, &entry_path, "module app.main;");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_span_for_missing_source_root_declaration() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "missing_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
pub fn value() -> i32 {
    return 3;
}
"#,
    )
    .expect("write package helper source without leading module");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "missing-module",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should reject source files without module declarations",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("missing module declaration diagnostic should carry a source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("pub fn value() -> i32 {")
            );
            assert_eq!(label.message, "expected leading module declaration");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("app/helper.lani") && note.contains("app::helper")),
                "expected source-root relative module note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("stale source-root metadata")),
                "expected stale metadata note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned missing module diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_span_for_module_declaration_after_items() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "module_after_item", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
fn before_module() -> i32 {
    return 0;
}

module app::main;

fn main() {
    return before_module();
}
"#,
    )
    .expect("write package entry source with a module declaration after an item");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "module-after-item",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject module declarations after items");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("non-leading module diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("module app::main;"));
            assert_eq!(
                label.message,
                "module declarations must appear before other items"
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("first non-comment declaration")),
                "expected module-position note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned non-leading module diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_multiple_leading_module_declarations_in_source_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "multiple_modules", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;
module app::other;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with ambiguous module identity");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "multiple-modules",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject ambiguous source module identity");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("duplicate leading module diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("module app::other;"));
            assert_eq!(label.message, "duplicate module declaration");
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("exactly one leading module declaration")
                        && note.contains("source file")
                }),
                "expected package replay single-module note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("app::other")
                        && note.contains("app::main")
                        && note.contains("source identity")
                }),
                "expected source identity ambiguity note to name both modules, got {:?}",
                diagnostic.notes
            );
        }
        other => {
            panic!("expected source-spanned duplicate leading module diagnostic, got {other:?}")
        }
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_non_leading_module_declarations_in_source_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "late_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn before_second_module() -> i32 {
    return 0;
}

module app::shadow;

fn main() {
    return before_second_module();
}
"#,
    )
    .expect("write package entry source with non-leading module identity");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "late-module",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject non-leading module identities");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("non-leading module diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("module app::shadow;"));
            assert_eq!(
                label.message,
                "module declarations must appear before other items"
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("exactly one leading module declaration")
                        && note.contains("source file")
                }),
                "expected package replay single-module note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| { note.contains("app::shadow") && note.contains("app::main") }),
                "expected note to name both module declarations, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned non-leading module diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_non_reproducible_control_plane_fields() {
    assert_lockfile_rejects(
        r#"
{
  "version": 2,
  "package": "app",
  "language_edition": "unstable-alpha",
  "compiler_version": "0.1.0",
  "roots": ["/tmp/lanius-lock-src"],
  "entry": "/tmp/lanius-lock-src/main.lani"
}
"#,
        "unsupported version",
    );
    assert_lockfile_rejects(
        r#"
{
  "version": 1,
  "package": "app",
  "language_edition": "future-stable",
  "compiler_version": "0.1.0",
  "roots": ["/tmp/lanius-lock-src"],
  "entry": "/tmp/lanius-lock-src/main.lani"
}
"#,
        "unsupported language edition",
    );
    assert_lockfile_rejects(
        r#"
{
  "version": 1,
  "package": "app",
  "language_edition": "unstable-alpha",
  "compiler_version": "0.1.0",
  "roots": ["relative-src"],
  "entry": "/tmp/lanius-lock-src/main.lani"
}
"#,
        "absolute resolved path",
    );
    let entry_outside_roots = r#"
{
  "version": 1,
  "package": "app",
  "language_edition": "unstable-alpha",
  "compiler_version": "0.1.0",
  "roots": ["/tmp/lanius-lock-src"],
  "entry": "/tmp/other/main.lani"
}
"#;
    let err = PackageLockfile::parse_json(entry_outside_roots)
        .expect_err("lockfile entries outside roots should report the resolved root boundary");
    let message = format!("{err:?}");
    assert!(
        message.contains("not under any resolved source root")
            && message.contains("resolved source roots")
            && message.contains("/tmp/lanius-lock-src"),
        "expected lockfile entry/root diagnostic to list resolved roots, got {message}"
    );
    assert_lockfile_rejects(
        r#"
{
  "version": 1,
  "package": "app",
  "language_edition": "unstable-alpha",
  "compiler_version": "0.1.0",
  "roots": ["/tmp/lanius-lock-src"],
  "entry": "/tmp/lanius-lock-src/main.lani",
  "module_identity": "app::main"
}
"#,
        "unknown field",
    );
}

#[test]
fn package_manifest_rejects_absolute_paths_so_lockfiles_own_resolved_paths() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "absolute_paths", None);
    let src_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create package stdlib root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let absolute_root = PackageManifest::parse_json(&format!(
        r#"{{
  "package": "absolute-root",
  "roots": [{}],
  "entry": "src/app/main.lani"
}}"#,
        serde_json::to_string(&src_root).expect("encode source root path")
    ))
    .expect_err("package manifests should reject absolute source roots");
    assert_manifest_relative_path_error(&absolute_root, "source root");

    let absolute_stdlib = PackageManifest::parse_json(&format!(
        r#"{{
  "package": "absolute-stdlib",
  "roots": ["src"],
  "stdlib_root": {},
  "entry": "src/app/main.lani"
}}"#,
        serde_json::to_string(&stdlib_root).expect("encode stdlib root path")
    ))
    .expect_err("package manifests should reject absolute stdlib roots");
    assert_manifest_relative_path_error(&absolute_stdlib, "stdlib root");

    let absolute_entry = PackageManifest::parse_json(&format!(
        r#"{{
  "package": "absolute-entry",
  "roots": ["src"],
  "entry": {}
}}"#,
        serde_json::to_string(&entry_path).expect("encode entry path")
    ))
    .expect_err("package manifests should reject absolute entries");
    assert_manifest_relative_path_error(&absolute_entry, "entry");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_public_serde_enforces_manifest_shape() {
    let manifest: PackageManifest = serde_json::from_str(
        r#"
{
  "package": "public-serde",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("public manifest serde should accept valid package metadata");
    assert_eq!(manifest.package, "public-serde");
    assert_eq!(manifest.roots, vec![PathBuf::from("src")]);
    assert_eq!(manifest.stdlib_root, Some(PathBuf::from("stdlib")));
    assert_eq!(manifest.entry, PathBuf::from("src/app/main.lani"));

    let serialized = serde_json::to_value(&manifest)
        .expect("public manifest serde should serialize valid package metadata");
    assert_eq!(serialized["package"].as_str(), Some("public-serde"));
    assert_eq!(serialized["roots"][0].as_str(), Some("src"));
    assert_eq!(serialized["stdlib_root"].as_str(), Some("stdlib"));
    assert_eq!(serialized["entry"].as_str(), Some("src/app/main.lani"));

    let absolute_root = std::env::temp_dir().join("laniusc-public-serde-src");
    let err = serde_json::from_value::<PackageManifest>(serde_json::json!({
        "package": "public-serde",
        "roots": [absolute_root.display().to_string()],
        "entry": "src/app/main.lani"
    }))
    .expect_err("public manifest serde should reject absolute source roots");
    let message = err.to_string();
    assert!(
        message.contains("source root")
            && message.contains("must be relative")
            && message.contains("lockfiles record canonical absolute paths"),
        "expected public manifest serde relative-path error, got {message}"
    );

    let err = serde_json::from_str::<PackageManifest>(
        r#"
{
  "package": "public-serde",
  "roots": ["src"],
  "entry": "src/app/main.txt"
}
"#,
    )
    .expect_err("public manifest serde should reject non-source entry paths");
    let message = err.to_string();
    assert!(
        message.contains("entry") && message.contains(".lani source file extension"),
        "expected public manifest serde source-extension error, got {message}"
    );

    let invalid_manifest = PackageManifest {
        package: "public-serde".to_string(),
        roots: vec![PathBuf::from("../src")],
        stdlib_root: None,
        entry: PathBuf::from("src/app/main.lani"),
    };
    let err = serde_json::to_string(&invalid_manifest)
        .expect_err("public manifest serialization should reject invalid package metadata");
    let message = err.to_string();
    assert!(
        message.contains("source root")
            && message.contains("normalized package-relative path")
            && message.contains("parent-directory components"),
        "expected public manifest serde serialization error, got {message}"
    );
}

#[test]
fn package_manifest_reports_dependency_fields_as_unsupported_import_configuration() {
    let err = PackageManifest::parse_json(
        r#"
{
  "package": "manifest-import-config",
  "roots": ["src"],
  "dependencies": {
    "tools": "../tools"
  },
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject dependency sections with import guidance");
    let message = format!("{err:?}");
    assert!(
        message.contains("unsupported package manifest field `dependencies`")
            && message.contains("source roots")
            && message.contains("stdlib_root")
            && message.contains("imports are declared in .lani source files")
            && message.contains("external package dependencies are not supported yet"),
        "expected manifest dependency-field guidance, got {message}"
    );
}

#[test]
fn package_metadata_rejects_unstable_package_name_shapes() {
    let leading_separator = PackageManifest::parse_json(
        r#"
{
  "package": ".app",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject names with empty leading segments");
    assert_invalid_package_name_error(&leading_separator, ".app");

    let trailing_separator = serde_json::from_str::<PackageManifest>(
        r#"
{
  "package": "app.",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("public manifest serde should reject names with empty trailing segments");
    let message = trailing_separator.to_string();
    assert_invalid_package_name_message(&message, "app.");

    let invalid_manifest = PackageManifest {
        package: "app..core".to_string(),
        roots: vec![PathBuf::from("src")],
        stdlib_root: None,
        entry: PathBuf::from("src/app/main.lani"),
    };
    let err = serde_json::to_string(&invalid_manifest)
        .expect_err("public manifest serialization should reject empty package name segments");
    let message = err.to_string();
    assert_invalid_package_name_message(&message, "app..core");

    let lockfile_json = format!(
        r#"
{{
  "version": {PACKAGE_LOCKFILE_VERSION},
  "package": "app-",
  "language_edition": "{PACKAGE_LOCKFILE_LANGUAGE_EDITION}",
  "compiler_version": "{}",
  "roots": ["/tmp/lanius-lock-src"],
  "entry": "/tmp/lanius-lock-src/main.lani"
}}
"#,
        env!("CARGO_PKG_VERSION"),
    );
    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("package lockfiles should reject names with punctuation-ended segments");
    assert_invalid_package_name_error(&err, "app-");
}

#[test]
fn package_manifest_public_boundary_rejects_duplicate_source_roots() {
    let err = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-roots",
  "roots": ["src", "src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject duplicate source roots before resolution");
    assert_duplicate_manifest_source_root_error(&err);

    let err = serde_json::from_str::<PackageManifest>(
        r#"
{
  "package": "duplicate-roots",
  "roots": ["src", "src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("public manifest serde should reject duplicate source roots");
    let message = err.to_string();
    assert!(
        message.contains("duplicate package source root") && message.contains("src"),
        "expected duplicate source-root serde error, got {message}"
    );

    let manifest = PackageManifest {
        package: "duplicate-roots".to_string(),
        roots: vec![PathBuf::from("src"), PathBuf::from("src")],
        stdlib_root: None,
        entry: PathBuf::from("src/app/main.lani"),
    };
    let err = serde_json::to_string(&manifest)
        .expect_err("public manifest serialization should reject duplicate source roots");
    let message = err.to_string();
    assert!(
        message.contains("duplicate package source root") && message.contains("src"),
        "expected duplicate source-root serialization error, got {message}"
    );
}

#[test]
fn package_manifest_and_lockfile_require_lani_entry_source_path() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "entry_extension", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.txt");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with ambiguous extension");

    let manifest_err = PackageManifest::parse_json(
        r#"
{
  "package": "entry-extension",
  "roots": ["src"],
  "entry": "src/app/main.txt"
}
"#,
    )
    .expect_err("package manifests should require .lani entry source paths");
    assert_entry_source_extension_error(&manifest_err);

    let lockfile_document = serde_json::json!({
        "version": PACKAGE_LOCKFILE_VERSION,
        "package": "entry-extension",
        "language_edition": PACKAGE_LOCKFILE_LANGUAGE_EDITION,
        "compiler_version": env!("CARGO_PKG_VERSION"),
        "roots": [
            std::fs::canonicalize(&src_root)
                .expect("canonicalize package source root")
                .display()
                .to_string()
        ],
        "entry": std::fs::canonicalize(&entry_path)
            .expect("canonicalize package entry")
            .display()
            .to_string()
    });
    let lockfile_json =
        serde_json::to_string_pretty(&lockfile_document).expect("serialize lockfile JSON");
    let lockfile_err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("package lockfiles should require .lani entry source paths");
    assert_entry_source_extension_error(&lockfile_err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_rejects_parent_directory_paths_before_resolution() {
    let parent_root = PackageManifest::parse_json(
        r#"
{
  "package": "parent-root",
  "roots": ["../src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject source roots that escape the package directory");
    assert_manifest_parent_path_error(&parent_root, "source root");

    let parent_stdlib = PackageManifest::parse_json(
        r#"
{
  "package": "parent-stdlib",
  "roots": ["src"],
  "stdlib_root": "../stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject stdlib roots that escape the package directory");
    assert_manifest_parent_path_error(&parent_stdlib, "stdlib root");

    let parent_entry = PackageManifest::parse_json(
        r#"
{
  "package": "parent-entry",
  "roots": ["src"],
  "entry": "../src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject entries that escape the package directory");
    assert_manifest_parent_path_error(&parent_entry, "entry");
}

#[test]
fn package_manifest_rejects_non_normalized_relative_paths_before_resolution() {
    let current_dir_root = PackageManifest::parse_json(
        r#"
{
  "package": "current-dir-root",
  "roots": ["./src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject source roots with current-directory components");
    assert_manifest_normalized_path_error(&current_dir_root, "source root");

    let current_dir_stdlib = PackageManifest::parse_json(
        r#"
{
  "package": "current-dir-stdlib",
  "roots": ["src"],
  "stdlib_root": "stdlib/.",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject stdlib roots with current-directory components");
    assert_manifest_normalized_path_error(&current_dir_stdlib, "stdlib root");

    let current_dir_entry = PackageManifest::parse_json(
        r#"
{
  "package": "current-dir-entry",
  "roots": ["src"],
  "entry": "src/./app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject entries with current-directory components");
    assert_manifest_normalized_path_error(&current_dir_entry, "entry");

    let backslash_root = PackageManifest::parse_json(
        r#"
{
  "package": "backslash-root",
  "roots": ["src\\app"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should require portable source-root separators");
    assert_manifest_separator_path_error(&backslash_root, "source root");

    let backslash_stdlib = PackageManifest::parse_json(
        r#"
{
  "package": "backslash-stdlib",
  "roots": ["src"],
  "stdlib_root": "stdlib\\core",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should require portable stdlib-root separators");
    assert_manifest_separator_path_error(&backslash_stdlib, "stdlib root");

    let backslash_entry = PackageManifest::parse_json(
        r#"
{
  "package": "backslash-entry",
  "roots": ["src"],
  "entry": "src\\app/main.lani"
}
"#,
    )
    .expect_err("package manifests should require portable entry separators");
    assert_manifest_separator_path_error(&backslash_entry, "entry");

    let prefix_root = PackageManifest::parse_json(
        r#"
{
  "package": "prefix-root",
  "roots": ["pkg:src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject source roots with drive-like prefixes");
    assert_manifest_portable_path_error(&prefix_root, "source root");

    let prefix_stdlib = PackageManifest::parse_json(
        r#"
{
  "package": "prefix-stdlib",
  "roots": ["src"],
  "stdlib_root": "pkg:stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject stdlib roots with drive-like prefixes");
    assert_manifest_portable_path_error(&prefix_stdlib, "stdlib root");

    let prefix_entry = PackageManifest::parse_json(
        r#"
{
  "package": "prefix-entry",
  "roots": ["src"],
  "entry": "pkg:src/app/main.lani"
}
"#,
    )
    .expect_err("package manifests should reject entries with drive-like prefixes");
    assert_manifest_portable_path_error(&prefix_entry, "entry");
}

#[cfg(unix)]
#[test]
fn package_manifest_rejects_symlink_escapes_before_lockfile_resolution() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "symlink_escape", None);
    let package_dir = root.join("package");
    let outside_dir = root.join("outside");
    let package_app = package_dir.join("src").join("app");
    let outside_app = outside_dir.join("src").join("app");
    let outside_stdlib = outside_dir.join("stdlib");
    std::fs::create_dir_all(&package_app).expect("create package app source root");
    std::fs::create_dir_all(&outside_app).expect("create escaped source root");
    std::fs::create_dir_all(&outside_stdlib).expect("create escaped stdlib root");

    std::fs::write(
        package_app.join("main.lani"),
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write package entry source");
    std::fs::write(
        outside_app.join("main.lani"),
        "module outside::main;\nfn main() { return 0; }\n",
    )
    .expect("write escaped source entry");
    let outside_entry = outside_dir.join("external-main.lani");
    std::fs::write(
        &outside_entry,
        "module outside::entry;\nfn main() { return 0; }\n",
    )
    .expect("write escaped entry source");

    std::os::unix::fs::symlink(outside_dir.join("src"), package_dir.join("linked-src"))
        .expect("create source-root escape symlink");
    std::os::unix::fs::symlink(&outside_stdlib, package_dir.join("linked-stdlib"))
        .expect("create stdlib escape symlink");
    std::os::unix::fs::symlink(&outside_entry, package_app.join("linked-main.lani"))
        .expect("create entry escape symlink");

    let source_root_escape = PackageManifest::parse_json(
        r#"
{
  "package": "symlink-source-root",
  "roots": ["linked-src"],
  "entry": "linked-src/app/main.lani"
}
"#,
    )
    .expect("parse source-root symlink escape manifest");
    let err = source_root_escape
        .resolve_from_dir(&package_dir)
        .expect_err("source-root symlink escapes should not enter lockfile metadata");
    assert_manifest_symlink_escape_error(&err, "package source root");

    let stdlib_escape = PackageManifest::parse_json(
        r#"
{
  "package": "symlink-stdlib-root",
  "roots": ["src"],
  "stdlib_root": "linked-stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse stdlib symlink escape manifest");
    let err = stdlib_escape
        .resolve_from_dir(&package_dir)
        .expect_err("stdlib symlink escapes should not enter lockfile metadata");
    assert_manifest_symlink_escape_error(&err, "package stdlib root");

    let entry_escape = PackageManifest::parse_json(
        r#"
{
  "package": "symlink-entry",
  "roots": ["src"],
  "entry": "src/app/linked-main.lani"
}
"#,
    )
    .expect("parse entry symlink escape manifest");
    let err = entry_escape
        .resolve_from_dir(&package_dir)
        .expect_err("entry symlink escapes should not enter lockfile metadata");
    assert_manifest_symlink_escape_error(&err, "package entry");

    std::fs::remove_dir_all(&root).expect("remove symlink escape temp root");
}

#[cfg(unix)]
#[test]
fn package_manifest_rejects_source_root_symlink_to_manifest_directory() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "symlink_root_self", None);
    let package_dir = root.join("package");
    let package_app = package_dir.join("app");
    std::fs::create_dir_all(&package_app).expect("create package app source root");
    std::fs::write(
        package_app.join("main.lani"),
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write package entry source");
    std::os::unix::fs::symlink(&package_dir, package_dir.join("linked-root"))
        .expect("create source-root symlink to package manifest directory");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "symlink-root-self",
  "roots": ["linked-root"],
  "entry": "linked-root/app/main.lani"
}
"#,
    )
    .expect("parse source-root self-symlink manifest");
    let err = manifest.resolve_from_dir(&package_dir).expect_err(
        "source-root symlinks should not widen the package source root to the manifest directory",
    );
    assert_manifest_directory_scope_error(&err, "package source root");

    std::fs::remove_dir_all(&root).expect("remove source-root self-symlink temp root");
}

#[cfg(unix)]
#[test]
fn package_manifest_rejects_entry_symlink_to_non_source_file() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "entry_symlink_ext", None);
    let package_dir = root.join("package");
    let package_app = package_dir.join("src").join("app");
    std::fs::create_dir_all(&package_app).expect("create package app source root");

    let non_source_entry = package_app.join("main.txt");
    std::fs::write(
        &non_source_entry,
        "module app::main;\nfn main() { return 0; }\n",
    )
    .expect("write non-source entry target");
    std::os::unix::fs::symlink(&non_source_entry, package_app.join("main.lani"))
        .expect("create entry symlink with source-looking name");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "entry-symlink-extension",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse entry symlink manifest");
    let err = manifest
        .resolve_from_dir(&package_dir)
        .expect_err("resolved package entries should remain canonical .lani source files");
    assert_entry_source_extension_error(&err);

    std::fs::remove_dir_all(&root).expect("remove entry symlink temp root");
}

#[test]
fn package_lockfile_rejects_other_compiler_versions() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "compiler_version", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "compiler-version",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize complete package lockfile");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse real lockfile");
    let stale_version = format!("{}-stale-lockfile", env!("CARGO_PKG_VERSION"));
    let fields = document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object");
    assert_eq!(
        fields.get("compiler_version"),
        Some(&serde_json::Value::String(
            env!("CARGO_PKG_VERSION").to_string()
        ))
    );
    fields.insert(
        "compiler_version".to_string(),
        serde_json::Value::String(stale_version.clone()),
    );
    let stale_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize stale-version lockfile");

    let err = PackageLockfile::parse_json(&stale_lockfile_json)
        .expect_err("lockfile from a different compiler version should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("unsupported compiler version")
            && message.contains(&stale_version)
            && message.contains(env!("CARGO_PKG_VERSION")),
        "expected compiler-version boundary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_metadata_rejects_overlapping_source_roots() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "overlap", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let overlapping_roots = PackageManifest::parse_json(
        r#"
{
  "package": "overlap",
  "roots": ["src", "src/app"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse overlapping-root manifest JSON");
    assert!(
        overlapping_roots.resolve_from_dir(&root).is_err(),
        "overlapping source roots should be rejected instead of silently changing import search identity"
    );

    let overlapping_stdlib = PackageManifest::parse_json(
        r#"
{
  "package": "overlap",
  "roots": ["src"],
  "stdlib_root": "src/app",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse overlapping-stdlib manifest JSON");
    assert!(
        overlapping_stdlib.resolve_from_dir(&root).is_err(),
        "stdlib and user roots should not describe overlapping source files"
    );

    let lock_root = common::temp_artifact_path("laniusc_package_manifest", "overlap_lock", None);
    let (src_root, _, lockfile_path) = write_minimal_generated_lockfile(&lock_root, "overlap-lock");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .get_mut("roots")
        .expect("generated lockfile should contain roots")
        .as_array_mut()
        .expect("generated lockfile roots should be an array")
        .push(serde_json::Value::String(
            std::fs::canonicalize(src_root.join("app"))
                .expect("canonicalize nested package root")
                .display()
                .to_string(),
        ));
    let overlapping_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize overlapping-root lockfile");
    assert!(
        PackageLockfile::parse_json(&overlapping_lockfile_json).is_err(),
        "lockfiles with overlapping resolved roots should be rejected"
    );

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "stdlib_root".to_string(),
            serde_json::Value::String(
                std::fs::canonicalize(&src_root)
                    .expect("canonicalize package source root")
                    .display()
                    .to_string(),
            ),
        );
    let overlapping_stdlib_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize overlapping-stdlib lockfile");
    assert!(
        PackageLockfile::parse_json(&overlapping_stdlib_lockfile_json).is_err(),
        "lockfiles with overlapping stdlib and user roots should be rejected"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
    std::fs::remove_dir_all(&lock_root).expect("remove package lockfile temp root");
}

#[test]
fn package_manifest_normalizes_root_order_for_reproducible_lockfiles() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "root_order", None);
    let alpha_root = root.join("a-src");
    let beta_root = root.join("z-src");
    let app_root = beta_root.join("app");
    std::fs::create_dir_all(&alpha_root).expect("create first package source root");
    std::fs::create_dir_all(&app_root).expect("create second package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest_z_first = PackageManifest::parse_json(
        r#"
{
  "package": "root-order",
  "roots": ["z-src", "a-src"],
  "entry": "z-src/app/main.lani"
}
"#,
    )
    .expect("parse z-first package manifest JSON");
    let manifest_a_first = PackageManifest::parse_json(
        r#"
{
  "package": "root-order",
  "roots": ["a-src", "z-src"],
  "entry": "z-src/app/main.lani"
}
"#,
    )
    .expect("parse a-first package manifest JSON");

    let resolved_z_first = manifest_z_first
        .resolve_from_dir(&root)
        .expect("resolve z-first package manifest");
    let resolved_a_first = manifest_a_first
        .resolve_from_dir(&root)
        .expect("resolve a-first package manifest");
    let expected_roots = vec![
        std::fs::canonicalize(&alpha_root).expect("canonicalize first package source root"),
        std::fs::canonicalize(&beta_root).expect("canonicalize second package source root"),
    ];
    assert_eq!(resolved_z_first.roots, expected_roots);
    assert_eq!(resolved_a_first.roots, expected_roots);

    let lockfile_z_first = PackageLockfile::from_resolved_manifest(&resolved_z_first)
        .expect("create z-first package lockfile")
        .to_json_pretty()
        .expect("serialize z-first package lockfile");
    let lockfile_a_first = PackageLockfile::from_resolved_manifest(&resolved_a_first)
        .expect("create a-first package lockfile")
        .to_json_pretty()
        .expect("serialize a-first package lockfile");
    assert_eq!(
        lockfile_z_first, lockfile_a_first,
        "manifest root order should not make semantically identical lockfiles differ"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_unsorted_resolved_source_roots() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "unsorted_roots", None);
    let alpha_root = root.join("a-src");
    let beta_root = root.join("z-src");
    let app_root = beta_root.join("app");
    std::fs::create_dir_all(&alpha_root).expect("create first package source root");
    std::fs::create_dir_all(&app_root).expect("create second package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let document = serde_json::json!({
        "version": PACKAGE_LOCKFILE_VERSION,
        "package": "unsorted-roots",
        "language_edition": PACKAGE_LOCKFILE_LANGUAGE_EDITION,
        "compiler_version": env!("CARGO_PKG_VERSION"),
        "roots": [
            std::fs::canonicalize(&beta_root)
                .expect("canonicalize second package source root")
                .display()
                .to_string(),
            std::fs::canonicalize(&alpha_root)
                .expect("canonicalize first package source root")
                .display()
                .to_string()
        ],
        "entry": std::fs::canonicalize(&entry_path)
            .expect("canonicalize package entry")
            .display()
            .to_string()
    });
    let lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize unsorted lockfile JSON");

    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("lockfiles should reject non-deterministic source-root order");
    let message = format!("{err:?}");
    assert!(
        message.contains("resolved source roots must be sorted"),
        "expected source-root ordering error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_filesystem_root_import_roots() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "filesystem_root", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "filesystem-root-lockfile");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let filesystem_root = root
        .ancestors()
        .last()
        .expect("temp root should have a filesystem root ancestor")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "roots".to_string(),
            serde_json::Value::Array(vec![serde_json::Value::String(filesystem_root.clone())]),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize root-source lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("package lockfiles must not accept filesystem root as a source root");
    assert_filesystem_root_import_root_error(&err, "source root");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "stdlib_root".to_string(),
            serde_json::Value::String(filesystem_root),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize root-stdlib lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("package lockfiles must not accept filesystem root as a stdlib root");
    assert_filesystem_root_import_root_error(&err, "stdlib root");

    std::fs::remove_dir_all(&root).expect("remove filesystem-root lockfile temp root");
}

#[test]
fn package_lockfile_records_and_validates_input_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "input_identity", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "input-identity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let first_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with input identity");
    let second_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile deterministically");
    assert_eq!(
        first_json, second_json,
        "unchanged package inputs should produce deterministic lockfile JSON"
    );
    let first_document =
        serde_json::from_str::<serde_json::Value>(&first_json).expect("parse generated lockfile");
    let input_files = first_document
        .get("inputs")
        .and_then(|inputs| inputs.get("files"))
        .and_then(|files| files.as_array())
        .expect("lockfile JSON should persist source input identity");
    let helper_path_text = helper_path.display().to_string();
    assert!(
        input_files
            .iter()
            .any(|file| file.get("path").and_then(|path| path.as_str())
                == Some(helper_path_text.as_str())),
        "lockfile JSON should include imported source inputs"
    );

    PackageLockfile::parse_json(&first_json).expect("unchanged lockfile inputs should validate");

    let lockfile_path = root.join("lanius.lock.json");
    std::fs::write(&lockfile_path, &first_json).expect("write package lockfile");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 3;
}
"#,
    )
    .expect("mutate package helper source");

    let err = PackageLockfile::load_json_file(&lockfile_path)
        .expect_err("stale package lockfile should reject changed input contents");
    let message = format!("{err:?}");
    assert!(
        message.contains("input digest mismatch"),
        "expected stale lockfile error to mention input digest mismatch, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_noncanonical_input_digest_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "noncanonical_input_digest",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "noncanonical-input-digest");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let entry_input = input_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
        })
        .expect("generated lockfile should include the entry input");
    let noncanonical_digest = "fnv1a64:0123456789ABCDEF";
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "digest".to_string(),
            serde_json::Value::String(noncanonical_digest.to_string()),
        );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted input digests should use canonical lowercase lockfile metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains("invalid digest")
            && message.contains(noncanonical_digest),
        "expected canonical input digest metadata error, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch"),
        "noncanonical persisted digest metadata should fail before live source replay, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_empty_persisted_input_identity_before_live_replay() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "empty_persisted_input_identity",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "empty-persisted-input-identity");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let entry_input = input_files
        .iter_mut()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include the entry input");
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert("byte_len".to_string(), serde_json::Value::from(0));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("empty persisted input identities should fail as malformed package metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains("byte length must be greater than zero")
            && message.contains("leading module metadata"),
        "expected empty input identity metadata error, got {message}"
    );
    assert!(
        !message.contains("input byte length mismatch"),
        "malformed input identity should fail before live source replay, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stale_entry_input_before_source_replay_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stale_entry_input_before_replay",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "stale-entry-input");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    std::fs::write(
        &entry_path,
        r#"
fn main() {
    return 0;
}
"#,
    )
    .expect("mutate entry before replaying package metadata");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale entry bytes should fail input identity before source replay metadata is trusted",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("input")
            && message.contains("mismatch")
            && message.contains(canonical_entry.as_str()),
        "expected entry input-identity mismatch before source replay, got {message}"
    );
    assert!(
        !message.contains("missing leading module")
            && !message.contains("source-root relative path")
            && !message.contains("module declaration does not match"),
        "stale entry bytes should not be reported as source replay metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn loaded_package_lockfile_revalidates_input_identity_before_replay() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "loaded_stale_input", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "loaded-stale-input",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile_path = root.join("lanius.lock.json");
    PackageLockfile::from_resolved_manifest(&resolved)
        .expect("create package lockfile")
        .write_json_file(&lockfile_path)
        .expect("write package lockfile");

    let loaded = PackageLockfile::load_json_file(&lockfile_path)
        .expect("loaded package lockfile should validate before sources change");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 3;
}
"#,
    )
    .expect("mutate helper body without changing module or import metadata");

    let err = loaded
        .validate()
        .expect_err("loaded lockfile validation should reject stale source input bytes");
    assert_input_digest_mismatch_error(&err, &helper_path);

    let err = loaded
        .load_path_manifest()
        .expect_err("loaded lockfile replay should reject stale source input bytes");
    assert_input_digest_mismatch_error(&err, &helper_path);

    let err = loaded
        .load_source_pack()
        .expect_err("loaded lockfile source loading should reject stale source input bytes");
    assert_input_digest_mismatch_error(&err, &helper_path);

    let err = loaded
        .to_json_pretty()
        .expect_err("loaded lockfile serialization should reject stale source input bytes");
    assert_input_digest_mismatch_error(&err, &helper_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn loaded_package_lockfile_revalidates_import_graph_before_replay() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "loaded_stale_imports", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package leaf source");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "loaded-stale-imports",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile_path = root.join("lanius.lock.json");
    PackageLockfile::from_resolved_manifest(&resolved)
        .expect("create package lockfile")
        .write_json_file(&lockfile_path)
        .expect("write package lockfile");

    let loaded = PackageLockfile::load_json_file(&lockfile_path)
        .expect("loaded package lockfile should validate before import graph changes");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

import app::leaf;

pub fn value() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("mutate helper import graph");

    let err = loaded
        .load_path_manifest()
        .expect_err("loaded lockfile replay should reject a stale import graph");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed") && message.contains("app::leaf"),
        "expected loaded lockfile replay to reject stale import graph, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn loaded_package_lockfile_revalidates_entry_import_graph_before_entry_digest() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "loaded_stale_entry_imports",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "loaded-stale-entry-imports",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile_path = root.join("lanius.lock.json");
    PackageLockfile::from_resolved_manifest(&resolved)
        .expect("create package lockfile")
        .write_json_file(&lockfile_path)
        .expect("write package lockfile");

    let loaded = PackageLockfile::load_json_file(&lockfile_path)
        .expect("loaded package lockfile should validate before entry imports change");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("remove entry import graph edge");

    let err = loaded
        .load_path_manifest()
        .expect_err("loaded lockfile replay should reject stale entry import edges");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("app::helper")
            && message.contains("expected 1 imports")
            && message.contains("found 0"),
        "expected loaded lockfile replay to report the stale entry import edge, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_records_and_validates_source_identities() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "source_identity", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "source-identity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with source identities");

    let mut lockfile_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = lockfile_document
        .get("source_identities")
        .and_then(|identities| identities.get("files"))
        .and_then(|files| files.as_array())
        .expect("lockfile JSON should persist source identities");
    let helper_path_text = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let helper_identity = source_identity_files
        .iter()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(helper_path_text.as_str())
        })
        .expect("lockfile source identities should include imported helper");
    assert_eq!(helper_identity["library_id"], serde_json::Value::from(1));
    assert_eq!(helper_identity["module_path"].as_str(), Some("app::helper"));

    PackageLockfile::parse_json(&lockfile_json)
        .expect("unchanged lockfile source identities should validate");

    let source_identity_files = lockfile_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let helper_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(helper_path_text.as_str())
        })
        .expect("lockfile source identities should include imported helper");
    helper_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("app::renamed".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&lockfile_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("tampered package source identity should be rejected");
    assert_module_file_mapping_error(&err, "app::renamed", "app::helper");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_records_and_validates_source_root_membership_metadata() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "source_root_membership", None);
    let helper_root = root.join("a-src");
    let entry_root = root.join("z-src");
    let helper_dir = helper_root.join("lib");
    let entry_dir = entry_root.join("app");
    std::fs::create_dir_all(&helper_dir).expect("create helper source root");
    std::fs::create_dir_all(&entry_dir).expect("create entry source root");

    let helper_path = helper_dir.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module lib::helper;

pub fn value() -> i32 {
    return 6;
}
"#,
    )
    .expect("write helper source");

    let entry_path = entry_dir.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import lib::helper;

fn main() {
    return lib::helper::value();
}
"#,
    )
    .expect("write entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "source-root-membership",
  "roots": ["z-src", "a-src"],
  "entry": "z-src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with source root metadata");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated source-root membership metadata should validate");

    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize helper source")
        .display()
        .to_string();
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize entry source")
        .display()
        .to_string();
    let document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = document
        .get("source_identities")
        .and_then(|identities| identities.get("files"))
        .and_then(|files| files.as_array())
        .expect("lockfile JSON should persist source identity files");
    let helper_identity = source_identity_files
        .iter()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_helper.as_str())
        })
        .expect("source identities should include the imported helper");
    assert_eq!(
        helper_identity["source_root_index"],
        serde_json::Value::from(0)
    );
    assert_eq!(
        helper_identity["source_root_relative_path"].as_str(),
        Some("lib/helper.lani")
    );
    let entry_identity = source_identity_files
        .iter()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
        })
        .expect("source identities should include the entry");
    assert_eq!(
        entry_identity["source_root_index"],
        serde_json::Value::from(1)
    );
    assert_eq!(
        entry_identity["source_root_relative_path"].as_str(),
        Some("app/main.lani")
    );

    let mut tampered_document = document.clone();
    let source_identity_files = tampered_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let entry_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
        })
        .expect("source identities should include the mutable entry");
    entry_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert("source_root_index".to_string(), serde_json::Value::from(0));
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject stale source-root index metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("source-root index") && message.contains("expected 1"),
        "expected source-root index validation error, got {message}"
    );

    let mut tampered_document = document;
    let source_identity_files = tampered_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let helper_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_helper.as_str())
        })
        .expect("source identities should include the mutable helper");
    helper_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "source_root_relative_path".to_string(),
            serde_json::Value::String("app/main.lani".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject stale source-root relative path metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("source-root relative path") && message.contains("lib/helper.lani"),
        "expected source-root relative path validation error, got {message}"
    );

    let mut tampered_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = tampered_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let helper_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_helper.as_str())
        })
        .expect("source identities should include the mutable helper");
    helper_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "source_root_relative_path".to_string(),
            serde_json::Value::String("lib//helper.lani".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject non-normalized source-root relative path metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity relative path")
            && message.contains("normalized source-root relative path"),
        "expected normalized source-root relative path error, got {message}"
    );

    let mut tampered_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = tampered_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let helper_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_helper.as_str())
        })
        .expect("source identities should include the mutable helper");
    helper_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "source_root_relative_path".to_string(),
            serde_json::Value::String("lib\\helper.lani".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject non-portable source-root relative path metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity relative path")
            && message.contains("'/' separators")
            && message.contains("backslash path separators"),
        "expected source-root relative path separator error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_root_drift_before_duplicate_module_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "source_root_drift_before_duplicate",
        None,
    );
    let helper_root = root.join("a-src");
    let entry_root = root.join("z-src");
    let helper_dir = helper_root.join("lib");
    let entry_dir = entry_root.join("app");
    std::fs::create_dir_all(&helper_dir).expect("create helper source root");
    std::fs::create_dir_all(&entry_dir).expect("create entry source root");

    let helper_path = helper_dir.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module lib::helper;

pub fn value() -> i32 {
    return 6;
}
"#,
    )
    .expect("write helper source");

    let entry_path = entry_dir.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import lib::helper;

fn main() {
    return lib::helper::value();
}
"#,
    )
    .expect("write entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "source-root-drift-before-duplicate",
  "roots": ["z-src", "a-src"],
  "entry": "z-src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with source root metadata");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize entry source")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable source identities");
    let entry_identity = source_identity_files
        .iter_mut()
        .find(|file| {
            file.get("path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
        })
        .expect("source identities should include the mutable entry");
    let entry_identity = entry_identity
        .as_object_mut()
        .expect("source identity entry should be an object");
    entry_identity.insert("source_root_index".to_string(), serde_json::Value::from(0));
    entry_identity.insert(
        "source_root_relative_path".to_string(),
        serde_json::Value::String("lib/helper.lani".to_string()),
    );
    entry_identity.insert(
        "module_path".to_string(),
        serde_json::Value::String("lib::helper".to_string()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "lockfile source-root drift should be reported before duplicate module metadata",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("source-root index") && message.contains("expected 1"),
        "expected source-root membership drift error, got {message}"
    );
    assert!(
        !message.contains("duplicate source identity module"),
        "source-root drift should not be masked by duplicate module metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_duplicate_source_identity_modules_in_one_library() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "duplicate_source_identity",
        None,
    );
    let first_root = root.join("a-src");
    let second_root = root.join("z-src");
    let first_app = first_root.join("app");
    let second_app = second_root.join("app");
    std::fs::create_dir_all(&first_app).expect("create first package app source root");
    std::fs::create_dir_all(&second_app).expect("create second package app source root");

    let source = r#"
module app::main;

fn main() {
    return 0;
}
"#;
    let first_entry = first_app.join("main.lani");
    let second_entry = second_app.join("main.lani");
    std::fs::write(&first_entry, source).expect("write first package entry source");
    std::fs::write(&second_entry, source).expect("write duplicate package module source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-source-identity",
  "roots": ["a-src", "z-src"],
  "entry": "a-src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with source identity");

    let canonical_first = std::fs::canonicalize(&first_entry)
        .expect("canonicalize first package entry")
        .display()
        .to_string();
    let canonical_second = std::fs::canonicalize(&second_entry)
        .expect("canonicalize duplicate package source")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");

    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source inputs");
    let mut duplicate_input = input_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_first))
        .expect("generated lockfile should include the first entry input")
        .clone();
    duplicate_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(canonical_second.clone()),
        );
    input_files.push(duplicate_input);

    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source identities");
    let mut duplicate_identity = source_identity_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_first))
        .expect("generated lockfile should include the first entry source identity")
        .clone();
    let duplicate_identity_fields = duplicate_identity
        .as_object_mut()
        .expect("source identity entry should be an object");
    duplicate_identity_fields.insert(
        "path".to_string(),
        serde_json::Value::String(canonical_second),
    );
    duplicate_identity_fields.insert("source_root_index".to_string(), serde_json::Value::from(1));
    duplicate_identity_fields.insert(
        "source_root_relative_path".to_string(),
        serde_json::Value::String("app/main.lani".to_string()),
    );
    source_identity_files.push(duplicate_identity);

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("one package library should not assign one module identity to two files");
    assert_duplicate_source_identity_module_error(&err, "app::main");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_duplicate_module_declarations_that_share_one_identity() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "duplicate_module_metadata",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let first_path = app_root.join("first.lani");
    std::fs::write(
        &first_path,
        r#"
module app::same;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write first duplicate-module source");

    let second_path = app_root.join("second.lani");
    std::fs::write(
        &second_path,
        r#"
module app::same;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write second duplicate-module source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::first;
import app::second;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-module-metadata",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let err = lockfile.to_json_pretty().expect_err(
        "lockfiles should reject duplicate declared module identities across source files",
    );
    assert_duplicate_source_identity_module_error(&err, "app::same");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_requires_import_graph_and_input_identity() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "required_lock_sections", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "required-lock-sections",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize complete package lockfile");

    let missing_import_graph = remove_lockfile_section(&lockfile_json, "import_graph");
    let err = PackageLockfile::parse_json(&missing_import_graph)
        .expect_err("lockfile without an import graph should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("missing import graph"),
        "expected missing import graph error, got {message}"
    );

    let missing_inputs = remove_lockfile_section(&lockfile_json, "inputs");
    let err = PackageLockfile::parse_json(&missing_inputs)
        .expect_err("lockfile without input identity should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("missing input identity"),
        "expected missing input identity error, got {message}"
    );

    let missing_source_identities = remove_lockfile_section(&lockfile_json, "source_identities");
    let err = PackageLockfile::parse_json(&missing_source_identities)
        .expect_err("lockfile without source identities should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("missing source identities"),
        "expected missing source identities error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_public_serialize_emits_integrity_sections_that_deserialize() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "serialize_integrity", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "serialize-integrity");
    let lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated lockfile");

    let document =
        serde_json::to_value(&lockfile).expect("public serialization should write a lockfile");
    let input_files = document
        .get("inputs")
        .and_then(|inputs| inputs.get("files"))
        .and_then(|files| files.as_array())
        .expect("public serialization should include input identity files");
    assert_eq!(
        input_files.len(),
        1,
        "minimal fixture should persist exactly the entry source input"
    );
    let source_identity_files = document
        .get("source_identities")
        .and_then(|identities| identities.get("files"))
        .and_then(|files| files.as_array())
        .expect("public serialization should include source identity files");
    assert_eq!(
        source_identity_files.len(),
        input_files.len(),
        "source identities should describe the same source file set as input identity"
    );
    let imports = document
        .get("import_graph")
        .and_then(|graph| graph.get("imports"))
        .and_then(|imports| imports.as_array())
        .expect("public serialization should include an import graph section");
    assert!(
        imports.is_empty(),
        "minimal fixture should persist an empty import graph, not omit the section"
    );

    serde_json::from_value::<PackageLockfile>(document)
        .expect("publicly serialized lockfile should pass public deserialization");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_public_deserialize_enforces_integrity_sections() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "deserialize_integrity", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "deserialize-integrity");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");

    serde_json::from_str::<PackageLockfile>(&lockfile_json)
        .expect("public lockfile deserialization should accept complete lockfiles");

    let missing_import_graph = remove_lockfile_section(&lockfile_json, "import_graph");
    let err = serde_json::from_str::<PackageLockfile>(&missing_import_graph)
        .expect_err("public lockfile deserialization should reject missing import graphs");
    let message = err.to_string();
    assert!(
        message.contains("missing import graph"),
        "expected public deserialization error to require import graph, got {message}"
    );

    let missing_inputs = remove_lockfile_section(&lockfile_json, "inputs");
    let err = serde_json::from_str::<PackageLockfile>(&missing_inputs)
        .expect_err("public lockfile deserialization should reject missing input identity");
    let message = err.to_string();
    assert!(
        message.contains("missing input identity"),
        "expected public deserialization error to require input identity, got {message}"
    );

    let missing_source_identities = remove_lockfile_section(&lockfile_json, "source_identities");
    let err = serde_json::from_str::<PackageLockfile>(&missing_source_identities)
        .expect_err("public lockfile deserialization should reject missing source identities");
    let message = err.to_string();
    assert!(
        message.contains("missing source identities"),
        "expected public deserialization error to require source identities, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_requires_integrity_sections_before_live_source_paths() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "missing_integrity_before_live_source",
        None,
    );
    let (src_root, _, lockfile_path) =
        write_minimal_generated_lockfile(&root, "missing-integrity-before-live-source");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    std::fs::remove_dir_all(&src_root).expect("remove live package source root");

    for (section, expected_message) in [
        ("import_graph", "missing import graph"),
        ("inputs", "missing input identity"),
        ("source_identities", "missing source identities"),
    ] {
        let missing_section = remove_lockfile_section(&lockfile_json, section);
        let err = PackageLockfile::parse_json(&missing_section)
            .expect_err("lockfile without required integrity section should be rejected");
        let message = format!("{err:?}");
        assert!(
            message.contains(expected_message),
            "expected {expected_message:?} before live source validation, got {message}"
        );
        assert!(
            !message.contains("no longer resolves") && !message.contains("read entry"),
            "missing integrity sections should fail before stale source paths are loaded, got {message}"
        );
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_requires_integrity_sections_before_optional_artifacts() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "missing_integrity_before_artifacts",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "missing-integrity-before-artifacts");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let artifact_path = std::fs::canonicalize(&entry_path).expect("canonicalize artifact fixture");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "artifacts".to_string(),
            serde_json::json!({
                "digest_algorithm": "lanius-fnv1a64-v1",
                "files": [{
                    "target": ":not-a-target",
                    "kind": "final-output",
                    "path": artifact_path.display().to_string(),
                    "byte_len": 0,
                    "digest": "fnv1a64:0000000000000000"
                }]
            }),
        );
    let malformed_artifact_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize malformed artifact lockfile");
    let err = PackageLockfile::parse_json(&malformed_artifact_lockfile_json)
        .expect_err("malformed optional artifact metadata should still be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact target") && message.contains(":not-a-target"),
        "expected malformed optional artifact metadata error, got {message}"
    );

    for (section, expected_message) in [
        ("import_graph", "missing import graph"),
        ("inputs", "missing input identity"),
        ("source_identities", "missing source identities"),
    ] {
        let missing_section = remove_lockfile_section(&malformed_artifact_lockfile_json, section);
        let err = PackageLockfile::parse_json(&missing_section)
            .expect_err("missing replay integrity should be rejected before optional artifacts");
        let message = format!("{err:?}");
        assert!(
            message.contains(expected_message),
            "expected {expected_message:?} before optional artifact validation, got {message}"
        );
        assert!(
            !message.contains("artifact target") && !message.contains(":not-a-target"),
            "optional produced artifacts should not mask missing replay integrity, got {message}"
        );
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_requires_integrity_shape_before_optional_artifacts_and_live_source_paths() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "malformed_integrity_before_artifacts_and_live_source",
        None,
    );
    let (src_root, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "malformed-integrity-before-artifacts");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "artifacts".to_string(),
            serde_json::json!({
                "digest_algorithm": "lanius-fnv1a64-v1",
                "files": [{
                    "target": ":not-a-target",
                    "kind": "final-output",
                    "path": canonical_entry,
                    "byte_len": 0,
                    "digest": "fnv1a64:0000000000000000"
                }]
            }),
        );
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source inputs");
    let entry_input = input_files
        .first_mut()
        .expect("generated lockfile should include an input identity");
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "digest".to_string(),
            serde_json::Value::String("not-a-digest".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");

    let mut source_identity_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    source_identity_document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "artifacts".to_string(),
            serde_json::json!({
                "digest_algorithm": "lanius-fnv1a64-v1",
                "files": [{
                    "target": ":not-a-target",
                    "kind": "final-output",
                    "path": canonical_entry.clone(),
                    "byte_len": 0,
                    "digest": "fnv1a64:0000000000000000"
                }]
            }),
        );
    let source_identity_files = source_identity_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source identities");
    let entry_source_identity = source_identity_files
        .first_mut()
        .expect("generated lockfile should include an entry source identity");
    entry_source_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("app::".to_string()),
        );
    let tampered_source_identity_json = serde_json::to_string_pretty(&source_identity_document)
        .expect("serialize tampered source identity lockfile");

    let mut import_graph_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    import_graph_document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "artifacts".to_string(),
            serde_json::json!({
                "digest_algorithm": "lanius-fnv1a64-v1",
                "files": [{
                    "target": ":not-a-target",
                    "kind": "final-output",
                    "path": canonical_entry,
                    "byte_len": 0,
                    "digest": "fnv1a64:0000000000000000"
                }]
            }),
        );
    import_graph_document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("library_dependencies"))
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies")
        .push(serde_json::json!({
            "library_id": 3,
            "depends_on_library_id": 1
        }));
    let tampered_import_graph_json = serde_json::to_string_pretty(&import_graph_document)
        .expect("serialize tampered import graph lockfile");

    std::fs::remove_dir_all(&src_root).expect("remove live package source root");

    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "malformed replay integrity should be rejected before artifacts or live source paths",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("input file") && message.contains("invalid digest"),
        "expected malformed input identity error before optional artifacts or live source validation, got {message}"
    );
    assert!(
        !message.contains("artifact target")
            && !message.contains(":not-a-target")
            && !message.contains("no longer resolves")
            && !message.contains("read entry"),
        "optional artifacts and live source paths must not mask malformed replay integrity, got {message}"
    );

    let err = PackageLockfile::parse_json(&tampered_source_identity_json).expect_err(
        "malformed source identity shape should be rejected before artifacts or live source paths",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity file") && message.contains("invalid module path"),
        "expected malformed source identity shape before optional artifacts or live source validation, got {message}"
    );
    assert!(
        !message.contains("artifact target")
            && !message.contains(":not-a-target")
            && !message.contains("no longer resolves")
            && !message.contains("read entry"),
        "optional artifacts and live source paths must not mask malformed source identity metadata, got {message}"
    );

    let err = PackageLockfile::parse_json(&tampered_import_graph_json).expect_err(
        "malformed import graph shape should be rejected before artifacts or live source paths",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph library dependency source")
            && message.contains("library 3")
            && message.contains("unsupported"),
        "expected malformed import graph shape before optional artifacts or live source validation, got {message}"
    );
    assert!(
        !message.contains("artifact target")
            && !message.contains(":not-a-target")
            && !message.contains("no longer resolves")
            && !message.contains("read entry"),
        "optional artifacts and live source paths must not mask malformed import graph metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stale_input_identity_before_optional_artifact_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stale_input_before_artifact_metadata",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "stale-input-before-artifacts");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "artifacts".to_string(),
            serde_json::json!({
                "digest_algorithm": "lanius-fnv1a64-v1",
                "files": [{
                    "target": ":not-a-target",
                    "kind": "final-output",
                    "path": canonical_entry,
                    "byte_len": 0,
                    "digest": "fnv1a64:0000000000000000"
                }]
            }),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");

    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 1;
}
"#,
    )
    .expect("mutate package entry source after lockfile generation");

    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("stale package inputs should fail before optional produced artifact metadata");
    let message = format!("{err:?}");
    assert!(
        message.contains("input")
            && message.contains("mismatch")
            && message.contains(&entry_path.display().to_string()),
        "expected stale input identity error before optional artifacts, got {message}"
    );
    assert!(
        !message.contains("artifact target") && !message.contains(":not-a-target"),
        "optional produced artifacts should not mask stale source input identity, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_tampered_source_identity_before_stale_input_digest() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stale_input_before_source_identity_metadata",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "stale-input-before-source-identity");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source identities");
    let entry_source_identity = source_identity_files
        .iter_mut()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include entry source identity");
    entry_source_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("app::tampered".to_string()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");

    let source = std::fs::read_to_string(&entry_path).expect("read package entry source");
    std::fs::write(&entry_path, source.replace("return 0;", "return 1;"))
        .expect("mutate package entry source without changing replay shape");

    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "tampered source identity metadata should fail before generic stale input bytes",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity file")
            && message.contains("app::tampered")
            && message.contains("source-root relative path")
            && message.contains("app::main"),
        "expected source identity ownership error before stale input digest, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch"),
        "generic stale input digest should not mask tampered source identity metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_requires_integrity_sections_to_cover_entry_source() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "entry_integrity", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "entry-integrity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with entry identity");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();

    let mut missing_input =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    missing_input
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist input files")
        .retain(|file| {
            file.get("path").and_then(|path| path.as_str()) != Some(canonical_entry.as_str())
        });
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&missing_input).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile input identity must include the package entry");
    let message = format!("{err:?}");
    assert!(
        message.contains("entry")
            && message.contains(&canonical_entry)
            && message.contains("missing from input identity"),
        "expected entry input-identity membership error, got {message}"
    );

    let mut missing_source_identity =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    missing_source_identity
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source identity files")
        .retain(|file| {
            file.get("path").and_then(|path| path.as_str()) != Some(canonical_entry.as_str())
        });
    let tampered_lockfile_json = serde_json::to_string_pretty(&missing_source_identity)
        .expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile source identities must include the package entry");
    let message = format!("{err:?}");
    assert!(
        message.contains("entry")
            && message.contains(&canonical_entry)
            && message.contains("missing from source identities"),
        "expected entry source-identity membership error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_input_identity_with_wrong_library_root() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "input_library_root", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "input-library-root");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let entry_input = input_files
        .iter_mut()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include the entry input");
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert("library_id".to_string(), serde_json::Value::from(0));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile inputs should belong to their declared roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains("stdlib library 0")
            && message.contains("no stdlib root"),
        "expected input library ownership error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_edge_with_wrong_library_root() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_library_root", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    let stdlib_root = root.join("stdlib");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create package stdlib root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-library-root",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let import_graph = document
        .get_mut("import_graph")
        .and_then(|graph| graph.as_object_mut())
        .expect("generated lockfile should persist an import graph object");
    import_graph
        .get_mut("library_dependencies")
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies")
        .push(serde_json::json!({
            "library_id": 1,
            "depends_on_library_id": 0
        }));
    let import_edges = import_graph
        .get_mut("imports")
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges");
    let helper_edge = import_edges
        .iter_mut()
        .find(|edge| {
            edge.get("target_path").and_then(|path| path.as_str())
                == Some(canonical_helper.as_str())
        })
        .expect("generated lockfile should include helper import edge");
    helper_edge
        .as_object_mut()
        .expect("import graph edge should be an object")
        .insert("target_library_id".to_string(), serde_json::Value::from(0));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph edges should belong to their declared roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("target file")
            && message.contains("stdlib library 0")
            && message.contains("not under resolved stdlib root"),
        "expected import graph library ownership error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[cfg(unix)]
#[test]
fn package_loaders_reject_import_aliases_that_do_not_match_declared_modules() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "duplicate_alias", None);
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 8;
}
"#,
    )
    .expect("write package helper source");
    std::os::unix::fs::symlink(&app_root, src_root.join("alias"))
        .expect("create package import alias");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;
import alias::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-alias",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved
        .load_path_manifest()
        .expect_err("package manifest path loading should reject import aliases that target a different declared module");
    assert_import_path_module_mismatch_error(&err, "alias::helper", "app::helper");

    let err = lockfile
        .load_source_pack()
        .expect_err("package lockfile source loading should reject import aliases that target a different declared module");
    assert_import_path_module_mismatch_error(&err, "alias::helper", "app::helper");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject import aliases that target a different declared module");
    assert_import_path_module_mismatch_error(&err, "alias::helper", "app::helper");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_records_and_validates_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_graph", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package leaf source");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

import app::leaf;

pub fn value() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-graph",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    let lockfile_document = serde_json::from_str::<serde_json::Value>(&lockfile_json)
        .expect("parse generated lockfile with import graph");
    let import_edges = lockfile_document
        .get("import_graph")
        .and_then(|import_graph| import_graph.get("imports"))
        .and_then(|imports| imports.as_array())
        .expect("lockfile JSON should persist the discovered import graph");
    assert!(
        import_edges.iter().any(|edge| {
            edge.get("import_path").and_then(|path| path.as_str()) == Some("app::helper")
        }) && import_edges.iter().any(|edge| {
            edge.get("import_path").and_then(|path| path.as_str()) == Some("app::leaf")
        }),
        "lockfile JSON should record declared import paths rather than deriving module identity from file paths"
    );
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::helper",
        "app::leaf",
        1,
        "app::leaf",
    );

    PackageLockfile::parse_json(&lockfile_json)
        .expect("unchanged lockfile import graph should validate");

    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 5;
}
"#,
    )
    .expect("mutate helper import graph");
    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("stale package lockfile should reject changed import graph");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed"),
        "expected stale lockfile error to mention import graph change, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_path_that_disagrees_with_target_module() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_target_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-target-module",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    mutable_import_edge(&mut document, "app::helper").insert(
        "import_path".to_string(),
        serde_json::Value::String("app::renamed".to_string()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "persisted package imports must resolve by the target's declared module identity",
    );
    assert_import_path_module_mismatch_error(&err, "app::renamed", "app::helper");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_changed_import_path_with_source_context() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "changed_import_path", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("old.lani"),
        r#"
module app::old;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write original imported module");
    std::fs::write(
        app_root.join("new.lani"),
        r#"
module app::new;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write replacement imported module");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::old;

fn main() {
    return app::old::VALUE;
}
"#,
    )
    .expect("write package entry with original import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "changed-import-path",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with original import graph");

    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::new;

fn main() {
    return app::new::VALUE;
}
"#,
    )
    .expect("rewrite package entry with changed import");

    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("stale package lockfile should identify changed import paths");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("source import path changed from app::old to app::new")
            && message.contains("persisted edge")
            && message.contains("live source-root replay")
            && message.contains(entry_path.display().to_string().as_str())
            && message.contains("regenerate the package lockfile"),
        "expected changed import-path replay diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_moved_import_source_module_with_context() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "moved_import_source", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub const VALUE: i32 = 3;
"#,
    )
    .expect("write imported leaf module");

    let carrier_path = app_root.join("zcarrier.lani");
    std::fs::write(
        &carrier_path,
        r#"
module app::zcarrier;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write original carrier module without nested imports");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::leaf;
import app::zcarrier;

fn main() {
    return app::leaf::VALUE + app::zcarrier::value();
}
"#,
    )
    .expect("write entry that owns the leaf import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "moved-import-source",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with original source-owned import graph");

    std::fs::write(
        &carrier_path,
        r#"
module app::zcarrier;

import app::leaf;

pub fn value() -> i32 {
    return app::leaf::VALUE;
}
"#,
    )
    .expect("move leaf import into carrier module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::zcarrier;

fn main() {
    return app::zcarrier::value();
}
"#,
    )
    .expect("remove leaf import from entry while keeping carrier reachable");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale package lockfile should identify the source module that moved an import",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("source changed for import app::leaf")
            && message.contains(entry_path.display().to_string().as_str())
            && message.contains("module app::main")
            && message.contains(carrier_path.display().to_string().as_str())
            && message.contains("module app::zcarrier")
            && message.contains("live source-root replay")
            && message.contains("regenerate the package lockfile"),
        "expected moved import-source replay diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_moved_import_target_before_generic_count_change() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "moved_import_target", None);
    let primary_app_root = root.join("src_primary").join("app");
    let shadow_app_root = root.join("src_shadow").join("app");
    std::fs::create_dir_all(&primary_app_root).expect("create primary package app source root");
    std::fs::create_dir_all(&shadow_app_root).expect("create shadow package app source root");

    let primary_helper_path = primary_app_root.join("helper.lani");
    std::fs::write(
        &primary_helper_path,
        r#"
module app::helper;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write original helper module in primary root");

    let entry_path = primary_app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::VALUE;
}
"#,
    )
    .expect("write package entry with original helper import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "moved-import-target",
  "roots": ["src_primary", "src_shadow"],
  "entry": "src_primary/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with original target import graph");
    let original_helper = std::fs::canonicalize(&primary_helper_path)
        .expect("canonicalize original helper")
        .display()
        .to_string();

    std::fs::remove_file(&primary_helper_path).expect("remove original helper module");
    let shadow_helper_path = shadow_app_root.join("helper.lani");
    std::fs::write(
        &shadow_helper_path,
        r#"
module app::helper;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write replacement helper module in later source root");
    let replacement_helper = std::fs::canonicalize(&shadow_helper_path)
        .expect("canonicalize replacement helper")
        .display()
        .to_string();
    std::fs::write(
        primary_app_root.join("leaf.lani"),
        r#"
module app::leaf;

pub const VALUE: i32 = 3;
"#,
    )
    .expect("write newly imported leaf module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;
import app::leaf;

fn main() {
    return app::helper::VALUE + app::leaf::VALUE;
}
"#,
    )
    .expect("rewrite package entry with moved target and one extra import");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale package lockfile should identify the import target that moved before reporting a generic count mismatch",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("target changed for import app::helper")
            && message.contains(original_helper.as_str())
            && message.contains(replacement_helper.as_str())
            && message.contains("live source-root replay")
            && message.contains("regenerate the package lockfile"),
        "expected moved import-target replay diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_non_leading_imports_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "late_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn before_import() -> i32 {
    return 0;
}

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with non-leading import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "late-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfiles should not persist incomplete import graph edges");
    let message = format!("{err:?}");
    assert!(
        message.contains("unsupported import form")
            && message.contains("imports must appear before other items")
            && message.contains("package replay metadata stays complete")
            && message.contains("main.lani"),
        "expected non-leading import discovery error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_imports_before_module_identity_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_before_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
import app::helper;

module app::main;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with import before module identity");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-before-module",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfiles should not persist imports before the source module identity exists",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("import-before-module diagnostic should carry a source label");
            assert_eq!(label.path, std::fs::canonicalize(&entry_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some("import app::helper;"));
            assert_eq!(
                label.message,
                "imports must follow a leading module declaration"
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("source module identity")),
                "expected module-identity ordering note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("source module identity")),
                "expected source module-identity boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned import-before-module diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_quoted_imports_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "quoted_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import "app/helper.lani";

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with quoted import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "quoted-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved
        .load_path_manifest()
        .expect_err("source-root package replay should reject unsupported quoted imports");
    assert_unsupported_quoted_import_form_error(&err);

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfiles should not persist incomplete quoted-import metadata");
    assert_unsupported_quoted_import_form_error(&err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_path_separator_imports_before_path_normalization() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "path_separator_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app/helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with a path-shaped import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "path-separator-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_path_manifest().expect_err(
        "package source-root replay should reject filesystem-style import paths before normalization",
    );
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app/helper;",
        "filesystem path separators",
    );

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile path replay should reject filesystem-style import paths before normalization",
    );
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app/helper;",
        "filesystem path separators",
    );

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should not persist path-shaped import metadata");
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app/helper;",
        "filesystem path separators",
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_dotted_package_imports_before_module_normalization() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "dotted_package_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app.helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with a dotted package-name import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "dotted-package-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_path_manifest().expect_err(
        "package source-root replay should reject package-name-shaped imports before normalization",
    );
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app.helper;",
        "package-name separators",
    );

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile replay should reject package-name-shaped imports before normalization",
    );
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app.helper;",
        "package-name separators",
    );

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should not persist dotted package-name import metadata",
    );
    assert_source_spanned_import_path_separator_error(
        &err,
        &entry_path,
        "import app.helper;",
        "package-name separators",
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_aliases_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_alias", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper as helper;

fn main() {
    return helper::value();
}
"#,
    )
    .expect("write package entry source with aliased import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-alias",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfiles should reject aliased imports before persisting import graph metadata",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unsupported import alias diagnostic should carry a source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("import app::helper as helper;")
            );
            assert_eq!(
                label.message,
                "import aliases are not supported by package replay"
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("parsed module/import records")),
                "expected package replay alias boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned unsupported import diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_glob_imports_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_glob", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::*;

fn main() {
    return helper::value();
}
"#,
    )
    .expect("write package entry source with a glob import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-glob",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_path_manifest().expect_err(
        "package source-root replay should reject glob imports before returning a path manifest",
    );
    assert_source_spanned_import_glob_error(&err, &entry_path);

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile replay should reject glob imports before returning a path manifest",
    );
    assert_source_spanned_import_glob_error(&err, &entry_path);

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfiles should reject glob imports before persisting import graph metadata",
    );
    assert_source_spanned_import_glob_error(&err, &entry_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_span_for_import_missing_semicolon_before_items() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "import_missing_semicolon", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with unterminated import declaration");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-missing-semicolon",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfiles should reject malformed import declarations before persisting import graph metadata");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("missing import semicolon diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("fn main() {"));
            assert_eq!(label.message, "expected ';' after import path");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("leading module/import metadata")),
                "expected package replay boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => {
            panic!("expected source-spanned missing import semicolon diagnostic, got {other:?}")
        }
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_unterminated_block_comments_during_source_root_replay() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "unterminated_comment", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

/* import app::helper;
fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with unterminated block comment");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "unterminated-comment",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_path_manifest().expect_err(
        "package manifest source-root replay should reject malformed comments before returning a path manifest",
    );
    assert_unterminated_source_replay_comment_error(&err);

    let err = lockfile.load_path_manifest().expect_err(
        "source-root replay should reject malformed comments before returning a path manifest",
    );
    assert_unterminated_source_replay_comment_error(&err);

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject malformed source-root replay");
    assert_unterminated_source_replay_comment_error(&err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_replay_does_not_treat_char_literal_text_as_import_metadata() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "char_literal_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    let token = 'import app::helper;';
    return 0;
}
"#,
    )
    .expect("write package entry source with import text inside a character literal");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "char-literal-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let path_manifest = lockfile
        .load_path_manifest()
        .expect("source-root replay should ignore import-looking text inside literals");
    assert_eq!(
        path_manifest.files.len(),
        1,
        "literal text must not create package import graph edges"
    );
    lockfile
        .to_json_pretty()
        .expect("lockfile generation should not interpret character literal text as imports");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn source_root_path_manifest_rejects_multiline_literals_before_returning_import_set() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "source_root_literal", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    let hidden = "unterminated
import app::helper;
";
    return 0;
}
"#,
    )
    .expect("write entry source with malformed multiline string literal");

    let err = load_entry_path_manifest_with_source_root(&entry_path, root.join("src"))
        .expect_err("source-root path manifests must reject malformed literals before returning an incomplete import set");
    assert_malformed_source_replay_literal_error(&err, "string literal");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_multiline_string_literals_during_source_root_replay() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "multiline_string", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    let hidden = "unterminated
import app::helper;
";
    return 0;
}
"#,
    )
    .expect("write package entry source with malformed multiline string literal");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "multiline-string",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "source-root replay should reject malformed string literals before returning a path manifest",
    );
    assert_malformed_source_replay_literal_error(&err, "string literal");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject malformed source-root literals");
    assert_malformed_source_replay_literal_error(&err, "string literal");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_escaped_newline_string_literals_during_source_root_replay() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "escaped_newline_string", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    let hidden = "unterminated\
import app::helper;
";
    return 0;
}
"#,
    )
    .expect("write package entry source with escaped-newline malformed string literal");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "escaped-newline-string",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "source-root replay should reject escaped-newline string literals before returning a path manifest",
    );
    assert_malformed_source_replay_literal_error(&err, "string literal");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should reject escaped-newline literals");
    assert_malformed_source_replay_literal_error(&err, "string literal");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_live_source_self_import_before_persisting_import_graph() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "live_self_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with a self import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "live-self-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile replay should reject source self-imports before returning a path manifest",
    );
    assert_source_spanned_self_import_error(&err, &entry_path, "app::main");

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should not persist source self-import edges");
    assert_source_spanned_self_import_error(&err, &entry_path, "app::main");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_source_root_self_import_cycles() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "self_import", None);
    let (_, entry_path, lockfile_path) = write_minimal_generated_lockfile(&root, "self-import");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 1,
            "source_path": canonical_entry.clone(),
            "source_module_path": "app::main",
            "import_path": "app::other",
            "target_library_id": 1,
            "target_path": canonical_entry,
            "target_module_path": "app::other"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("package lockfiles should reject persisted source-root self-import cycles");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph self-cycle")
            && message.contains("app::other")
            && message.contains("imports its own module"),
        "expected package self-import diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_semantic_self_import_cycles() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "semantic_self_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "semantic-self-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 1,
            "source_path": canonical_entry,
            "source_module_path": "app::main",
            "import_path": "app::main",
            "target_library_id": 1,
            "target_path": canonical_helper,
            "target_module_path": "app::helper"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("package lockfiles should reject semantic import cycles");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph semantic self-cycle")
            && message.contains("app::main")
            && message.contains("imports its own module path"),
        "expected package semantic self-import diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_preserves_two_module_import_edges_as_metadata() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "two_module_cycle", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;
import app::main;

pub const VALUE: i32 = 7;
"#,
    )
    .expect("write cyclic helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;
import app::helper;

fn main() {
    return app::helper::VALUE;
}
"#,
    )
    .expect("write cyclic package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "two-module-cycle",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let path_manifest = resolved
        .load_path_manifest()
        .expect("package manifest path replay should preserve direct reverse import edges");
    assert_eq!(
        path_manifest.files.len(),
        2,
        "cyclic import metadata should load each source file once"
    );

    let path_manifest = lockfile
        .load_path_manifest()
        .expect("package lockfile path replay should preserve direct reverse import edges");
    assert_eq!(
        path_manifest.files.len(),
        2,
        "cyclic import metadata should load each source file once"
    );

    let source_pack = lockfile
        .load_source_pack()
        .expect("package lockfile source replay should preserve direct reverse import edges");
    assert_eq!(
        source_pack.sources.len(),
        2,
        "cyclic import metadata should load each source file once for source replay"
    );

    let lockfile_json = lockfile.to_json_pretty().expect(
        "package lockfile generation should persist direct reverse import edges as replay metadata",
    );
    let lockfile_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::main",
        "app::helper",
        1,
        "app::helper",
    );
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::helper",
        "app::main",
        1,
        "app::main",
    );

    let reparsed = PackageLockfile::parse_json(&lockfile_json)
        .expect("package lockfile replay should accept direct reverse import metadata");
    reparsed
        .load_path_manifest()
        .expect("replayed lockfile should preserve direct reverse import metadata");
    reparsed
        .load_source_pack()
        .expect("replayed lockfile source replay should preserve direct reverse import metadata");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_preserves_longer_import_cycles_as_replay_metadata() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "long_import_cycle", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("leaf.lani"),
        r#"
module app::leaf;
import app::main;

pub const VALUE: i32 = 7;
"#,
    )
    .expect("write cyclic leaf source");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;
import app::leaf;

pub const VALUE: i32 = app::leaf::VALUE;
"#,
    )
    .expect("write cyclic helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;
import app::helper;

fn main() {
    return app::helper::VALUE;
}
"#,
    )
    .expect("write cyclic package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "long-import-cycle",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let path_manifest = resolved
        .load_path_manifest()
        .expect("package manifest path replay should preserve longer import cycles as metadata");
    assert_eq!(
        path_manifest.files.len(),
        3,
        "cyclic source-root discovery should load each reachable file once"
    );

    let path_manifest = lockfile
        .load_path_manifest()
        .expect("package lockfile path replay should preserve longer import cycles as metadata");
    assert_eq!(
        path_manifest.files.len(),
        3,
        "cyclic lockfile replay should load each reachable file once"
    );

    let source_pack = lockfile
        .load_source_pack()
        .expect("package lockfile source replay should preserve longer import cycle metadata");
    assert_eq!(
        source_pack.sources.len(),
        3,
        "cyclic replay metadata should not duplicate source files"
    );

    let lockfile_json = lockfile.to_json_pretty().expect(
        "package lockfile generation should persist longer import cycles as replay metadata",
    );
    let lockfile_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::main",
        "app::helper",
        1,
        "app::helper",
    );
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::helper",
        "app::leaf",
        1,
        "app::leaf",
    );
    assert_import_graph_edge(
        &lockfile_document,
        1,
        "app::leaf",
        "app::main",
        1,
        "app::main",
    );

    let reparsed = PackageLockfile::parse_json(&lockfile_json)
        .expect("package lockfile replay should accept longer import-cycle metadata");
    reparsed
        .load_path_manifest()
        .expect("replayed lockfile should preserve longer import-cycle metadata");
    reparsed
        .load_source_pack()
        .expect("replayed lockfile source replay should preserve longer import-cycle metadata");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_module_endpoints_not_declared_by_source_identities() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "import_endpoint_identity", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-endpoint-identity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import endpoint identities");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated lockfile endpoint identities should validate");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let helper_edge = document
        .get("import_graph")
        .and_then(|graph| graph.get("imports"))
        .and_then(|imports| imports.as_array())
        .and_then(|imports| {
            imports.iter().find(|edge| {
                edge.get("source_path").and_then(|path| path.as_str())
                    == Some(canonical_entry.as_str())
                    && edge.get("target_path").and_then(|path| path.as_str())
                        == Some(canonical_helper.as_str())
                    && edge.get("import_path").and_then(|path| path.as_str()) == Some("app::helper")
            })
        })
        .expect("lockfile JSON should persist the helper import edge");
    assert_eq!(
        helper_edge
            .get("source_module_path")
            .and_then(|path| path.as_str()),
        Some("app::main")
    );
    assert_eq!(
        helper_edge
            .get("target_module_path")
            .and_then(|path| path.as_str()),
        Some("app::helper")
    );

    let mut missing_source_endpoint = document.clone();
    mutable_import_edge(&mut missing_source_endpoint, "app::helper")
        .remove("source_module_path")
        .expect("fixture import edge should persist source endpoint metadata");
    let tampered_lockfile_json = serde_json::to_string_pretty(&missing_source_endpoint)
        .expect("serialize missing source endpoint");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph source endpoint module path is required");
    assert_missing_import_graph_endpoint_field_error(&err, "source_module_path");

    let mut missing_target_endpoint = document.clone();
    mutable_import_edge(&mut missing_target_endpoint, "app::helper")
        .remove("target_module_path")
        .expect("fixture import edge should persist target endpoint metadata");
    let tampered_lockfile_json = serde_json::to_string_pretty(&missing_target_endpoint)
        .expect("serialize missing target endpoint");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph target endpoint module path is required");
    assert_missing_import_graph_endpoint_field_error(&err, "target_module_path");

    let mut tampered_target = document.clone();
    let helper_edge = mutable_import_edge(&mut tampered_target, "app::helper");
    helper_edge.insert(
        "import_path".to_string(),
        serde_json::Value::String("app::renamed".to_string()),
    );
    helper_edge.insert(
        "target_module_path".to_string(),
        serde_json::Value::String("app::renamed".to_string()),
    );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_target).expect("serialize tampered target endpoint");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph target endpoint should match persisted source identity");
    assert_import_graph_module_endpoint_error(&err, "target", "app::renamed", "app::helper");

    let mut tampered_source = document;
    let helper_edge = mutable_import_edge(&mut tampered_source, "app::helper");
    helper_edge.insert(
        "source_module_path".to_string(),
        serde_json::Value::String("app::renamed".to_string()),
    );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_source).expect("serialize tampered source endpoint");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph source endpoint should match persisted source identity");
    assert_import_graph_module_endpoint_error(&err, "source", "app::renamed", "app::main");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_source_identity_without_module_path() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "missing_module_path", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write package helper source without module declaration");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "missing-module-path",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfiles should require module path metadata for every source identity",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("missing module diagnostic should carry a source label");
            assert_eq!(label.path, std::fs::canonicalize(&helper_path).unwrap());
            assert_eq!(
                label.source_line.as_deref(),
                Some("pub fn value() -> i32 {")
            );
            assert_eq!(label.message, "expected leading module declaration");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("app/helper.lani") && note.contains("app::helper")),
                "expected missing module diagnostic to name the expected module path, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned missing module diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_package_name_as_source_identity_module_path() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "package_as_module", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "control.plane",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with source identities");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| {
            files.iter_mut().find(|file| {
                file.get("path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
            })
        })
        .expect("generated lockfile should include entry source identity");
    source_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("control::plane".to_string()),
        );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("package lockfiles must not accept package metadata as source module identity");
    let message = format!("{err:?}");
    assert!(
        message.contains("package metadata")
            && message.contains("control.plane")
            && message.contains("control::plane")
            && message.contains("control-plane identity")
            && message.contains("source module declarations"),
        "expected package/source identity boundary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_replay_does_not_resolve_missing_imports_from_package_name_metadata() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "package_import_metadata", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import control::plane;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with package-name-shaped import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "control.plane",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved
        .load_path_manifest()
        .expect_err("package manifest replay must not satisfy imports from package-name metadata");
    assert_missing_import_does_not_use_package_metadata(&err, "control::plane", &entry_path);

    let err = lockfile
        .load_path_manifest()
        .expect_err("package lockfile replay must not satisfy imports from package-name metadata");
    assert_missing_import_does_not_use_package_metadata(&err, "control::plane", &entry_path);

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation must not persist package-name metadata as import evidence",
    );
    assert_missing_import_does_not_use_package_metadata(&err, "control::plane", &entry_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_and_lockfile_reject_ambiguous_source_root_import_candidates() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "ambiguous_roots", None);
    let source_root_a = root.join("src_a");
    let source_root_b = root.join("src_b");
    let app_root = source_root_a.join("app");
    let shared_root_a = source_root_a.join("shared");
    let shared_root_b = source_root_b.join("shared");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&shared_root_a).expect("create first shared source root");
    std::fs::create_dir_all(&shared_root_b).expect("create second shared source root");

    let helper_a = shared_root_a.join("helper.lani");
    std::fs::write(
        &helper_a,
        r#"
module shared::helper;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write first shared helper candidate");
    let helper_b = shared_root_b.join("helper.lani");
    std::fs::write(
        &helper_b,
        r#"
module shared::helper;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write second shared helper candidate");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import shared::helper;

fn main() {
    return shared::helper::VALUE;
}
"#,
    )
    .expect("write package entry with ambiguous import candidate");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "ambiguous-roots",
  "roots": ["src_a", "src_b"],
  "entry": "src_a/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_path_manifest().expect_err(
        "package manifest replay should reject imports with multiple source-root candidates",
    );
    assert_ambiguous_source_root_import_error(&err, "shared::helper", &[&helper_a, &helper_b]);

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile replay should reject imports with multiple source-root candidates",
    );
    assert_ambiguous_source_root_import_error(&err, "shared::helper", &[&helper_a, &helper_b]);

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile generation should not persist ambiguous import candidates");
    assert_ambiguous_source_root_import_error(&err, "shared::helper", &[&helper_a, &helper_b]);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_endpoint_package_name_metadata() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "endpoint_package_name", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "control.plane",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let helper_edge = mutable_import_edge(&mut document, "app::helper");
    helper_edge.insert(
        "import_path".to_string(),
        serde_json::Value::String("control::plane".to_string()),
    );
    helper_edge.insert(
        "target_module_path".to_string(),
        serde_json::Value::String("control::plane".to_string()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "lockfile import graph endpoints must not accept package-name metadata as module evidence",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("target module path")
            && message.contains("package metadata")
            && message.contains("control.plane")
            && message.contains("control::plane")
            && message.contains("control-plane identity")
            && message.contains("source module declarations"),
        "expected import-graph/package metadata boundary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_endpoint_package_name_even_when_source_identity_is_tampered() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "endpoint_identity_tamper", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "control.plane",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");

    let source_identity = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| {
            files.iter_mut().find(|file| {
                file.get("path").and_then(|path| path.as_str()) == Some(canonical_helper.as_str())
            })
        })
        .expect("generated lockfile should include helper source identity");
    source_identity
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("control::plane".to_string()),
        );

    let helper_edge = mutable_import_edge(&mut document, "app::helper");
    helper_edge.insert(
        "import_path".to_string(),
        serde_json::Value::String("control::plane".to_string()),
    );
    helper_edge.insert(
        "target_module_path".to_string(),
        serde_json::Value::String("control::plane".to_string()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "import graph endpoints must be checked against their source-root path identity, not only the persisted source-identity table",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("target module path")
            && message.contains("package metadata")
            && message.contains("control.plane")
            && message.contains("control::plane")
            && message.contains("source-root relative path")
            && message.contains("app/helper.lani")
            && message.contains("source module declarations"),
        "expected import graph endpoint/source-root identity boundary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_replay_rejects_stale_package_name_shaped_import_graph_edges() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "stale_package_import", None);
    let app_root = root.join("src").join("app");
    let control_root = root.join("src").join("control");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&control_root).expect("create package control source root");

    let package_module_path = control_root.join("plane.lani");
    std::fs::write(
        &package_module_path,
        r#"
module control::plane;

pub fn value() -> i32 {
    return 1;
}
"#,
    )
    .expect("write package-name-shaped module source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import control::plane;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with package-name-shaped import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "control.plane",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with package-name-shaped import graph edge");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated lockfile should validate before the source import changes");

    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("remove live import while leaving package metadata and imported file in place");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale package lockfile import graph must be replay-validated against live source imports",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("control::plane")
            && message.contains("expected 1 imports")
            && message.contains("found 0"),
        "expected stale package-name-shaped import edge to be rejected as replay metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_edges_outside_library_dependencies() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "stdlib_user_back_edge", None);
    let app_root = root.join("src").join("app");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core root");

    std::fs::write(
        app_root.join("leaf.lani"),
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 4;
}
"#,
    )
    .expect("write package leaf source");

    std::fs::write(
        stdlib_core_root.join("shim.lani"),
        r#"
module core::shim;

import app::leaf;

pub fn value() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("write stdlib shim source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import core::shim;

fn main() {
    return core::shim::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stdlib-user-back-edge",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved
        .load_source_pack()
        .expect_err("package manifest loading should reject stdlib imports back into user roots");
    assert_stdlib_user_back_edge_error(&err);

    let err = resolved.load_path_manifest().expect_err(
        "package manifest path loading should reject stdlib imports back into user roots",
    );
    assert_stdlib_user_back_edge_error(&err);

    let err = lockfile
        .load_source_pack()
        .expect_err("package lockfile loading should reject stdlib imports back into user roots");
    assert_stdlib_user_back_edge_error(&err);

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile path loading should reject stdlib imports back into user roots",
    );
    assert_stdlib_user_back_edge_error(&err);

    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfile should reject stdlib imports back into user roots");
    assert_stdlib_user_back_edge_error(&err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stdlib_to_user_library_dependency_metadata() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "stdlib_user_dependency", None);
    let app_root = root.join("src").join("app");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core root");

    std::fs::write(
        stdlib_core_root.join("number.lani"),
        r#"
module core::number;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write stdlib core source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import core::number;

fn main() {
    return core::number::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stdlib-user-dependency",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with stdlib dependency");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let library_dependencies = document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("library_dependencies"))
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies");
    assert!(
        library_dependencies.iter().any(|dependency| {
            dependency.get("library_id") == Some(&serde_json::Value::from(1))
                && dependency.get("depends_on_library_id") == Some(&serde_json::Value::from(0))
        }),
        "fixture should record the allowed package/user to stdlib dependency"
    );
    library_dependencies.push(serde_json::json!({
        "library_id": 0,
        "depends_on_library_id": 1
    }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("stdlib library dependencies should not point back to package roots");
    assert_stdlib_user_library_dependency_error(&err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_duplicate_library_dependency_metadata() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "duplicate_dependency", None);
    let app_root = root.join("src").join("app");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core root");

    std::fs::write(
        stdlib_core_root.join("number.lani"),
        r#"
module core::number;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write stdlib core source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import core::number;

fn main() {
    return core::number::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-dependency",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with stdlib dependency");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let dependencies = document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("library_dependencies"))
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies");
    let dependency = dependencies
        .iter()
        .find(|dependency| {
            dependency.get("library_id") == Some(&serde_json::Value::from(1))
                && dependency.get("depends_on_library_id") == Some(&serde_json::Value::from(0))
        })
        .expect("fixture should record the user-to-stdlib dependency")
        .clone();
    dependencies.push(dependency);

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("duplicate library dependency metadata should not validate");
    assert_duplicate_library_dependency_error(&err, 1, 0);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_library_dependency_without_import_edge() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "dependency_without_edge", None);
    let app_root = root.join("src").join("app");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core root");

    std::fs::write(
        stdlib_core_root.join("number.lani"),
        r#"
module core::number;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write stdlib core source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import core::number;

fn main() {
    return core::number::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "dependency-without-edge",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with stdlib dependency");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated package lockfile should validate");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let import_graph = document
        .get_mut("import_graph")
        .and_then(|graph| graph.as_object_mut())
        .expect("generated lockfile should persist mutable import graph");
    let library_dependencies = import_graph
        .get("library_dependencies")
        .and_then(|dependencies| dependencies.as_array())
        .expect("generated lockfile should persist library dependencies");
    assert!(
        library_dependencies.iter().any(|dependency| {
            dependency.get("library_id") == Some(&serde_json::Value::from(1))
                && dependency.get("depends_on_library_id") == Some(&serde_json::Value::from(0))
        }),
        "fixture should record the user-to-stdlib library dependency"
    );
    let imports = import_graph
        .get_mut("imports")
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges");
    let original_import_count = imports.len();
    imports.retain(|edge| {
        !(edge.get("source_library_id") == Some(&serde_json::Value::from(1))
            && edge.get("target_library_id") == Some(&serde_json::Value::from(0))
            && edge.get("import_path").and_then(|path| path.as_str()) == Some("core::number"))
    });
    assert!(
        imports.len() < original_import_count,
        "test fixture should remove the cross-library import edge while keeping the dependency"
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("library dependencies should be justified by persisted import edges");
    assert_library_dependency_without_edge_error(&err, 1, 0);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_unknown_import_graph_library_ids() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "unknown_library_id", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "unknown-library-id");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut dependency_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    dependency_document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("library_dependencies"))
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies")
        .push(serde_json::json!({
            "library_id": 2,
            "depends_on_library_id": 1
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&dependency_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile library dependencies must use known package replay libraries");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph library dependency source")
            && message.contains("library 2")
            && message.contains("unsupported")
            && message.contains("stdlib library 0")
            && message.contains("package/user library 1"),
        "expected unknown dependency library diagnostic, got {message}"
    );

    let mut edge_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    edge_document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 2,
            "source_path": canonical_entry.clone(),
            "source_module_path": "app::main",
            "import_path": "app::helper",
            "target_library_id": 1,
            "target_path": canonical_entry,
            "target_module_path": "app::helper"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&edge_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import edges must use known package replay libraries");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge 0 source")
            && message.contains("library 2")
            && message.contains("unsupported"),
        "expected unknown import-edge library diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_unknown_input_and_source_identity_library_ids() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "unknown_identity_library_id",
        None,
    );
    let (_, _, lockfile_path) =
        write_minimal_generated_lockfile(&root, "unknown-identity-library-id");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");

    let mut input_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    input_document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|file| file.as_object_mut())
        .expect("generated lockfile should persist mutable input identities")
        .insert("library_id".to_string(), serde_json::Value::from(2));
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&input_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile input identities must use known replay libraries");
    let message = format!("{err:?}");
    assert!(
        message.contains("input identity file library 2")
            && message.contains("unsupported")
            && message.contains("stdlib library 0")
            && message.contains("package/user library 1"),
        "expected unknown input identity library diagnostic, got {message}"
    );

    let mut source_identity_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    source_identity_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|file| file.as_object_mut())
        .expect("generated lockfile should persist mutable source identities")
        .insert("library_id".to_string(), serde_json::Value::from(2));
    let tampered_lockfile_json = serde_json::to_string_pretty(&source_identity_document)
        .expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile source identities must use known replay libraries");
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity file library 2")
            && message.contains("unsupported")
            && message.contains("stdlib library 0")
            && message.contains("package/user library 1"),
        "expected unknown source identity library diagnostic, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_incomplete_source_identity_shape_before_import_graph_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "incomplete_source_identity_shape",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "incomplete-source-identity-shape");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|file| file.as_object_mut())
        .expect("generated lockfile should persist mutable source identity metadata")
        .remove("module_path");
    document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 1,
            "source_path": canonical_entry.clone(),
            "source_module_path": "app::main",
            "import_path": "not a module path",
            "target_library_id": 1,
            "target_path": canonical_entry,
            "target_module_path": "app::main"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "incomplete source identities should fail before import graph metadata is considered",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity file")
            && message.contains("missing module path metadata"),
        "expected incomplete source identity metadata error, got {message}"
    );
    assert!(
        !message.contains("invalid import graph path"),
        "incomplete source identity shape must not be masked by import graph metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_source_identity_package_metadata_before_import_graph_metadata() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "source_identity_before_import_graph",
        None,
    );
    let (_, entry_path, lockfile_path) = write_minimal_generated_lockfile(&root, "control.plane");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|file| file.as_object_mut())
        .expect("generated lockfile should persist mutable source identity metadata")
        .insert(
            "module_path".to_string(),
            serde_json::Value::String("control::plane".to_string()),
        );
    document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 1,
            "source_path": canonical_entry.clone(),
            "source_module_path": "app::main",
            "import_path": "not a module path",
            "target_library_id": 1,
            "target_path": canonical_entry,
            "target_module_path": "app::main"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "source identity ownership should fail before malformed import graph metadata is considered",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity file")
            && message.contains("package metadata")
            && message.contains("control.plane")
            && message.contains("control::plane")
            && message.contains("control-plane identity")
            && message.contains("source module declarations"),
        "expected source identity package/control-plane boundary error, got {message}"
    );
    assert!(
        !message.contains("invalid import graph path"),
        "source identity ownership must not be masked by import graph metadata, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_duplicate_source_import_declarations() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "duplicate_source_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 9;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;
import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with repeated import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "duplicate-source-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let err = lockfile
        .to_json_pretty()
        .expect_err("package lockfiles should reject duplicate source import declarations");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("duplicate import diagnostic should carry a source label");
            assert_eq!(label.path, std::fs::canonicalize(&entry_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some("import app::helper;"));
            assert_eq!(label.message, "duplicate import declaration");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("app::helper") && note.contains("repeated")),
                "expected duplicate import note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("first `app::helper` import") && note.contains("line 4")
                }),
                "expected duplicate import diagnostic to identify the first import, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("parsed import records")),
                "expected parsed import-record boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned duplicate import diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_duplicate_imports_after_path_normalization() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "normalized_duplicate_import",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("helper.lani"),
        r#"
module app::helper;

pub fn value() -> i32 {
    return 9;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;
import app
    /* import path trivia must not create a second edge */
    :: helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source with normalized repeated import");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "normalized-duplicate-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let err = lockfile.to_json_pretty().expect_err(
        "package lockfiles should reject duplicate import declarations after path normalization",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("normalized duplicate import diagnostic should carry a source label");
            assert_eq!(label.path, std::fs::canonicalize(&entry_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some("import app"));
            assert_eq!(label.message, "duplicate import declaration");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("app::helper") && note.contains("repeated")),
                "expected normalized duplicate import note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("first `app::helper` import") && note.contains("line 4")
                }),
                "expected normalized duplicate import diagnostic to identify the first import, got {:?}",
                diagnostic.notes
            );
        }
        other => {
            panic!("expected source-spanned normalized duplicate import diagnostic, got {other:?}")
        }
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_import_path_with_multiple_targets() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "ambiguous_import_edge", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 9;
}
"#,
    )
    .expect("write package helper source");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 4;
}
"#,
    )
    .expect("write package leaf source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "ambiguous-import-edge",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize package helper")
        .display()
        .to_string();
    let canonical_leaf = std::fs::canonicalize(&leaf_path)
        .expect("canonicalize package leaf")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let import_edges = document
        .get_mut("import_graph")
        .and_then(|import_graph| import_graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("lockfile JSON should persist mutable import graph edges");
    let mut ambiguous_edge = import_edges
        .iter()
        .find(|edge| {
            edge.get("source_path").and_then(|path| path.as_str()) == Some(canonical_entry.as_str())
                && edge.get("import_path").and_then(|path| path.as_str()) == Some("app::helper")
                && edge.get("target_path").and_then(|path| path.as_str())
                    == Some(canonical_helper.as_str())
        })
        .expect("generated lockfile should include the helper import edge")
        .clone();
    let ambiguous_edge_object = ambiguous_edge
        .as_object_mut()
        .expect("import graph edge should be an object");
    ambiguous_edge_object.insert(
        "target_path".to_string(),
        serde_json::Value::String(canonical_leaf.clone()),
    );
    ambiguous_edge_object.insert(
        "target_module_path".to_string(),
        serde_json::Value::String("app::helper".to_string()),
    );
    import_edges.push(ambiguous_edge);

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("a persisted source import path should not resolve to multiple target files");
    let message = format!("{err:?}");
    assert!(
        message.contains("ambiguous import graph edge")
            && message.contains("app::helper")
            && message.contains(canonical_helper.as_str())
            && message.contains(canonical_leaf.as_str())
            && message.contains("one target per source import path"),
        "expected ambiguous persisted import edge error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_persists_input_and_source_identity_sections_in_canonical_order() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "canonical_sections", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("alpha.lani"),
        r#"
module app::alpha;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write alpha package source");
    std::fs::write(
        app_root.join("zeta.lani"),
        r#"
module app::zeta;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write zeta package source");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::zeta;
import app::alpha;

fn main() {
    return app::alpha::VALUE + app::zeta::VALUE;
}
"#,
    )
    .expect("write package entry source with non-canonical discovery order");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "canonical-sections",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with canonical replay sections");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated package lockfile should validate");

    let document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    assert_canonical_section_file_order(&document, "inputs");
    assert_canonical_section_file_order(&document, "source_identities");

    let mut tampered_inputs = document.clone();
    tampered_inputs
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable input files")
        .reverse();
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_inputs).expect("serialize tampered inputs");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted input identity order should be canonical");
    let message = format!("{err:?}");
    assert!(
        message.contains("input identity files must be sorted")
            && message.contains("regenerate the package lockfile"),
        "expected canonical input identity order error, got {message}"
    );

    let mut tampered_identities = document;
    tampered_identities
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source identity files")
        .reverse();
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_identities).expect("serialize tampered identities");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted source identity order should be canonical");
    let message = format!("{err:?}");
    assert!(
        message.contains("source identity files must be sorted")
            && message.contains("regenerate the package lockfile"),
        "expected canonical source identity order error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_import_graph_keeps_stdlib_nested_imports_inside_stdlib_boundary() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "stdlib_nested_imports", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&user_core_root).expect("create package user core source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core source root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create package stdlib std source root");

    let user_number = user_core_root.join("number.lani");
    std::fs::write(
        &user_number,
        "module core::number;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write user-shadowed core module");
    let stdlib_number = stdlib_core_root.join("number.lani");
    std::fs::write(
        &stdlib_number,
        "module core::number;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib core module");
    let stdlib_user = stdlib_std_root.join("uses_number.lani");
    std::fs::write(
        &stdlib_user,
        "module std::uses_number;\nimport core::number;\npub const VALUE: i32 = 3;\n",
    )
    .expect("write stdlib module with nested core import");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::number;\nimport std::uses_number;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stdlib-nested-imports",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize lockfile with shadowed user and stdlib modules");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated lockfile import graph should validate");

    let document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let imports = document
        .get("import_graph")
        .and_then(|graph| graph.get("imports"))
        .and_then(|imports| imports.as_array())
        .expect("lockfile JSON should include import graph edges");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let canonical_user_number = std::fs::canonicalize(&user_number)
        .expect("canonicalize user core module")
        .display()
        .to_string();
    let canonical_stdlib_user = std::fs::canonicalize(&stdlib_user)
        .expect("canonicalize stdlib dependent module")
        .display()
        .to_string();
    let canonical_stdlib_number = std::fs::canonicalize(&stdlib_number)
        .expect("canonicalize stdlib core module")
        .display()
        .to_string();

    assert!(
        imports.iter().any(|edge| {
            edge.get("source_library_id") == Some(&serde_json::Value::from(1))
                && edge.get("source_path").and_then(|path| path.as_str())
                    == Some(canonical_entry.as_str())
                && edge.get("import_path").and_then(|path| path.as_str()) == Some("core::number")
                && edge.get("target_library_id") == Some(&serde_json::Value::from(1))
                && edge.get("target_path").and_then(|path| path.as_str())
                    == Some(canonical_user_number.as_str())
        }),
        "entry imports should record the user source-root shadow"
    );
    assert!(
        imports.iter().any(|edge| {
            edge.get("source_library_id") == Some(&serde_json::Value::from(0))
                && edge.get("source_path").and_then(|path| path.as_str())
                    == Some(canonical_stdlib_user.as_str())
                && edge.get("import_path").and_then(|path| path.as_str()) == Some("core::number")
                && edge.get("target_library_id") == Some(&serde_json::Value::from(0))
                && edge.get("target_path").and_then(|path| path.as_str())
                    == Some(canonical_stdlib_number.as_str())
        }),
        "stdlib nested imports should record the stdlib target, not the user shadow"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_user_import_edge_that_skips_user_shadow_for_stdlib_module() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "user_shadow_edge", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&user_core_root).expect("create package user core source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core source root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create package stdlib std source root");

    let user_number = user_core_root.join("number.lani");
    std::fs::write(
        &user_number,
        "module core::number;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write user-shadowed core module");
    let stdlib_number = stdlib_core_root.join("number.lani");
    std::fs::write(
        &stdlib_number,
        "module core::number;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib core module");
    std::fs::write(
        stdlib_std_root.join("uses_number.lani"),
        "module std::uses_number;\nimport core::number;\npub const VALUE: i32 = 3;\n",
    )
    .expect("write stdlib module with nested core import");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::number;\nimport std::uses_number;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "user-shadow-edge",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize lockfile with shadowed user and stdlib modules");

    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize package entry")
        .display()
        .to_string();
    let canonical_user_number = std::fs::canonicalize(&user_number)
        .expect("canonicalize user core module")
        .display()
        .to_string();
    let canonical_stdlib_number = std::fs::canonicalize(&stdlib_number)
        .expect("canonicalize stdlib core module")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let entry_core_edge = document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .and_then(|imports| {
            imports.iter_mut().find(|edge| {
                edge.get("source_library_id") == Some(&serde_json::Value::from(1))
                    && edge.get("source_path").and_then(|path| path.as_str())
                        == Some(canonical_entry.as_str())
                    && edge.get("import_path").and_then(|path| path.as_str())
                        == Some("core::number")
            })
        })
        .expect("generated lockfile should include entry core::number import edge")
        .as_object_mut()
        .expect("import graph edge should be an object");
    entry_core_edge.insert("target_library_id".to_string(), serde_json::Value::from(0));
    entry_core_edge.insert(
        "target_path".to_string(),
        serde_json::Value::String(canonical_stdlib_number.clone()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "persisted import graph should not let library metadata skip a user-root module shadow",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("targets stdlib module core::number")
            && message.contains(canonical_stdlib_number.as_str())
            && message.contains(canonical_user_number.as_str())
            && message.contains("package/user roots take precedence")
            && message.contains("must not choose semantic module identity"),
        "expected user-root precedence import-graph error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove user-shadow edge temp root");
}

#[test]
fn package_lockfile_rejects_stale_stdlib_fallback_when_user_module_appears() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "stale_stdlib_fallback", None);
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core root");

    let stdlib_number = stdlib_core_root.join("number.lani");
    std::fs::write(
        &stdlib_number,
        "module core::number;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib fallback module");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::number;\nfn main() { return core::number::VALUE; }\n",
    )
    .expect("write package entry using stdlib fallback");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stale-stdlib-fallback",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile while stdlib fallback is current");

    std::fs::create_dir_all(&user_core_root).expect("create package user core root");
    let user_number = user_core_root.join("number.lani");
    std::fs::write(
        &user_number,
        "module core::number;\npub const VALUE: i32 = 1;\n",
    )
    .expect("add user module that shadows the stale stdlib fallback");

    let canonical_stdlib_number =
        std::fs::canonicalize(&stdlib_number).expect("canonicalize stdlib number module");
    let canonical_user_number =
        std::fs::canonicalize(&user_number).expect("canonicalize user number module");
    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale package lockfile must not keep using a stdlib fallback shadowed by user source",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph changed")
            && message.contains("core::number")
            && message.contains(canonical_stdlib_number.display().to_string().as_str())
            && message.contains(canonical_user_number.display().to_string().as_str())
            && message.contains("package/user roots take precedence")
            && message.contains("stale lockfile metadata"),
        "expected stale stdlib fallback precedence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale stdlib fallback temp root");
}

#[cfg(unix)]
#[test]
fn package_manifest_rejects_stdlib_nested_import_symlink_escape_through_user_root() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stdlib_nested_import_symlink_escape",
        None,
    );
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&user_core_root).expect("create package user core source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib core source root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create package stdlib std source root");

    let shared_path = stdlib_core_root.join("shared.lani");
    std::fs::write(
        &shared_path,
        "module core::shared;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write shared stdlib module");
    std::os::unix::fs::symlink(&shared_path, user_core_root.join("shared.lani"))
        .expect("create user-root source-looking symlink to stdlib module");

    let shim_path = stdlib_std_root.join("shim.lani");
    std::fs::write(
        &shim_path,
        "module std::shim;\nimport core::shared;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib shim module");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport std::shim;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stdlib-nested-import-symlink-escape",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = resolved.load_source_pack().expect_err(
        "package manifest source loading should reject user-root symlink aliases to stdlib imports",
    );
    assert_stdlib_nested_import_symlink_escape_error(&err, &shim_path, &shared_path);

    let err = resolved.load_path_manifest().expect_err(
        "package manifest path loading should reject user-root symlink aliases to stdlib imports",
    );
    assert_stdlib_nested_import_symlink_escape_error(&err, &shim_path, &shared_path);

    let err = lockfile.load_source_pack().expect_err(
        "package lockfile source loading should reject user-root symlink aliases to stdlib imports",
    );
    assert_stdlib_nested_import_symlink_escape_error(&err, &shim_path, &shared_path);

    let err = lockfile.load_path_manifest().expect_err(
        "package lockfile path loading should reject user-root symlink aliases to stdlib imports",
    );
    assert_stdlib_nested_import_symlink_escape_error(&err, &shim_path, &shared_path);

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should reject user-root symlink aliases to stdlib imports",
    );
    assert_stdlib_nested_import_symlink_escape_error(&err, &shim_path, &shared_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_edges_missing_from_input_identity() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "import_input_integrity", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write imported leaf source");

    let middle_path = app_root.join("middle.lani");
    std::fs::write(
        &middle_path,
        r#"
module app::middle;

import app::leaf;

pub fn value() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("write imported middle source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::middle;

fn main() {
    return app::middle::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-input-integrity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");

    let leaf_path_text = std::fs::canonicalize(&leaf_path)
        .expect("canonicalize imported source")
        .display()
        .to_string();
    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let input_count = input_files.len();
    input_files.retain(|file| {
        file.get("path").and_then(|path| path.as_str()) != Some(leaf_path_text.as_str())
    });
    assert!(
        input_files.len() < input_count,
        "test fixture should remove one persisted source input"
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph should not reference files absent from input identity");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("target file")
            && message.contains("missing from input identity"),
        "expected import graph/input identity consistency error, got {message}"
    );

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source identities");
    let source_identity_count = source_identity_files.len();
    source_identity_files.retain(|file| {
        file.get("path").and_then(|path| path.as_str()) != Some(leaf_path_text.as_str())
    });
    assert!(
        source_identity_files.len() < source_identity_count,
        "test fixture should remove one persisted source identity"
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "lockfile import graph should not reference files absent from source identities",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("target file")
            && message.contains("missing from source identities"),
        "expected import graph/source identity consistency error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_dependencies_missing_from_identity_sections() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "dependency_identity", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "dependency-identity");
    let stdlib_core_root = root.join("stdlib").join("core");
    std::fs::create_dir_all(&stdlib_core_root).expect("create package stdlib root");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let canonical_stdlib_root =
        std::fs::canonicalize(root.join("stdlib")).expect("canonicalize generated stdlib root");
    let canonical_stdlib_target = canonical_stdlib_root
        .join("core")
        .join("number.lani")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "stdlib_root".to_string(),
            serde_json::Value::String(canonical_stdlib_root.display().to_string()),
        );
    let import_graph = document
        .get_mut("import_graph")
        .and_then(|import_graph| import_graph.as_object_mut())
        .expect("generated lockfile should persist mutable import graph");
    import_graph
        .get_mut("library_dependencies")
        .and_then(|dependencies| dependencies.as_array_mut())
        .expect("generated lockfile should persist mutable library dependencies")
        .push(serde_json::json!({
            "library_id": 1,
            "depends_on_library_id": 0
        }));
    import_graph
        .get_mut("imports")
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges")
        .push(serde_json::json!({
            "source_library_id": 1,
            "source_path": canonical_entry,
            "source_module_path": "app::main",
            "import_path": "core::number",
            "target_library_id": 0,
            "target_path": canonical_stdlib_target,
            "target_module_path": "core::number"
        }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "lockfile import graph dependencies should be backed by persisted source identities",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph library dependency")
            && message.contains("depends-on library 0")
            && message.contains("missing from input identity"),
        "expected import graph dependency/input identity consistency error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_unreachable_source_identity_metadata() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "unreachable_identity", None);
    let (src_root, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "unreachable-identity");
    let unused_path = src_root.join("app").join("unused.lani");
    std::fs::write(
        &unused_path,
        r#"
module app::unused;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write unreachable package source");

    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let canonical_unused = std::fs::canonicalize(&unused_path)
        .expect("canonicalize unreachable source")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source inputs");
    let mut unreachable_input = input_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include entry input")
        .clone();
    unreachable_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(canonical_unused.clone()),
        );
    input_files.push(unreachable_input);

    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source identities");
    let mut unreachable_identity = source_identity_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include entry source identity")
        .clone();
    let unreachable_identity_fields = unreachable_identity
        .as_object_mut()
        .expect("source identity entry should be an object");
    unreachable_identity_fields.insert(
        "path".to_string(),
        serde_json::Value::String(canonical_unused.clone()),
    );
    unreachable_identity_fields.insert(
        "source_root_relative_path".to_string(),
        serde_json::Value::String("app/unused.lani".to_string()),
    );
    unreachable_identity_fields.insert(
        "module_path".to_string(),
        serde_json::Value::String("app::unused".to_string()),
    );
    source_identity_files.push(unreachable_identity);

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("unreachable lockfile source metadata should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains(canonical_unused.as_str())
            && message.contains("not reachable")
            && message.contains("persisted import graph edges"),
        "expected unreachable source metadata error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_disconnected_import_graph_components() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "disconnected_graph", None);
    let (src_root, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "disconnected-graph");
    let app_root = src_root.join("app");
    let helper_path = app_root.join("helper.lani");
    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

import app::leaf;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write disconnected helper source");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write disconnected leaf source");

    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize disconnected helper")
        .display()
        .to_string();
    let canonical_leaf = std::fs::canonicalize(&leaf_path)
        .expect("canonicalize disconnected leaf")
        .display()
        .to_string();

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source inputs");
    let entry_input = input_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include entry input")
        .clone();
    for path in [&canonical_helper, &canonical_leaf] {
        let mut input = entry_input.clone();
        input
            .as_object_mut()
            .expect("input identity entry should be an object")
            .insert("path".to_string(), serde_json::Value::String(path.clone()));
        input_files.push(input);
    }
    sort_lockfile_section_files(&mut document, "inputs");

    let source_identity_files = document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist mutable source identities");
    let entry_identity = source_identity_files
        .iter()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include entry source identity")
        .clone();
    for (path, relative_path, module_path) in [
        (&canonical_helper, "app/helper.lani", "app::helper"),
        (&canonical_leaf, "app/leaf.lani", "app::leaf"),
    ] {
        let mut identity = entry_identity.clone();
        let identity_fields = identity
            .as_object_mut()
            .expect("source identity entry should be an object");
        identity_fields.insert("path".to_string(), serde_json::Value::String(path.clone()));
        identity_fields.insert(
            "source_root_relative_path".to_string(),
            serde_json::Value::String(relative_path.to_string()),
        );
        identity_fields.insert(
            "module_path".to_string(),
            serde_json::Value::String(module_path.to_string()),
        );
        source_identity_files.push(identity);
    }
    sort_lockfile_section_files(&mut document, "source_identities");

    let import_edges = document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges");
    import_edges.push(serde_json::json!({
        "source_library_id": 1,
        "source_path": canonical_helper,
        "source_module_path": "app::helper",
        "import_path": "app::leaf",
        "target_library_id": 1,
        "target_path": canonical_leaf,
        "target_module_path": "app::leaf"
    }));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("disconnected lockfile import components should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains(canonical_helper.as_str())
            && message.contains("not reachable from the package entry")
            && message.contains("persisted import graph edges"),
        "expected disconnected import graph component error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_validates_optional_produced_artifact_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "artifact_identity", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "artifact-identity");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");
    let artifact_path = artifact_dir.join("app.wasm");
    std::fs::write(&artifact_path, b"\0asm\x01\0\0\0").expect("write package artifact");

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "final-output",
            &artifact_path,
        )
        .expect("record produced artifact identity"),
    );
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with artifact identity");
    let roundtrip = PackageLockfile::parse_json(&lockfile_json)
        .expect("artifact identity should validate while artifact bytes match");
    assert_eq!(roundtrip.artifacts.len(), 1);
    assert_eq!(roundtrip.artifacts[0].target, "wasm32-unknown-unknown");
    assert_eq!(roundtrip.artifacts[0].kind, "final-output");

    assert!(
        PackageLockfileArtifact::from_existing_file("-wasm32", "final-output", &artifact_path)
            .is_err(),
        "artifact targets should be stable identity labels, not punctuation-prefixed tokens"
    );
    assert!(
        PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "final-output:",
            &artifact_path,
        )
        .is_err(),
        "artifact kinds should be stable identity labels, not punctuation-suffixed tokens"
    );
    let err = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "link",
        &artifact_path,
    )
    .expect_err("package artifact identities must not reuse source-pack link evidence labels");
    assert_reserved_artifact_kind_error(&err, "link");
    let err = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "linked-output",
        &artifact_path,
    )
    .expect_err("package artifact identities must not reuse source-pack link evidence labels");
    assert_reserved_artifact_kind_error(&err, "linked-output");
    let err = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "object-section",
        &artifact_path,
    )
    .expect_err("package artifact identities must not reuse link record labels");
    assert_reserved_artifact_kind_error(&err, "object-section");
    let err = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "runtime-service",
        &artifact_path,
    )
    .expect_err("package artifact identities must not reuse runtime link requirement labels");
    assert_reserved_artifact_kind_error(&err, "runtime-service");

    let mut tampered_label_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let artifact_identity = tampered_label_document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|artifact| artifact.as_object_mut())
        .expect("lockfile should persist one mutable artifact identity");
    artifact_identity.insert(
        "target".to_string(),
        serde_json::Value::String("wasm32-unknown-unknown:".to_string()),
    );
    let tampered_label_json =
        serde_json::to_string_pretty(&tampered_label_document).expect("serialize lockfile JSON");
    assert!(
        PackageLockfile::parse_json(&tampered_label_json).is_err(),
        "persisted artifact targets should reject punctuation-suffixed labels"
    );

    let mut tampered_kind_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let artifact_identity = tampered_kind_document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|artifact| artifact.as_object_mut())
        .expect("lockfile should persist one mutable artifact identity");
    artifact_identity.insert(
        "kind".to_string(),
        serde_json::Value::String("partial-link".to_string()),
    );
    let tampered_kind_json =
        serde_json::to_string_pretty(&tampered_kind_document).expect("serialize lockfile JSON");
    let err = PackageLockfile::parse_json(&tampered_kind_json)
        .expect_err("persisted package artifact identities must not reuse link evidence labels");
    assert_reserved_artifact_kind_error(&err, "partial-link");

    let mut tampered_record_kind_document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let artifact_identity = tampered_record_kind_document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|artifact| artifact.as_object_mut())
        .expect("lockfile should persist one mutable artifact identity");
    artifact_identity.insert(
        "kind".to_string(),
        serde_json::Value::String("export-symbol".to_string()),
    );
    let tampered_record_kind_json = serde_json::to_string_pretty(&tampered_record_kind_document)
        .expect("serialize link-record-label lockfile JSON");
    let err = PackageLockfile::parse_json(&tampered_record_kind_json).expect_err(
        "persisted package artifact identities must not reuse link record evidence labels",
    );
    assert_reserved_artifact_kind_error(&err, "export-symbol");

    std::fs::write(&artifact_path, b"\0asm\x01\0\0\x01")
        .expect("rewrite package artifact with stale content");
    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("stale artifact bytes should make artifact identity invalid");
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact digest mismatch")
            && message.contains(
                artifact_path
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .as_ref()
            ),
        "expected artifact digest mismatch, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_empty_produced_artifact_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "empty_artifact", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "empty-artifact");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");

    let empty_artifact_path = artifact_dir.join("empty.wasm");
    std::fs::write(&empty_artifact_path, b"").expect("write empty package artifact");
    let err = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "final-output",
        &empty_artifact_path,
    )
    .expect_err("empty produced artifact files should not become package lock identities");
    assert_empty_artifact_error(&err, &empty_artifact_path);

    let non_empty_artifact_path = artifact_dir.join("app.wasm");
    std::fs::write(&non_empty_artifact_path, b"\0asm\x01\0\0\0")
        .expect("write non-empty package artifact");
    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "final-output",
            &non_empty_artifact_path,
        )
        .expect("record non-empty produced artifact identity"),
    );
    let mut document = serde_json::from_str::<serde_json::Value>(
        &lockfile
            .to_json_pretty()
            .expect("serialize package lockfile with artifact identity"),
    )
    .expect("parse package lockfile JSON with artifact identity");
    let artifact_identity = document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .and_then(|files| files.first_mut())
        .and_then(|artifact| artifact.as_object_mut())
        .expect("lockfile should persist one mutable artifact identity");
    artifact_identity.insert(
        "path".to_string(),
        serde_json::Value::String(
            std::fs::canonicalize(&empty_artifact_path)
                .expect("canonicalize empty package artifact")
                .display()
                .to_string(),
        ),
    );
    artifact_identity.insert(
        "byte_len".to_string(),
        serde_json::Value::Number(serde_json::Number::from(0)),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted artifact identities should not point at empty produced files");
    assert_empty_artifact_error(&err, &empty_artifact_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stale_source_before_missing_produced_artifact() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stale_source_before_artifact",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "stale-source-before-artifact");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");
    let artifact_path = artifact_dir.join("app.wasm");
    std::fs::write(&artifact_path, b"\0asm\x01\0\0\0").expect("write package artifact");

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "final-output",
            &artifact_path,
        )
        .expect("record produced artifact identity"),
    );
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with artifact identity");

    let source = std::fs::read_to_string(&entry_path).expect("read package entry source");
    std::fs::write(&entry_path, source.replace("return 0;", "return 1;"))
        .expect("mutate package entry source without changing replay shape");
    std::fs::remove_file(&artifact_path).expect("remove produced artifact after lockfile write");

    let assert_stale_source_before_artifact = |err: CompileError, context: &str| {
        let message = format!("{err:?}");
        assert!(
            message.contains("input digest mismatch")
                && message.contains(&entry_path.display().to_string()),
            "expected stale source input digest error before artifact validation for {context}, got {message}"
        );
        assert!(
            !message.contains("artifact file") && !message.contains("no longer resolves to a file"),
            "missing produced artifacts must not mask stale package source identity for {context}, got {message}"
        );
    };

    let err = lockfile
        .to_json_pretty()
        .expect_err("loaded lockfile reserialization should reject stale source before missing produced artifacts");
    assert_stale_source_before_artifact(err, "lockfile reserialization");

    let err = lockfile.load_path_manifest().expect_err(
        "loaded lockfile replay should reject stale source before missing produced artifacts",
    );
    assert_stale_source_before_artifact(err, "lockfile replay");

    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("stale source identity should fail before missing produced artifacts");
    assert_stale_source_before_artifact(err, "package lockfile parse");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_ambiguous_produced_artifact_paths() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "artifact_path_unique", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "artifact-path-unique");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");
    let artifact_path = artifact_dir.join("app.wasm");
    std::fs::write(&artifact_path, b"\0asm\x01\0\0\0").expect("write package artifact");

    let final_artifact = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "final-output",
        &artifact_path,
    )
    .expect("record final produced artifact identity");
    let metadata_artifact = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "metadata",
        &artifact_path,
    )
    .expect("record metadata produced artifact identity");

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(final_artifact.clone());
    lockfile.artifacts.push(metadata_artifact.clone());
    let err = lockfile
        .to_json_pretty()
        .expect_err("one produced artifact path should not carry multiple identities");
    assert_duplicate_artifact_path_error(&err, &artifact_path);

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("reload generated package lockfile");
    lockfile.artifacts.push(final_artifact);
    let mut document = serde_json::from_str::<serde_json::Value>(
        &lockfile
            .to_json_pretty()
            .expect("serialize package lockfile with one artifact identity"),
    )
    .expect("parse package lockfile JSON with one artifact identity");
    let artifact_files = document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable artifact files");
    artifact_files
        .push(serde_json::to_value(&metadata_artifact).expect("serialize duplicate-path artifact"));

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted artifact identities should not reuse produced artifact paths");
    assert_duplicate_artifact_path_error(&err, &artifact_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_artifact_identity_that_points_at_source_input() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "artifact_source_collision",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "artifact-source-collision");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");
    let artifact_path = artifact_dir.join("app.o");
    std::fs::write(&artifact_path, b"object bytes").expect("write package artifact");

    let source_artifact = PackageLockfileArtifact::from_existing_file(
        "x86_64-unknown-linux-gnu",
        "final-output",
        &entry_path,
    )
    .expect("record source input as a produced artifact identity");
    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(source_artifact.clone());
    let err = lockfile
        .to_json_pretty()
        .expect_err("source inputs should not serialize as produced artifacts");
    assert_artifact_source_input_collision(&err);

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("reload generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "x86_64-unknown-linux-gnu",
            "final-output",
            &artifact_path,
        )
        .expect("record non-source produced artifact identity"),
    );
    let mut document = serde_json::from_str::<serde_json::Value>(
        &lockfile
            .to_json_pretty()
            .expect("serialize package lockfile with artifact identity"),
    )
    .expect("parse package lockfile JSON with artifact identity");
    let artifact_files = document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable artifact files");
    artifact_files[0] =
        serde_json::to_value(&source_artifact).expect("serialize source artifact identity");

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted artifact identities should not point at source inputs");
    assert_artifact_source_input_collision(&err);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_artifact_identity_inside_source_roots() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "artifact_unloaded_source_collision",
        None,
    );
    let (src_root, _, lockfile_path) =
        write_minimal_generated_lockfile(&root, "artifact-unloaded-source-collision");
    let artifact_dir = root.join("target");
    std::fs::create_dir_all(&artifact_dir).expect("create package artifact directory");
    let artifact_path = artifact_dir.join("app.o");
    std::fs::write(&artifact_path, b"object bytes").expect("write package artifact");

    let unloaded_source_path = src_root.join("app").join("unused.lani");
    std::fs::write(
        &unloaded_source_path,
        "module app::unused;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write unloaded package source file");

    let source_artifact = PackageLockfileArtifact::from_existing_file(
        "x86_64-unknown-linux-gnu",
        "final-output",
        &unloaded_source_path,
    )
    .expect("record unloaded package source as a produced artifact identity");
    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    lockfile.artifacts.push(source_artifact.clone());
    let err = lockfile
        .to_json_pretty()
        .expect_err("unloaded package source files should not serialize as produced artifacts");
    assert_artifact_package_source_collision(&err, &unloaded_source_path);

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("reload generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "x86_64-unknown-linux-gnu",
            "final-output",
            &artifact_path,
        )
        .expect("record non-source produced artifact identity"),
    );
    let mut document = serde_json::from_str::<serde_json::Value>(
        &lockfile
            .to_json_pretty()
            .expect("serialize package lockfile with artifact identity"),
    )
    .expect("parse package lockfile JSON with artifact identity");
    let artifact_files = document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable artifact files");
    artifact_files[0] =
        serde_json::to_value(&source_artifact).expect("serialize package source artifact identity");

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted artifact identities should not point at package source files");
    assert_artifact_package_source_collision(&err, &unloaded_source_path);

    let source_root_artifact_path = src_root.join("app").join("generated.wasm");
    std::fs::write(&source_root_artifact_path, b"\0asm\x01\0\0\0")
        .expect("write non-source artifact path inside source root");
    let source_root_artifact = PackageLockfileArtifact::from_existing_file(
        "wasm32-unknown-unknown",
        "final-output",
        &source_root_artifact_path,
    )
    .expect("record source-root output as a produced artifact identity");
    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("reload generated package lockfile");
    lockfile.artifacts.push(source_root_artifact.clone());
    let err = lockfile
        .to_json_pretty()
        .expect_err("produced artifacts should stay outside package source roots");
    assert_artifact_package_source_collision(&err, &source_root_artifact_path);
    let err = lockfile
        .validate()
        .expect_err("public lockfile validation should reject artifacts inside source roots");
    assert_artifact_package_source_collision(&err, &source_root_artifact_path);

    let mut lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("reload generated package lockfile");
    lockfile.artifacts.push(
        PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "final-output",
            &artifact_path,
        )
        .expect("record non-source-root produced artifact identity"),
    );
    let mut document = serde_json::from_str::<serde_json::Value>(
        &lockfile
            .to_json_pretty()
            .expect("serialize package lockfile with external artifact identity"),
    )
    .expect("parse package lockfile JSON with external artifact identity");
    let artifact_files = document
        .get_mut("artifacts")
        .and_then(|artifacts| artifacts.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("lockfile JSON should persist mutable artifact files");
    artifact_files[0] = serde_json::to_value(&source_root_artifact)
        .expect("serialize source-root artifact identity");

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted artifact identities should stay outside package source roots");
    assert_artifact_package_source_collision(&err, &source_root_artifact_path);

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_write_creates_missing_non_source_output_directories() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "lock_output_dirs", None);
    let (_, _, lockfile_path) = write_minimal_generated_lockfile(&root, "lock-output-dirs");
    let lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    let nested_lockfile = root
        .join("target")
        .join("package")
        .join("generated")
        .join("lanius.lock.json");
    assert!(
        !nested_lockfile
            .parent()
            .expect("nested lockfile should have a parent")
            .exists(),
        "test fixture should start without the nested output directory"
    );

    lockfile
        .write_json_file(&nested_lockfile)
        .expect("package lockfile writer should create missing non-source output directories");
    assert!(
        nested_lockfile.is_file(),
        "package lockfile writer should create {}",
        nested_lockfile.display()
    );
    PackageLockfile::load_json_file(&nested_lockfile)
        .expect("lockfile written under a missing output directory should validate");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_write_rejects_missing_parent_source_root_output_paths() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "lock_output_source", None);
    let (src_root, _, lockfile_path) =
        write_minimal_generated_lockfile(&root, "lock-output-source");
    let lockfile =
        PackageLockfile::load_json_file(&lockfile_path).expect("load generated package lockfile");
    let source_output = src_root
        .join("app")
        .join("generated")
        .join("lanius.lock.json");
    let source_output_parent = source_output
        .parent()
        .expect("source output should have a parent")
        .to_path_buf();
    assert!(
        !source_output_parent.exists(),
        "test fixture should start without the source output directory"
    );

    let err = lockfile
        .write_json_file(&source_output)
        .expect_err("package lockfile output must not create files inside source roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("lockfile output path")
            && message.contains("package source root")
            && message.contains("control-plane artifacts")
            && message.contains(source_output.display().to_string().as_str()),
        "expected source-output lockfile error, got {message}"
    );
    assert!(
        !source_output.exists() && !source_output_parent.exists(),
        "failed lockfile write should not create source output directories"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_write_rejects_missing_parent_stdlib_root_output_paths() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "lock_output_stdlib_source",
        None,
    );
    let app_root = root.join("src").join("app");
    let stdlib_root = root.join("stdlib");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create package stdlib root");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "lock-output-stdlib-source",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let source_output = stdlib_root
        .join("core")
        .join("generated")
        .join("lanius.lock.json");
    let source_output_parent = source_output
        .parent()
        .expect("stdlib output should have a parent")
        .to_path_buf();
    assert!(
        !source_output_parent.exists(),
        "test fixture should start without the stdlib output directory"
    );

    let err = lockfile
        .write_json_file(&source_output)
        .expect_err("package lockfile output must not create files inside stdlib source roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("lockfile output path")
            && message.contains("stdlib source root")
            && message.contains("control-plane artifacts")
            && message.contains(source_output.display().to_string().as_str()),
        "expected stdlib source-output lockfile error, got {message}"
    );
    assert!(
        !source_output.exists() && !source_output_parent.exists(),
        "failed lockfile write should not create stdlib source output directories"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_load_rejects_control_plane_file_inside_source_roots() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "lock_load_source", None);
    let (src_root, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "lock-load-source");
    let misplaced_lockfile = src_root.join("app").join("lanius.lock.json");
    std::fs::copy(&lockfile_path, &misplaced_lockfile)
        .expect("place lockfile copy inside package source root");
    let entry_source = std::fs::read_to_string(&entry_path).expect("read package entry source");
    std::fs::write(&entry_path, entry_source.replace("return 0;", "return 1;"))
        .expect("make persisted lockfile input identity stale");

    let err = PackageLockfile::load_json_file(&misplaced_lockfile)
        .expect_err("package lockfile loads must reject control-plane files inside source roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("lockfile path")
            && message.contains("package source root")
            && message.contains("control-plane artifacts")
            && message.contains(misplaced_lockfile.display().to_string().as_str()),
        "expected source-root lockfile load boundary error, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch")
            && !message.contains("input byte length mismatch"),
        "source-root lockfile placement should fail before replaying stale source inputs, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[cfg(unix)]
#[test]
fn package_lockfile_load_rejects_symlinked_control_plane_path_inside_source_roots() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "lock_load_source_symlink", None);
    let (src_root, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "lock-load-source-symlink");
    let target_dir = root.join("target");
    std::fs::create_dir_all(&target_dir).expect("create non-source lockfile target directory");
    let target_lockfile = target_dir.join("lanius.lock.json");
    std::fs::copy(&lockfile_path, &target_lockfile)
        .expect("place lockfile target outside package source root");
    let source_tree_symlink = src_root.join("app").join("linked-lock.json");
    std::os::unix::fs::symlink(&target_lockfile, &source_tree_symlink)
        .expect("place lockfile symlink inside package source root");
    let entry_source = std::fs::read_to_string(&entry_path).expect("read package entry source");
    std::fs::write(&entry_path, entry_source.replace("return 0;", "return 1;"))
        .expect("make persisted lockfile input identity stale");

    let err = PackageLockfile::load_json_file(&source_tree_symlink)
        .expect_err("package lockfile loads must reject symlink paths placed inside source roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("lockfile path")
            && message.contains("package source root")
            && message.contains("control-plane artifacts")
            && message.contains(source_tree_symlink.display().to_string().as_str()),
        "expected source-root symlink lockfile load boundary error, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch")
            && !message.contains("input byte length mismatch"),
        "source-root symlink placement should fail before replaying stale source inputs, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_load_rejects_control_plane_file_inside_stdlib_root() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "lock_load_stdlib", None);
    let app_root = root.join("src").join("app");
    let stdlib_root = root.join("stdlib");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create package stdlib root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "lock-load-stdlib",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile_path = root.join("lanius.lock.json");
    PackageLockfile::from_resolved_manifest(&resolved)
        .expect("create package lockfile")
        .write_json_file(&lockfile_path)
        .expect("write package lockfile outside source roots");

    let misplaced_lockfile = stdlib_root.join("lanius.lock.json");
    std::fs::copy(&lockfile_path, &misplaced_lockfile)
        .expect("place lockfile copy inside stdlib source root");
    let entry_source = std::fs::read_to_string(&entry_path).expect("read package entry source");
    std::fs::write(&entry_path, entry_source.replace("return 0;", "return 1;"))
        .expect("make persisted lockfile input identity stale");

    let err = PackageLockfile::load_json_file(&misplaced_lockfile)
        .expect_err("package lockfile loads must reject control-plane files inside stdlib roots");
    let message = format!("{err:?}");
    assert!(
        message.contains("lockfile path")
            && message.contains("stdlib source root")
            && message.contains("control-plane artifacts")
            && message.contains(misplaced_lockfile.display().to_string().as_str()),
        "expected stdlib-root lockfile load boundary error, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch")
            && !message.contains("input byte length mismatch"),
        "stdlib-root lockfile placement should fail before replaying stale source inputs, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_detects_removed_imported_file() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "removed_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "removed-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize imported helper before removal")
        .display()
        .to_string();

    std::fs::remove_file(&helper_path).expect("remove imported package helper source");
    let err = PackageLockfile::parse_json(&lockfile_json)
        .expect_err("stale package lockfile should reject removed imported source");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains(canonical_helper.as_str())
            && message.contains("persisted input identity"),
        "expected stale lockfile error to reject the removed persisted input before import replay, got {message}"
    );
    assert!(
        !message.contains("missing source-root module")
            && !message.contains(entry_path.display().to_string().as_str()),
        "removed persisted inputs should fail before live import replay diagnostics, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_removed_persisted_input_before_graph_shrink() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "removed_input_before_graph_shrink",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write package leaf source");

    let middle_path = app_root.join("middle.lani");
    std::fs::write(
        &middle_path,
        r#"
module app::middle;

import app::leaf;

pub const VALUE: i32 = app::leaf::VALUE;
"#,
    )
    .expect("write package middle source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::middle;

fn main() {
    return app::middle::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "removed-input-before-graph-shrink",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with transitive import graph");
    let canonical_leaf = std::fs::canonicalize(&leaf_path)
        .expect("canonicalize package leaf before removal")
        .display()
        .to_string();

    std::fs::write(
        &middle_path,
        r#"
module app::middle;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("shrink live import graph by removing transitive import");
    std::fs::remove_file(&leaf_path).expect("remove persisted transitive package input");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "removed persisted source inputs should fail input identity before graph comparison",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains(canonical_leaf.as_str())
            && message.contains("persisted input identity"),
        "expected missing persisted input identity error, got {message}"
    );
    assert!(
        !message.contains("import graph changed"),
        "missing persisted inputs should not be masked by live import graph shrinkage, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stale_imported_input_before_source_replay_failure() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "stale_imported_input_before_replay",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 2;
}
"#,
    )
    .expect("write package helper source");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "stale-imported-input-before-replay",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    let canonical_helper = std::fs::canonicalize(&helper_path)
        .expect("canonicalize imported helper")
        .display()
        .to_string();

    std::fs::write(
        &helper_path,
        r#"
module app::helper

pub fn value() -> i32 {
    return 3;
}
"#,
    )
    .expect("mutate imported helper into malformed replay metadata");

    let err = PackageLockfile::parse_json(&lockfile_json).expect_err(
        "stale package lockfile should reject imported input bytes before source replay diagnostics",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("input")
            && message.contains("mismatch")
            && message.contains(canonical_helper.as_str()),
        "expected stale imported input mismatch before source replay, got {message}"
    );
    assert!(
        !message.contains("syntax error")
            && !message.contains("expected ';' after module path")
            && !message.contains("source-root relative path"),
        "stale imported input bytes should fail before live source replay metadata diagnostics, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_noncanonical_import_graph_edge_order() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "import_graph_order", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("alpha.lani"),
        r#"
module app::alpha;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write alpha package source");
    std::fs::write(
        app_root.join("zeta.lani"),
        r#"
module app::zeta;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write zeta package source");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::zeta;
import app::alpha;

fn main() {
    return app::alpha::VALUE + app::zeta::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-graph-order",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated import graph should already use canonical edge order");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let import_edges = document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist mutable import graph edges");
    let import_paths = import_edges
        .iter()
        .map(|edge| edge.get("import_path").and_then(|path| path.as_str()))
        .collect::<Vec<_>>();
    assert_eq!(
        import_paths,
        vec![Some("app::alpha"), Some("app::zeta")],
        "generated package lockfiles should canonicalize import graph edge order"
    );
    import_edges.reverse();

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("persisted import graph replay must not depend on CPU discovery order");
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edges must be sorted")
            && message.contains("source library")
            && message.contains("regenerate the package lockfile"),
        "expected import graph canonical order error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_import_graph_path_with_multiple_module_identities() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "import_graph_path_identity",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("alpha.lani"),
        r#"
module app::alpha;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write alpha package source");
    std::fs::write(
        app_root.join("zeta.lani"),
        r#"
module app::zeta;

pub const VALUE: i32 = 2;
"#,
    )
    .expect("write zeta package source");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::alpha;
import app::zeta;

fn main() {
    return app::alpha::VALUE + app::zeta::VALUE;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "import-graph-path-identity",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    PackageLockfile::parse_json(&lockfile_json)
        .expect("generated import graph should have one module identity per source path");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    mutable_import_edge(&mut document, "app::zeta").insert(
        "source_module_path".to_string(),
        serde_json::Value::String("app::shadow".to_string()),
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "package lockfiles should reject one source path claiming multiple module identities",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("already associated")
            && message.contains("one library/module identity per canonical source path")
            && message.contains("app::main")
            && message.contains("app::shadow"),
        "expected import graph path/module identity error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_stale_resolved_roots_and_entry_before_loading_inputs() {
    let entry_root = common::temp_artifact_path("laniusc_package_manifest", "stale_entry", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&entry_root, "stale-entry");
    std::fs::remove_file(&entry_path).expect("remove resolved package entry");
    std::fs::create_dir(&entry_path).expect("replace resolved package entry with directory");

    let err = PackageLockfile::load_json_file(&lockfile_path)
        .expect_err("stale package lockfile should reject a non-file entry");
    let message = format!("{err:?}");
    assert!(
        message.contains("entry") && message.contains("no longer resolves to a file"),
        "expected stale lockfile error to mention non-file entry, got {message}"
    );
    assert!(
        !message.contains("input digest mismatch") && !message.contains("import graph changed"),
        "stale resolved entry should fail before input or import graph validation, got {message}"
    );

    std::fs::remove_dir_all(&entry_root).expect("remove stale entry temp root");

    let source_root =
        common::temp_artifact_path("laniusc_package_manifest", "stale_source_root", None);
    let (src_root, _, lockfile_path) =
        write_minimal_generated_lockfile(&source_root, "stale-source-root");
    std::fs::remove_dir_all(&src_root).expect("remove resolved package source root");
    std::fs::write(&src_root, "not a directory").expect("replace source root with file");

    let err = PackageLockfile::load_json_file(&lockfile_path)
        .expect_err("stale package lockfile should reject a non-directory source root");
    let message = format!("{err:?}");
    assert!(
        message.contains("source root") && message.contains("no longer resolves to a directory"),
        "expected stale lockfile error to mention non-directory source root, got {message}"
    );

    std::fs::remove_dir_all(&source_root).expect("remove stale source root temp root");
}

#[test]
fn package_lockfile_rejects_non_canonical_resolved_entry_path() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "non_canonical_entry", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "non-canonical-entry");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let non_canonical_entry = entry_path
        .parent()
        .expect("entry should have a parent")
        .join("..")
        .join("app")
        .join("main.lani");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .insert(
            "entry".to_string(),
            serde_json::Value::String(non_canonical_entry.display().to_string()),
        );
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let mut replaced_input_path = false;
    for file in input_files {
        let Some(path) = file.get_mut("path") else {
            continue;
        };
        if path.as_str() == Some(canonical_entry.as_str()) {
            *path = serde_json::Value::String(non_canonical_entry.display().to_string());
            replaced_input_path = true;
        }
    }
    assert!(
        replaced_input_path,
        "generated lockfile should include the entry in input identity"
    );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject non-canonical resolved entry paths");
    let message = format!("{err:?}");
    assert!(
        message.contains("entry") && message.contains("canonical resolved path"),
        "expected canonical resolved entry path error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_non_canonical_input_identity_path() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "non_canonical_input", None);
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "non-canonical-input");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let non_canonical_entry = entry_path
        .parent()
        .expect("entry should have a parent")
        .join("..")
        .join("app")
        .join("main.lani");

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let entry_input = input_files
        .iter_mut()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include the entry in input identity");
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(non_canonical_entry.display().to_string()),
        );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile should reject non-canonical input identity paths");
    let message = format!("{err:?}");
    assert!(
        message.contains("input file") && message.contains("canonical resolved path"),
        "expected canonical input identity path error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_non_canonical_missing_input_identity_path() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "non_canonical_missing_input",
        None,
    );
    let (_, entry_path, lockfile_path) =
        write_minimal_generated_lockfile(&root, "non-canonical-missing-input");
    let lockfile_json = std::fs::read_to_string(&lockfile_path).expect("read generated lockfile");
    let canonical_entry = std::fs::canonicalize(&entry_path)
        .expect("canonicalize generated entry")
        .display()
        .to_string();
    let non_canonical_missing_input = entry_path
        .parent()
        .expect("entry should have a parent")
        .join("..")
        .join("missing")
        .join("ghost.lani");
    assert!(
        !non_canonical_missing_input.exists(),
        "fixture path should stay missing so validation cannot rely on filesystem canonicalization"
    );

    let mut document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");
    let input_files = document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    let entry_input = input_files
        .iter_mut()
        .find(|file| file.get("path").and_then(|path| path.as_str()) == Some(&canonical_entry))
        .expect("generated lockfile should include the entry in input identity");
    entry_input
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(non_canonical_missing_input.display().to_string()),
        );

    let tampered_lockfile_json =
        serde_json::to_string_pretty(&document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json).expect_err(
        "missing input paths should still reject non-canonical resolved replay metadata",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("input file")
            && message.contains("canonical resolved path")
            && message.contains("parent-directory"),
        "expected canonical input identity path error before replay consistency, got {message}"
    );
    assert!(
        !message.contains("missing from input identity")
            && !message.contains("no longer matches persisted input identity"),
        "non-canonical persisted paths should not be reported as stale replay state, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_source_metadata_requires_lani_source_paths() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "source_path_extension", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn value() -> i32 {
    return 11;
}
"#,
    )
    .expect("write package helper source");

    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::value();
}
"#,
    )
    .expect("write package entry source");

    let non_source_path = app_root.join("notes.txt");
    std::fs::write(&non_source_path, "not a Lanius source file\n")
        .expect("write non-source package file");
    let canonical_non_source = std::fs::canonicalize(&non_source_path)
        .expect("canonicalize non-source package file")
        .display()
        .to_string();

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "source-path-extension",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_json = lockfile
        .to_json_pretty()
        .expect("serialize package lockfile with import graph");
    let document =
        serde_json::from_str::<serde_json::Value>(&lockfile_json).expect("parse lockfile JSON");

    let mut tampered_document = document.clone();
    let input_files = tampered_document
        .get_mut("inputs")
        .and_then(|inputs| inputs.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source inputs");
    input_files
        .first_mut()
        .expect("generated lockfile should include at least one input")
        .as_object_mut()
        .expect("input identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(canonical_non_source.clone()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile input identities should only name .lani source files");
    assert_lockfile_source_extension_error(&err, "input file");

    let mut tampered_document = document.clone();
    let source_identity_files = tampered_document
        .get_mut("source_identities")
        .and_then(|identities| identities.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .expect("generated lockfile should persist source identities");
    source_identity_files
        .first_mut()
        .expect("generated lockfile should include at least one source identity")
        .as_object_mut()
        .expect("source identity entry should be an object")
        .insert(
            "path".to_string(),
            serde_json::Value::String(canonical_non_source.clone()),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile source identities should only name .lani source files");
    assert_lockfile_source_extension_error(&err, "source identity file");

    let mut tampered_document = document;
    let import_edges = tampered_document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .expect("generated lockfile should persist import graph edges");
    let helper_edge = import_edges
        .iter_mut()
        .find(|edge| edge.get("import_path").and_then(|path| path.as_str()) == Some("app::helper"))
        .expect("generated lockfile should include the helper import edge");
    helper_edge
        .as_object_mut()
        .expect("import graph edge should be an object")
        .insert(
            "target_path".to_string(),
            serde_json::Value::String(canonical_non_source),
        );
    let tampered_lockfile_json =
        serde_json::to_string_pretty(&tampered_document).expect("serialize tampered lockfile");
    let err = PackageLockfile::parse_json(&tampered_lockfile_json)
        .expect_err("lockfile import graph endpoints should only name .lani source files");
    assert_lockfile_source_extension_error(&err, "import graph target file");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_rejects_entry_paths_that_do_not_map_to_import_root_module_identity() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "entry_module_segment", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("main-file.lani"),
        r#"
module app::main_file;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source with non-module filename");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "entry-module-segment",
  "roots": ["src"],
  "entry": "src/app/main-file.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let err = manifest.resolve_from_dir(&root).expect_err(
        "package manifests should reject entries that cannot replay through import roots",
    );
    let message = format!("{err:?}");
    assert!(
        message.contains("package entry source-root relative path")
            && message.contains("main-file")
            && message.contains("invalid module path segment"),
        "expected package manifest entry module-path segment error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_rejects_imported_paths_that_map_to_reserved_module_segments() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "reserved_import", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    std::fs::write(
        app_root.join("fn.lani"),
        r#"
module app::fn;

pub const VALUE: i32 = 1;
"#,
    )
    .expect("write package source with reserved module segment");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import app::fn;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry importing a reserved module segment");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "reserved-import",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let err = resolved.load_path_manifest().expect_err(
        "package source-root replay should reject imported paths that cannot be source module identifiers",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("invalid import segment diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("import app::fn;"));
            assert_eq!(label.message, "invalid import path segment");
            assert!(
                diagnostic.notes.iter().any(|note| note
                    .contains("reserved keywords cannot be used as import path segments")),
                "expected reserved segment recovery note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned unsupported import diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_span_for_invalid_import_segment_punctuation() {
    let root =
        common::temp_artifact_path("laniusc_package_manifest", "invalid_import_segment", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::bad-name;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry with invalid import segment punctuation");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "invalid-import-segment",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "package replay should reject invalid import segment punctuation before source-root lookup",
    );
    assert_source_spanned_invalid_import_segment_error(
        &err,
        &entry_path,
        "import app::bad-name;",
        "bad-name",
    );

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should not persist invalid import segment metadata",
    );
    assert_source_spanned_invalid_import_segment_error(
        &err,
        &entry_path,
        "import app::bad-name;",
        "bad-name",
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_reports_source_span_for_import_segment_with_invalid_start() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "invalid_import_segment_start",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::9helper;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry with invalid import segment start");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "invalid-import-segment-start",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");

    let err = lockfile.load_path_manifest().expect_err(
        "package replay should reject invalid import segment starts before source-root lookup",
    );
    assert_source_spanned_invalid_import_segment_error(
        &err,
        &entry_path,
        "import app::9helper;",
        "9helper",
    );

    let err = lockfile.to_json_pretty().expect_err(
        "package lockfile generation should not persist import segments with invalid starts",
    );
    assert_source_spanned_invalid_import_segment_error(
        &err,
        &entry_path,
        "import app::9helper;",
        "9helper",
    );

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_manifest_accepts_deep_entry_module_paths() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "module_path_limit", None);
    let source_root = root.join("src");
    let parent_dir = source_root
        .join("a")
        .join("b")
        .join("c")
        .join("d")
        .join("e")
        .join("f")
        .join("g")
        .join("h");
    std::fs::create_dir_all(&parent_dir).expect("create deep package module path");

    let module_path = "a::b::c::d::e::f::g::h::i";
    let entry_path = parent_dir.join("i.lani");
    std::fs::write(
        &entry_path,
        format!(
            r#"
module {module_path};

fn main() {{
    return 0;
}}
"#
        ),
    )
    .expect("write too-deep package entry");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "module-path-limit",
  "roots": ["src"],
  "entry": "src/a/b/c/d/e/f/g/h/i.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("deep package entry paths should resolve without a segment cap");
    assert_eq!(resolved.entry, std::fs::canonicalize(&entry_path).unwrap());

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_accepts_deep_import_paths() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "deep_import_path", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let deep_import_path = "a::b::c::d::e::f::g::h::i";
    let entry_path = app_root.join("main.lani");
    let imported_path = root.join("src/a/b/c/d/e/f/g/h/i.lani");
    std::fs::create_dir_all(imported_path.parent().unwrap())
        .expect("create deep imported module directory");
    std::fs::write(
        &imported_path,
        format!("module {deep_import_path};\npub const VALUE: i32 = 1;\n"),
    )
    .expect("write deep imported module");
    std::fs::write(
        &entry_path,
        format!(
            r#"
module app::main;

import {deep_import_path};

fn main() {{
    return 0;
}}
"#
        ),
    )
    .expect("write package entry with overdeep import path");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "deep-import-path",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let path_manifest = lockfile
        .load_path_manifest()
        .expect("package replay should preserve deep import metadata");
    assert!(
        path_manifest
            .files
            .iter()
            .any(|file| { file.path == std::fs::canonicalize(&imported_path).unwrap() })
    );
    lockfile
        .to_json_pretty()
        .expect("deep import graph metadata should serialize");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_accepts_deep_imported_module_declarations() {
    let root = common::temp_artifact_path(
        "laniusc_package_manifest",
        "deep_imported_module_path",
        None,
    );
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let deep_module_path = "a::b::c::d::e::f::g::h::i";
    let helper_path = root.join("src/a/b/c/d/e/f/g/h/i.lani");
    std::fs::create_dir_all(helper_path.parent().unwrap()).expect("create deep helper directory");
    std::fs::write(
        &helper_path,
        format!(
            r#"
module {deep_module_path};

pub const VALUE: i32 = 1;
"#
        ),
    )
    .expect("write imported source with overdeep module declaration");
    std::fs::write(
        app_root.join("main.lani"),
        r#"
module app::main;

import a::b::c::d::e::f::g::h::i;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry importing helper");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "deep-imported-module-path",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    lockfile
        .to_json_pretty()
        .expect("package replay should serialize arbitrary-depth module metadata");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

#[test]
fn package_lockfile_rejects_deep_module_paths_that_do_not_match_file_mapping() {
    let root = common::temp_artifact_path("laniusc_package_manifest", "deep_module_path", None);
    let app_root = root.join("src").join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let deep_module_path = "a::b::c::d::e::f::g::h";
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        format!(
            r#"
module {deep_module_path};

fn main() {{
    return 0;
}}
"#
        ),
    )
    .expect("write deep-module package entry");

    let manifest = PackageManifest::parse_json(
        r#"
{
  "package": "deep-module-path",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}
"#,
    )
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(&root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let err = lockfile
        .to_json_pretty()
        .expect_err("lockfile generation should reject module declarations that do not match source-root file paths");
    assert_source_spanned_module_file_mapping_error(&err, deep_module_path, "app::main");

    std::fs::remove_dir_all(&root).expect("remove package manifest temp root");
}

fn write_minimal_generated_lockfile(root: &Path, package: &str) -> (PathBuf, PathBuf, PathBuf) {
    let src_root = root.join("src");
    let app_root = src_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

fn main() {
    return 0;
}
"#,
    )
    .expect("write package entry source");

    let manifest = PackageManifest::parse_json(&format!(
        r#"
{{
  "package": "{package}",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}}
"#
    ))
    .expect("parse package manifest JSON");
    let resolved = manifest
        .resolve_from_dir(root)
        .expect("resolve package manifest paths");
    let lockfile =
        PackageLockfile::from_resolved_manifest(&resolved).expect("create package lockfile");
    let lockfile_path = root.join("lanius.lock.json");
    lockfile
        .write_json_file(&lockfile_path)
        .expect("write generated package lockfile");

    (src_root, entry_path, lockfile_path)
}

fn assert_lockfile_rejects(source: &str, expected: &str) {
    let err = PackageLockfile::parse_json(source).expect_err("lockfile should be rejected");
    let message = format!("{err:?}");
    assert!(
        message.contains(expected),
        "expected lockfile error to contain {expected:?}, got {message}"
    );
}

fn assert_canonical_section_file_order(document: &serde_json::Value, section: &str) {
    let identities = document
        .get(section)
        .and_then(|section| section.get("files"))
        .and_then(|files| files.as_array())
        .unwrap_or_else(|| panic!("generated lockfile should include {section}.files"))
        .iter()
        .map(|file| {
            let library_id = file
                .get("library_id")
                .and_then(|library_id| library_id.as_u64())
                .unwrap_or_else(|| panic!("{section}.files entry should include library_id"));
            let path = file
                .get("path")
                .and_then(|path| path.as_str())
                .unwrap_or_else(|| panic!("{section}.files entry should include path"))
                .to_string();
            (library_id, path)
        })
        .collect::<Vec<_>>();
    let mut sorted_identities = identities.clone();
    sorted_identities.sort();
    assert_eq!(
        identities, sorted_identities,
        "{section}.files should be persisted in canonical replay order"
    );
}

fn sort_lockfile_section_files(document: &mut serde_json::Value, section: &str) {
    let files = document
        .get_mut(section)
        .and_then(|section| section.get_mut("files"))
        .and_then(|files| files.as_array_mut())
        .unwrap_or_else(|| panic!("lockfile fixture should include {section}.files"));
    files.sort_by_key(|file| {
        let library_id = file
            .get("library_id")
            .and_then(|library_id| library_id.as_u64())
            .unwrap_or_else(|| panic!("{section}.files entry should include library_id"));
        let path = file
            .get("path")
            .and_then(|path| path.as_str())
            .unwrap_or_else(|| panic!("{section}.files entry should include path"))
            .to_string();
        (library_id, path)
    });
}

fn assert_ambiguous_source_root_import_error(
    err: &CompileError,
    import_path: &str,
    candidates: &[&Path],
) {
    let message = format!("{err:?}");
    assert!(
        message.contains("ambiguous source-root module")
            && message.contains(import_path)
            && message.contains("candidates"),
        "expected ambiguous source-root import error for {import_path}, got {message}"
    );
    for candidate in candidates {
        let canonical_candidate = std::fs::canonicalize(candidate)
            .expect("canonicalize expected source-root import candidate")
            .display()
            .to_string();
        assert!(
            message.contains(&canonical_candidate),
            "expected ambiguous source-root import error to mention {canonical_candidate}, got {message}"
        );
    }
}

fn assert_stdlib_nested_import_symlink_escape_error(
    err: &CompileError,
    importer: &Path,
    escaped_target: &Path,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-root escape diagnostic should point at the import");
            assert_eq!(
                label.path,
                std::fs::canonicalize(importer).expect("canonicalize stdlib importing source")
            );
            assert_eq!(label.source_line.as_deref(), Some("import core::shared;"));
            let escaped_target = std::fs::canonicalize(escaped_target)
                .expect("canonicalize escaped stdlib target")
                .display()
                .to_string();
            let message = diagnostic.render();
            assert!(message.contains("source-root module core::shared escapes source root"));
            assert!(message.contains(&escaped_target));
            assert!(message.contains("resolves outside source root"));
        }
        other => panic!("expected source-root escape diagnostic, got {other:?}"),
    }
}

fn assert_manifest_relative_path_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("must be relative")
            && message.contains("lockfiles record canonical absolute paths"),
        "expected manifest relative-path error for {label}, got {message}"
    );
}

fn assert_manifest_parent_path_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("normalized package-relative path")
            && message.contains("parent-directory components"),
        "expected manifest parent-path error for {label}, got {message}"
    );
}

fn assert_manifest_normalized_path_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("normalized package-relative path")
            && message.contains("current-directory"),
        "expected manifest normalized-path error for {label}, got {message}"
    );
}

fn assert_manifest_separator_path_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("'/' separators")
            && message.contains("backslash path separators"),
        "expected manifest separator error for {label}, got {message}"
    );
}

fn assert_manifest_portable_path_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("must not contain ':'")
            && message.contains("portable package-relative paths"),
        "expected manifest portable-path error for {label}, got {message}"
    );
}

fn assert_manifest_symlink_escape_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("resolves outside package manifest directory")
            && message.contains("symlinks"),
        "expected manifest symlink escape error for {label}, got {message}"
    );
}

fn assert_manifest_directory_scope_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("resolves to the package manifest directory")
            && message.contains("source or stdlib subdirectory"),
        "expected manifest directory-scope error for {label}, got {message}"
    );
}

fn assert_stdlib_user_back_edge_error(err: &CompileError) {
    let message = format!("{err:?}");
    assert!(
        message.contains("package boundary")
            && message.contains("stdlib")
            && message.contains("app::leaf")
            && message.contains("may not import package/user roots"),
        "expected stdlib/user package-boundary error, got {message}"
    );
}

fn assert_stdlib_user_library_dependency_error(err: &CompileError) {
    let message = format!("{err:?}");
    assert!(
        message.contains("package boundary")
            && message.contains("stdlib library 0")
            && message.contains("package/user library 1"),
        "expected stdlib/user library-dependency boundary error, got {message}"
    );
}

fn assert_library_dependency_without_edge_error(
    err: &CompileError,
    library_id: u32,
    depends_on_library_id: u32,
) {
    let message = format!("{err:?}");
    let dependency = format!("{library_id} -> {depends_on_library_id}");
    assert!(
        message.contains("import graph library dependency")
            && message.contains(dependency.as_str())
            && message.contains("no matching cross-library import edge"),
        "expected library-dependency/import-edge consistency error, got {message}"
    );
}

fn assert_duplicate_library_dependency_error(
    err: &CompileError,
    library_id: u32,
    depends_on_library_id: u32,
) {
    let message = format!("{err:?}");
    let dependency = format!("{library_id} -> {depends_on_library_id}");
    assert!(
        message.contains("duplicate import graph library dependency")
            && message.contains(dependency.as_str())
            && message.contains("one coarse dependency edge per library pair"),
        "expected duplicate library dependency error, got {message}"
    );
}

fn assert_artifact_source_input_collision(err: &CompileError) {
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact file")
            && message.contains("source input")
            && message.contains("produced artifact identities"),
        "expected artifact/source-input collision error, got {message}"
    );
}

fn assert_artifact_package_source_collision(err: &CompileError, path: &Path) {
    let canonical_path = std::fs::canonicalize(path)
        .expect("canonicalize package source artifact path")
        .display()
        .to_string();
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact file")
            && message.contains(canonical_path.as_str())
            && message.contains("package source root")
            && message.contains("produced artifact identities"),
        "expected artifact/package-source collision error, got {message}"
    );
}

fn assert_input_digest_mismatch_error(err: &CompileError, path: &Path) {
    let canonical_path = std::fs::canonicalize(path)
        .expect("canonicalize package input path")
        .display()
        .to_string();
    let message = format!("{err:?}");
    assert!(
        message.contains("input digest mismatch") && message.contains(canonical_path.as_str()),
        "expected stale input digest error for {canonical_path}, got {message}"
    );
}

fn assert_duplicate_artifact_path_error(err: &CompileError, path: &Path) {
    let canonical_path = std::fs::canonicalize(path)
        .expect("canonicalize duplicate package artifact")
        .display()
        .to_string();
    let message = format!("{err:?}");
    assert!(
        message.contains("duplicate artifact path")
            && message.contains("unique across targets and kinds")
            && message.contains(canonical_path.as_str()),
        "expected duplicate artifact path error, got {message}"
    );
}

fn assert_reserved_artifact_kind_error(err: &CompileError, kind: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact kind")
            && message.contains(kind)
            && message.contains("reserved for compiler module, import, semantic, or link evidence")
            && message.contains("control-plane path/digest metadata"),
        "expected reserved artifact kind error, got {message}"
    );
}

fn assert_empty_artifact_error(err: &CompileError, path: &Path) {
    let canonical_path = std::fs::canonicalize(path)
        .expect("canonicalize empty package artifact")
        .display()
        .to_string();
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact file")
            && message.contains(canonical_path.as_str())
            && message.contains("byte length must be greater than zero")
            && message.contains("concrete artifact bytes"),
        "expected empty artifact identity error, got {message}"
    );
}

fn assert_entry_source_extension_error(err: &CompileError) {
    let message = format!("{err:?}");
    assert!(
        message.contains("entry") && message.contains(".lani source file extension"),
        "expected entry source extension error, got {message}"
    );
}

fn assert_duplicate_manifest_source_root_error(err: &CompileError) {
    let message = format!("{err:?}");
    assert!(
        message.contains("duplicate package source root") && message.contains("src"),
        "expected duplicate manifest source-root error, got {message}"
    );
}

fn assert_invalid_package_name_error(err: &CompileError, package: &str) {
    let message = format!("{err:?}");
    assert_invalid_package_name_message(&message, package);
}

fn assert_invalid_package_name_message(message: &str, package: &str) {
    assert!(
        message.contains("invalid package name")
            && message.contains(package)
            && message.contains("dot-separated ASCII package segments")
            && message.contains("start and end"),
        "expected invalid package-name error for {package}, got {message}"
    );
}

fn assert_lockfile_source_extension_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label) && message.contains(".lani source file extension"),
        "expected lockfile source extension error for {label}, got {message}"
    );
}

fn assert_filesystem_root_import_root_error(err: &CompileError, label: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains(label)
            && message.contains("filesystem root")
            && message.contains("package-owned source directory")
            && message.contains("imports cannot resolve arbitrary absolute paths"),
        "expected filesystem-root lockfile import-root error for {label}, got {message}"
    );
}

fn assert_duplicate_source_identity_module_error(err: &CompileError, module_path: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains("duplicate source identity module")
            && message.contains(module_path)
            && message.contains("one source file per module identity"),
        "expected duplicate source identity module error for {module_path}, got {message}"
    );
}

fn assert_module_file_mapping_error(err: &CompileError, declared: &str, expected: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains("declares module")
            && message.contains(declared)
            && message.contains("source-root relative path")
            && message.contains(expected),
        "expected module/file mapping error from {declared} to {expected}, got {message}"
    );
}

fn assert_source_spanned_module_path_separator_error(
    err: &CompileError,
    source_path: &Path,
    expected_source_line: &str,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("module path separator diagnostic should carry the separator span");
            assert_eq!(label.path, std::fs::canonicalize(source_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some(expected_source_line));
            assert_eq!(label.message, "module paths must use `::` separators");
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("package-name separators") && note.contains("module declarations")
                }),
                "expected module path separator note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("source module-path declarations")),
                "expected source module-path boundary note, got {:?}",
                diagnostic.notes
            );
            assert!(
                !diagnostic
                    .render()
                    .contains("module declaration does not match source-root path"),
                "dotted module declarations should fail before file/path mapping replay"
            );
        }
        other => panic!("expected source-spanned module path separator diagnostic, got {other:?}"),
    }
}

fn assert_source_spanned_module_file_mapping_error(
    err: &CompileError,
    declared: &str,
    expected: &str,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0015");
            assert_eq!(diagnostic.message, "invalid module path");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("module/file mapping diagnostic should carry a source label");
            assert!(
                label
                    .source_line
                    .as_deref()
                    .is_some_and(|line| line.contains(&format!("module {declared};"))),
                "expected module declaration source line for {declared}, got {:?}",
                label.source_line
            );
            assert_eq!(
                label.message,
                "module declaration does not match source-root path"
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains(&format!("declares module `{declared}`"))
                        && note.contains("source-root relative path")
                        && note.contains(expected)
                }),
                "expected module/file mapping note from {declared} to {expected}, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned module/file mapping diagnostic, got {other:?}"),
    }
}

fn assert_import_graph_module_endpoint_error(
    err: &CompileError,
    endpoint: &str,
    actual: &str,
    expected: &str,
) {
    let message = format!("{err:?}");
    let endpoint_label = format!("{endpoint} module path");
    assert!(
        message.contains("import graph edge")
            && message.contains(endpoint_label.as_str())
            && message.contains("source identity module")
            && message.contains(actual)
            && message.contains(expected),
        "expected import graph {endpoint} module endpoint error, got {message}"
    );
}

fn assert_missing_import_graph_endpoint_field_error(err: &CompileError, field: &str) {
    let message = format!("{err:?}");
    assert!(
        message.contains("parse package lockfile JSON")
            && message.contains("missing field")
            && message.contains(field),
        "expected missing import graph endpoint field {field} error, got {message}"
    );
}

fn assert_import_path_module_mismatch_error(
    err: &CompileError,
    import_path: &str,
    target_module_path: &str,
) {
    let message = format!("{err:?}");
    assert!(
        message.contains("import graph edge")
            && message.contains("import path")
            && message.contains(import_path)
            && message.contains("target module")
            && message.contains(target_module_path)
            && message.contains("declared module identity"),
        "expected import path/module identity mismatch error, got {message}"
    );
}

fn assert_missing_import_does_not_use_package_metadata(
    err: &CompileError,
    import_path: &str,
    source_path: &Path,
) {
    let searched_tail = import_path.replace("::", "/") + ".lani";
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0001");
            assert_eq!(
                diagnostic.message,
                format!("missing source-root module {import_path}")
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("missing import diagnostic should carry the import span");
            assert_eq!(
                label.path,
                std::fs::canonicalize(source_path).expect("canonicalize missing-import source")
            );
            let expected_source_line = format!("import {import_path};");
            assert_eq!(
                label.source_line.as_deref(),
                Some(expected_source_line.as_str())
            );
            assert_eq!(label.message, "imported here");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("searched") && note.contains(searched_tail.as_str())),
                "expected searched source-root candidate note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("control-plane metadata")
                        && note.contains("leading module declaration")),
                "expected package metadata boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned missing import diagnostic, got {other:?}"),
    }
}

fn assert_unsupported_quoted_import_form_error(err: &CompileError) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unsupported import diagnostic should carry the quoted import span");
            assert_eq!(
                label.source_line.as_deref(),
                Some(r#"import "app/helper.lani";"#)
            );
            let rendered = diagnostic.render();
            assert!(
                rendered.contains("package lockfiles require module-path imports here")
                    && rendered.contains("quoted imports are unsupported"),
                "expected unsupported quoted import diagnostic, got {rendered}"
            );
        }
        other => panic!("expected unsupported import diagnostic, got {other:?}"),
    }
}

fn assert_source_spanned_import_path_separator_error(
    err: &CompileError,
    source_path: &Path,
    expected_source_line: &str,
    expected_note_fragment: &str,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("path-separator import diagnostic should carry the separator span");
            assert_eq!(label.path, std::fs::canonicalize(source_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some(expected_source_line));
            assert_eq!(label.message, "import paths must use `::` separators");
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains(expected_note_fragment)
                        && note.contains("semantic module identity")
                }),
                "expected import path separator note, got {:?}",
                diagnostic.notes
            );
            assert!(
                !diagnostic
                    .render()
                    .contains("expected ';' after import path"),
                "path-shaped imports should not be reported as a truncated module path"
            );
        }
        other => {
            panic!("expected source-spanned import path separator diagnostic, got {other:?}")
        }
    }
}

fn assert_source_spanned_invalid_import_segment_error(
    err: &CompileError,
    source_path: &Path,
    expected_source_line: &str,
    rejected_segment: &str,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("invalid import segment diagnostic should carry a source label");
            assert_eq!(label.path, std::fs::canonicalize(source_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some(expected_source_line));
            assert_eq!(label.message, "invalid import path segment");
            assert!(
                diagnostic.render().contains(rejected_segment),
                "invalid import segment diagnostic should name the rejected segment"
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("ASCII identifiers")),
                "expected import identifier-shape note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned invalid import segment diagnostic, got {other:?}"),
    }
}

fn assert_source_spanned_self_import_error(
    err: &CompileError,
    source_path: &Path,
    import_path: &str,
) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("self-import diagnostic should carry the import declaration span");
            assert_eq!(label.path, std::fs::canonicalize(source_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some("import app::main;"));
            assert_eq!(label.message, "module imports itself");
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains(import_path) && note.contains("cannot import its own module path")
                }),
                "expected self-import note for {import_path}, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("import graph metadata")
                        && note.contains("source module identity")
                }),
                "expected package import graph boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned self-import diagnostic, got {other:?}"),
    }
}

fn assert_source_spanned_import_glob_error(err: &CompileError, source_path: &Path) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("glob import diagnostic should carry the glob span");
            assert_eq!(label.path, std::fs::canonicalize(source_path).unwrap());
            assert_eq!(label.source_line.as_deref(), Some("import app::*;"));
            assert_eq!(
                label.message,
                "import globs are not supported by package replay"
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("explicit module-path imports")
                        && note.contains("import app::module")
                }),
                "expected explicit import replay note, got {:?}",
                diagnostic.notes
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("parsed module/import records")),
                "expected parsed module/import boundary note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned glob import diagnostic, got {other:?}"),
    }
}

fn assert_unterminated_source_replay_comment_error(err: &CompileError) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("malformed comment diagnostic should carry a source label");
            assert_eq!(label.source_line.as_deref(), Some("/* import app::helper;"));
            assert_eq!(label.message, "unterminated block comment");
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("source-root replay") && note.contains("module/import metadata")
                }),
                "expected source-root replay note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned unterminated comment diagnostic, got {other:?}"),
    }
}

fn assert_malformed_source_replay_literal_error(err: &CompileError, label: &str) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let primary_label = diagnostic
                .primary_label
                .as_ref()
                .expect("malformed literal diagnostic should carry a source label");
            assert_eq!(primary_label.message, format!("malformed {label}"));
            assert!(
                primary_label
                    .source_line
                    .as_deref()
                    .is_some_and(|line| line.contains("unterminated")),
                "expected malformed literal source line, got {:?}",
                primary_label.source_line
            );
            assert!(
                diagnostic.notes.iter().any(|note| {
                    note.contains("source-root replay") && note.contains("module/import metadata")
                }),
                "expected source-root replay note, got {:?}",
                diagnostic.notes
            );
        }
        other => panic!("expected source-spanned malformed literal diagnostic, got {other:?}"),
    }
}

fn mutable_import_edge<'a>(
    document: &'a mut serde_json::Value,
    import_path: &str,
) -> &'a mut serde_json::Map<String, serde_json::Value> {
    document
        .get_mut("import_graph")
        .and_then(|graph| graph.get_mut("imports"))
        .and_then(|imports| imports.as_array_mut())
        .and_then(|imports| {
            imports.iter_mut().find(|edge| {
                edge.get("import_path").and_then(|path| path.as_str()) == Some(import_path)
            })
        })
        .expect("lockfile JSON should persist the requested import edge")
        .as_object_mut()
        .expect("import graph edge should be an object")
}

fn assert_import_graph_edge(
    document: &serde_json::Value,
    source_library_id: u32,
    source_module_path: &str,
    import_path: &str,
    target_library_id: u32,
    target_module_path: &str,
) {
    let imports = document
        .get("import_graph")
        .and_then(|graph| graph.get("imports"))
        .and_then(|imports| imports.as_array())
        .expect("lockfile JSON should persist import graph edges");
    assert!(
        imports.iter().any(|edge| {
            edge.get("source_library_id") == Some(&serde_json::Value::from(source_library_id))
                && edge
                    .get("source_module_path")
                    .and_then(|path| path.as_str())
                    == Some(source_module_path)
                && edge.get("import_path").and_then(|path| path.as_str()) == Some(import_path)
                && edge.get("target_library_id")
                    == Some(&serde_json::Value::from(target_library_id))
                && edge
                    .get("target_module_path")
                    .and_then(|path| path.as_str())
                    == Some(target_module_path)
        }),
        "lockfile import graph should persist {source_module_path} importing {import_path} as {target_module_path}"
    );
}

fn remove_lockfile_section(source: &str, section: &str) -> String {
    let mut document =
        serde_json::from_str::<serde_json::Value>(source).expect("parse generated lockfile JSON");
    document
        .as_object_mut()
        .expect("generated lockfile should be a JSON object")
        .remove(section)
        .unwrap_or_else(|| panic!("generated lockfile should contain {section}"));
    serde_json::to_string_pretty(&document).expect("serialize lockfile without section")
}
