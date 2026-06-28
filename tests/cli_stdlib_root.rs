mod common;

use std::{fs, path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

fn assert_cli_fails_with(args: &[&std::path::Path], string_args: &[&str], context: &str) -> String {
    let mut command = Command::new(laniusc_bin());
    for arg in string_args {
        command.arg(arg);
    }
    for arg in args {
        command.arg(arg);
    }
    let output = common::command_output_with_timeout(context, &mut command);
    assert!(
        !output.status.success(),
        "{context} should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
fn cli_stdlib_root_x86_sample_build_command_runs_stdio_print_i32() {
    use std::os::unix::fs::PermissionsExt;

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let sample = repo_root.join("sample_programs/stdio_print_i32.lani");
    let expected_stdout =
        fs::read_to_string(repo_root.join("sample_programs/stdio_print_i32.stdout"))
            .expect("read stdio_print_i32 expected stdout");
    let stdlib_root = repo_root.join("stdlib");
    let exe = common::TempArtifact::new("laniusc_cli_stdlib_root", "stdio_print_i32", None);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--stdlib-root")
        .arg(&stdlib_root)
        .arg("--emit")
        .arg("x86_64")
        .arg("-o")
        .arg(exe.path())
        .arg(&sample);
    let output = common::codegen_command_output_with_timeout(
        "laniusc --stdlib-root stdio_print_i32 --emit x86_64",
        &mut command,
    );
    common::assert_command_success(
        "laniusc --stdlib-root stdio_print_i32 --emit x86_64",
        &output,
    );

    let mut permissions = fs::metadata(exe.path())
        .unwrap_or_else(|err| panic!("stat emitted executable {}: {err}", exe.path().display()))
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(exe.path(), permissions)
        .unwrap_or_else(|err| panic!("chmod emitted executable {}: {err}", exe.path().display()));

    let mut command = Command::new(exe.path());
    let output =
        common::short_process_output_with_timeout("run stdio_print_i32 sample", &mut command);
    common::assert_command_success("stdio_print_i32 sample execution", &output);
    let stdout = common::stdout_utf8("stdio_print_i32 sample stdout", output.stdout);
    assert_eq!(stdout, expected_stdout);
}

#[test]
fn cli_stdlib_root_reports_missing_import_before_gpu() {
    let root = common::temp_artifact_path("laniusc_cli_stdlib_root", "root", None);
    let stdlib_root = root.join("stdlib");
    fs::create_dir_all(stdlib_root.join("core")).expect("create temp stdlib root");
    let entry = common::TempArtifact::new("laniusc_cli_stdlib_root", "app", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::missing;
fn main() { return 0; }
"#,
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--stdlib-root")
        .arg(&stdlib_root)
        .arg(entry.path());
    let output = common::command_output_with_timeout("laniusc --stdlib-root missing", &mut command);
    assert!(
        !output.status.success(),
        "missing source-root import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0001]: missing source-root module core::missing"));
    assert!(stderr.contains("-->"));
    assert!(stderr.contains("core::missing"));
    assert!(stderr.contains(&entry.path().display().to_string()));
    assert!(stderr.contains("core/missing.lani"));
    assert!(stderr.contains("import core::missing;"));
    assert!(stderr.contains("^"));
    assert!(stderr.contains("imported here"));
    assert!(stderr.contains("= note: searched"));

    fs::remove_dir_all(&root).expect("remove temp stdlib root");
}

#[test]
fn cli_stdlib_root_reports_missing_std_import_before_gpu() {
    let root = common::temp_artifact_path("laniusc_cli_stdlib_root", "missing_std", None);
    let stdlib_root = root.join("stdlib");
    fs::create_dir_all(stdlib_root.join("std")).expect("create temp stdlib root");
    let entry = common::TempArtifact::new("laniusc_cli_stdlib_root", "std_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import std::io;
fn main() { return 0; }
"#,
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--stdlib-root")
        .arg(&stdlib_root)
        .arg(entry.path());
    let output = common::command_output_with_timeout(
        "laniusc --stdlib-root missing std import",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "missing stdlib-root std import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0001]: missing source-root module std::io"));
    assert!(stderr.contains("-->"));
    assert!(stderr.contains("std::io"));
    assert!(stderr.contains(&entry.path().display().to_string()));
    assert!(stderr.contains("std/io.lani"));
    assert!(stderr.contains("import std::io;"));
    assert!(stderr.contains("^"));
    assert!(stderr.contains("imported here"));
    assert!(stderr.contains("= note: searched"));
    assert!(
        !stderr.contains("GPU frontend error"),
        "stdlib-root missing std imports should be structured diagnostics: {stderr}"
    );

    fs::remove_dir_all(&root).expect("remove temp stdlib root");
}

#[test]
fn cli_source_root_and_stdlib_root_require_path_arguments() {
    let stderr = assert_cli_fails_with(&[], &["--source-root"], "laniusc --source-root missing");
    assert!(stderr.contains("--source-root requires a directory path"));

    let stderr = assert_cli_fails_with(&[], &["--stdlib-root"], "laniusc --stdlib-root missing");
    assert!(stderr.contains("--stdlib-root requires a directory path"));
}

#[test]
fn cli_source_roots_require_existing_directories() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "dir_validation", None);
    fs::create_dir_all(&root).expect("create temp validation root");
    let file_root = root.join("not_a_dir");
    fs::write(&file_root, "").expect("write non-directory root path");
    let entry = common::TempArtifact::new("laniusc_cli_source_root", "dir_entry", Some("lani"));
    entry.write_str("module app::main;\nfn main() { return 0; }\n");

    let stderr = assert_cli_fails_with(
        &[&file_root, entry.path()],
        &["--source-root"],
        "laniusc --source-root file path",
    );
    assert!(stderr.contains("source root"));
    assert!(stderr.contains("is not a directory"));

    fs::remove_dir_all(&root).expect("remove temp validation root");
}

#[test]
fn cli_source_roots_require_exactly_one_entry_input() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "entry_count", None);
    fs::create_dir_all(&root).expect("create temp source root");
    let entry_a = common::TempArtifact::new("laniusc_cli_source_root", "entry_a", Some("lani"));
    let entry_b = common::TempArtifact::new("laniusc_cli_source_root", "entry_b", Some("lani"));
    entry_a.write_str("module app::a;\nfn main() { return 0; }\n");
    entry_b.write_str("module app::b;\nfn main() { return 0; }\n");

    let stderr = assert_cli_fails_with(
        &[&root, entry_a.path(), entry_b.path()],
        &["--source-root"],
        "laniusc --source-root multiple entries",
    );
    assert!(stderr.contains("requires exactly one entry input file"));

    fs::remove_dir_all(&root).expect("remove temp entry-count root");
}

