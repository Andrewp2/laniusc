mod common;

use std::{fs, path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_descriptor_source_pack_requires_explicit_contract_output() {
    let root = common::temp_artifact_path("laniusc_cli_source_pack_contract", "root", None);
    let artifact_root = root.join("artifacts");
    let output = root.join("out");
    let missing_source = root.join("missing.lani");
    fs::create_dir_all(&artifact_root).expect("create artifact root");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("x86_64")
        .arg("--source-pack-descriptors")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("-o")
        .arg(&output)
        .arg(&missing_source);

    let output = common::command_output_with_timeout(
        "laniusc source-pack descriptor contract boundary",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "descriptor compile should fail before writing implicit target bytes\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--emit-contract"));
    assert!(stderr.contains("contract descriptors"));
    assert!(
        !stderr.contains("missing.lani"),
        "contract-output validation should run before touching source paths"
    );

    fs::remove_dir_all(&root).expect("remove temp artifact root");
}

#[test]
fn cli_emit_contract_single_input_uses_descriptor_path_instead_of_plain_compile() {
    let root =
        common::temp_artifact_path("laniusc_cli_source_pack_contract", "emit_contract", None);
    let missing_source = root.join("missing.lani");
    fs::create_dir_all(&root).expect("create emit-contract root");

    let mut command = Command::new(laniusc_bin());
    command.arg("--emit-contract").arg(&missing_source);

    let output =
        common::command_output_with_timeout("laniusc emit-contract source-pack path", &mut command);
    assert!(
        !output.status.success(),
        "--emit-contract must not fall through to plain single-file compile\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--source-pack-artifact-root"));
    assert!(
        !stderr.contains("missing.lani"),
        "descriptor-mode validation should run before loading the input source"
    );

    fs::remove_dir_all(&root).expect("remove emit-contract root");
}

#[test]
fn cli_descriptor_source_root_preparation_is_explicitly_unsupported() {
    let root = common::temp_artifact_path("laniusc_cli_source_pack_contract", "source_root", None);
    let source_root = root.join("missing_source_root");
    let artifact_root = root.join("artifacts");
    let output_path = root.join("out");
    let entry_path = root.join("app/main.lani");
    fs::create_dir_all(&root).expect("create source-root contract root");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("x86_64")
        .arg("--source-root")
        .arg(&source_root)
        .arg("--source-pack-descriptors")
        .arg("--emit-contract")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("-o")
        .arg(&output_path)
        .arg(&entry_path);

    let output = common::command_output_with_timeout(
        "laniusc source-root descriptor preparation boundary",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "source-root descriptor preparation should fail as explicitly unsupported\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--source-root and --stdlib-root"));
    assert!(stderr.contains("--source-pack-library-manifest"));
    assert!(
        !stderr.contains("canonicalize source root"),
        "descriptor/source-root guard should run before path loading"
    );
    assert!(
        !output_path.exists(),
        "unsupported descriptor/source-root compile must not leave contract or executable output"
    );

    fs::remove_dir_all(&root).expect("remove source-root contract root");
}

#[test]
fn cli_descriptor_package_manifest_preparation_is_explicitly_unsupported() {
    let root = common::temp_artifact_path("laniusc_cli_source_pack_contract", "package", None);
    let artifact_root = root.join("artifacts");
    let output_path = root.join("out");
    fs::create_dir_all(&root).expect("create package contract root");
    let manifest_path = root.join("lanius.package.json");
    fs::write(
        &manifest_path,
        r#"{
  "package": "app",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("x86_64")
        .arg("--package-manifest")
        .arg(&manifest_path)
        .arg("--source-pack-descriptors")
        .arg("--emit-contract")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("-o")
        .arg(&output_path);

    let output = common::command_output_with_timeout(
        "laniusc package descriptor preparation boundary",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package descriptor preparation should fail as explicitly unsupported\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-manifest"));
    assert!(stderr.contains("--source-pack-metadata-only"));
    assert!(stderr.contains("final source-pack descriptor"));
    assert!(
        !output_path.exists(),
        "unsupported package descriptor compile must not leave contract or executable output"
    );

    fs::remove_dir_all(&root).expect("remove package contract root");
}

#[test]
fn cli_descriptor_package_lockfile_preparation_is_explicitly_unsupported() {
    let root = common::temp_artifact_path("laniusc_cli_source_pack_contract", "lockfile", None);
    let artifact_root = root.join("artifacts");
    let output_path = root.join("out");
    let missing_lockfile = root.join("missing.lanius.lock.json");
    fs::create_dir_all(&root).expect("create package lockfile contract root");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("x86_64")
        .arg("--package-lockfile")
        .arg(&missing_lockfile)
        .arg("--source-pack-descriptors")
        .arg("--emit-contract")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("-o")
        .arg(&output_path);

    let output = common::command_output_with_timeout(
        "laniusc package lockfile descriptor preparation boundary",
        &mut command,
    );
    assert!(
        !output.status.success(),
        "package lockfile descriptor preparation should fail as explicitly unsupported\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--package-lockfile"));
    assert!(stderr.contains("--source-pack-metadata-only"));
    assert!(stderr.contains("final source-pack descriptor"));
    assert!(
        !stderr.contains("missing.lanius.lock.json"),
        "descriptor/package-lockfile guard should run before lockfile loading"
    );
    assert!(
        !output_path.exists(),
        "unsupported package lockfile descriptor compile must not leave contract or executable output"
    );

    fs::remove_dir_all(&root).expect("remove package lockfile contract root");
}