#[test]
fn cli_source_roots_reject_explicit_stdlib_sources() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "explicit_stdlib", None);
    fs::create_dir_all(&root).expect("create temp source root");
    let entry = common::TempArtifact::new("laniusc_cli_source_root", "entry", Some("lani"));
    let stdlib = common::TempArtifact::new("laniusc_cli_source_root", "stdlib", Some("lani"));
    entry.write_str("module app::main;\nfn main() { return 0; }\n");
    stdlib.write_str("module core::fake;\n");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--stdlib")
        .arg(stdlib.path())
        .arg("--source-root")
        .arg(&root)
        .arg(entry.path());
    let output = common::command_output_with_timeout(
        "laniusc root mode with explicit --stdlib",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "root mode with explicit --stdlib should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("do not combine"));
    assert!(stderr.contains("explicit --stdlib"));

    fs::remove_dir_all(&root).expect("remove temp explicit-stdlib root");
}

#[test]
fn cli_source_root_and_stdlib_root_reject_same_canonical_import_file() {
    let root = common::temp_artifact_path("laniusc_cli_stdlib_root", "shared_boundary", None);
    let shared_root = root.join("shared");
    fs::create_dir_all(shared_root.join("core")).expect("create shared source root");
    let shared_module = shared_root.join("core/i32.lani");
    fs::write(
        &shared_module,
        "module core::i32;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write shared module");
    let entry = common::TempArtifact::new(
        "laniusc_cli_stdlib_root",
        "shared_boundary_app",
        Some("lani"),
    );
    entry.write_str("module app::main;\nimport core::i32;\nfn main() { return 0; }\n");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--source-root")
        .arg(&shared_root)
        .arg("--stdlib-root")
        .arg(&shared_root)
        .arg(entry.path());
    let output = common::command_output_with_timeout(
        "laniusc shared source-root and stdlib-root import",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "same canonical import claimed by source and stdlib roots should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0003]: ambiguous source-root module core::i32"));
    assert!(stderr.contains(&entry.path().display().to_string()));
    assert!(stderr.contains("import core::i32;"));
    assert!(stderr.contains("ambiguous import"));
    assert!(stderr.contains("= note: candidates:"));
    assert!(stderr.contains("source root:"));
    assert!(stderr.contains("stdlib root:"));
    let canonical_module = fs::canonicalize(&shared_module)
        .expect("canonicalize shared module")
        .display()
        .to_string();
    assert_eq!(
        stderr.matches(&canonical_module).count(),
        2,
        "both boundaries should report the same canonical candidate once\nstderr:\n{stderr}"
    );

    fs::remove_dir_all(&root).expect("remove temp shared-boundary root");
}

#[test]
fn cli_source_root_reports_missing_import_before_gpu() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "root", None);
    let source_root = root.join("src");
    fs::create_dir_all(source_root.join("app")).expect("create temp source root");
    let entry = common::TempArtifact::new("laniusc_cli_source_root", "app", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::missing;
fn main() { return 0; }
"#,
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--source-root")
        .arg(&source_root)
        .arg(entry.path());
    let output = common::command_output_with_timeout("laniusc --source-root missing", &mut command);
    assert!(
        !output.status.success(),
        "missing source-root import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0001]: missing source-root module app::missing"));
    assert!(stderr.contains("-->"));
    assert!(stderr.contains("app::missing"));
    assert!(stderr.contains(&entry.path().display().to_string()));
    assert!(stderr.contains("app/missing.lani"));
    assert!(stderr.contains("import app::missing;"));
    assert!(stderr.contains("^"));
    assert!(stderr.contains("imported here"));
    assert!(stderr.contains("= note: searched"));

    fs::remove_dir_all(&root).expect("remove temp source root");
}

#[test]
fn cli_source_root_rejects_import_symlink_to_non_source_file_before_gpu() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "non_source_import", None);
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    fs::create_dir_all(&app_root).expect("create temp app source root");
    let non_source_path = app_root.join("helper.txt");
    fs::write(
        &non_source_path,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write non-source helper target");
    std::os::unix::fs::symlink(&non_source_path, app_root.join("helper.lani"))
        .expect("create source-looking helper symlink");
    let entry = common::TempArtifact::new(
        "laniusc_cli_source_root",
        "non_source_import_app",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--source-root")
        .arg(&source_root)
        .arg(entry.path());
    let output = common::command_output_with_timeout(
        "laniusc --source-root non-source canonical import target",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "non-source canonical import target should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr
            .contains("error[LNC0030]: source-root module app::helper resolves to non-source file")
    );
    assert!(stderr.contains(&entry.path().display().to_string()));
    assert!(stderr.contains("import app::helper;"));
    assert!(stderr.contains(&non_source_path.display().to_string()));
    assert!(stderr.contains("canonical .lani source files"));
    assert!(
        !stderr.contains("GPU frontend error"),
        "source-root non-source target failures should be structured diagnostics: {stderr}"
    );

    fs::remove_dir_all(&root).expect("remove temp source root");
}

#[test]
fn cli_source_root_reports_ambiguous_import_before_gpu() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "ambiguous", None);
    let left_root = root.join("left");
    let right_root = root.join("right");
    fs::create_dir_all(left_root.join("app")).expect("create left source root");
    fs::create_dir_all(right_root.join("app")).expect("create right source root");
    fs::write(
        left_root.join("app/helper.lani"),
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write left helper");
    fs::write(
        right_root.join("app/helper.lani"),
        "module app::helper;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write right helper");
    let entry = common::TempArtifact::new("laniusc_cli_source_root", "ambiguous_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--source-root")
        .arg(&left_root)
        .arg("--source-root")
        .arg(&right_root)
        .arg(entry.path());
    let output =
        common::command_output_with_timeout("laniusc --source-root ambiguous", &mut command);
    assert!(
        !output.status.success(),
        "ambiguous source-root import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0003]: ambiguous source-root module app::helper"));
    assert!(stderr.contains("app/helper.lani"));
    assert!(stderr.contains("import app::helper;"));
    assert!(stderr.contains("ambiguous import"));
    assert!(stderr.contains("= note: candidates:"));

    fs::remove_dir_all(&root).expect("remove temp ambiguous source roots");
}

#[test]
fn cli_source_root_deduplicates_repeated_roots_before_missing_import_diagnostic() {
    let root = common::temp_artifact_path("laniusc_cli_source_root", "dedup_roots", None);
    let source_root = root.join("src");
    fs::create_dir_all(source_root.join("app")).expect("create temp source root");
    let entry = common::TempArtifact::new("laniusc_cli_source_root", "dedup_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::missing;
fn main() { return 0; }
"#,
    );

    let repeated_root = source_root.join(".");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--source-root")
        .arg(&source_root)
        .arg("--source-root")
        .arg(&repeated_root)
        .arg(entry.path());
    let output =
        common::command_output_with_timeout("laniusc --source-root repeated root", &mut command);
    assert!(
        !output.status.success(),
        "missing source-root import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("error[LNC0001]: missing source-root module app::missing"));
    let searched_path = std::fs::canonicalize(&source_root)
        .expect("canonicalize temp source root")
        .join("app/missing.lani")
        .display()
        .to_string();
    assert_eq!(
        stderr.matches(&searched_path).count(),
        1,
        "repeated --source-root entries should not duplicate searched candidates\nstderr:\n{stderr}"
    );

    fs::remove_dir_all(&root).expect("remove temp repeated-root dir");
}
