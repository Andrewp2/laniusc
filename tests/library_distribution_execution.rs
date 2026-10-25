#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compiler() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| repository().join("target/stdlib-build/debug/laniusc"))
}
fn copy_sources(source: &Path, target: &Path) {
    fs::create_dir_all(target).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let destination = target.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_sources(&entry.path(), &destination);
        } else if entry.path().extension().is_some_and(|ext| ext == "lani") {
            fs::copy(entry.path(), destination).unwrap();
        }
    }
}
fn package(root: &Path, main: &str) -> PathBuf {
    fs::create_dir_all(root.join("src/app")).unwrap();
    copy_sources(&repository().join("stdlib"), &root.join("stdlib"));
    copy_sources(&repository().join("extended"), &root.join("extended"));
    fs::write(root.join("src/app/main.lani"), main).unwrap();
    let manifest = root.join("lanius.package.json");
    fs::write(&manifest, r#"{"package":"library.bundle-test","roots":["src","extended"],"stdlib_root":"stdlib","entry":"src/app/main.lani"}"#).unwrap();
    manifest
}
fn vendor(manifest: &Path, out: &Path) -> Command {
    let mut command = Command::new("python3");
    command
        .arg(repository().join("tools/vendor_lanius.py"))
        .arg("--compiler")
        .arg(compiler())
        .arg("--manifest")
        .arg(manifest)
        .arg("--out")
        .arg(out);
    command
}
fn verify(root: &Path) -> std::process::Output {
    common::command_output_with_timeout(
        "bundle verify",
        Command::new("python3")
            .arg(repository().join("tools/vendor_lanius.py"))
            .arg("--verify")
            .arg(root),
    )
}
fn count_sources(root: &Path) -> usize {
    fs::read_dir(root)
        .unwrap()
        .map(|entry| {
            let path = entry.unwrap().path();
            if path.is_dir() {
                count_sources(&path)
            } else {
                usize::from(path.extension().is_some_and(|ext| ext == "lani"))
            }
        })
        .sum()
}

#[test]
fn selective_bundle_relocates_and_executes_without_original_sources() {
    let root = common::temp_artifact_path("library_distribution", "relocation", None);
    fs::create_dir_all(&root).unwrap();
    let input = root.join("original package ' quoted $() path");
    let main =
        fs::read_to_string(repository().join("sample_programs/library/expr_calc.lani")).unwrap();
    let manifest = package(&input, &main);
    let bundle = root.join("bundle");
    let output =
        common::command_output_with_timeout("vendor calculator", &mut vendor(&manifest, &bundle));
    common::assert_command_success("vendor calculator", &output);
    assert!(count_sources(&bundle) < count_sources(&input));
    assert!(bundle.join("stdlib/core/i64.lani").is_file());
    assert!(!bundle.join("stdlib/core/unicode.lani").exists());
    assert!(!bundle.join("stdlib/test/suite.lani").exists());
    common::assert_command_success("verify source bundle", &verify(&bundle));
    let moved = root.join("relocated bundle");
    fs::rename(&bundle, &moved).unwrap();
    fs::remove_dir_all(&input).unwrap();
    common::assert_command_success("verify relocated bundle", &verify(&moved));
    let lock = root.join("relocated.lock.json");
    let locked = common::command_output_with_timeout(
        "lock relocated bundle",
        Command::new(compiler())
            .args(["package", "lock", "--manifest"])
            .arg(moved.join("lanius.package.json"))
            .arg("-o")
            .arg(&lock),
    );
    common::assert_command_success("lock relocated bundle", &locked);
    let executable = root.join("calculator");
    let compiled = common::codegen_command_output_with_timeout(
        "compile relocated calculator",
        Command::new(compiler())
            .arg("--package-lockfile")
            .arg(&lock)
            .arg("-o")
            .arg(&executable),
    );
    common::assert_command_success("compile relocated calculator", &compiled);
    common::x86_jumps::assert_x86_64_file_jumps_stay_in_functions(&executable);
    let input_file = root.join("calculator-input");
    fs::write(&input_file, b"1+2*3\n-(5+6)\n9223372036854775807\n").unwrap();
    let result = common::process_output_with_timeout(
        "run relocated calculator",
        Command::new(&executable).stdin(fs::File::open(&input_file).unwrap()),
        std::time::Duration::from_secs(5),
    );
    common::assert_command_success("run relocated calculator", &result);
    assert_eq!(result.stdout, b"7\n-11\n9223372036854775807\n");
    assert!(result.stderr.is_empty());
    common::assert_command_success("verify bundle after compilation", &verify(&moved));
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn distribution_rejects_limits_tampering_and_existing_destinations() {
    let root = common::temp_artifact_path("library_distribution", "failures", None);
    fs::create_dir_all(&root).unwrap();
    let input = root.join("input");
    let manifest = package(
        &input,
        "module app::main; import app; import core::option; fn main() -> i32 { return app::zero()+core::option::unwrap_or(core::option::Some(0),1); }\n",
    );
    // Both a module file and a nested module directory are valid. Inventory
    // ordering must compare complete relative strings, not Path components.
    fs::write(
        input.join("src/app.lani"),
        "module app; pub fn zero() -> i32 { return 0; }\n",
    )
    .unwrap();
    let limited = root.join("limited");
    let result = common::command_output_with_timeout(
        "bundle file limit",
        vendor(&manifest, &limited).args(["--max-files", "1"]),
    );
    assert_eq!(result.status.code(), Some(1));
    assert!(!limited.exists());
    let bundle = root.join("bundle");
    common::assert_command_success(
        "vendor small package",
        &common::command_output_with_timeout(
            "vendor small package",
            &mut vendor(&manifest, &bundle),
        ),
    );
    let before = fs::read(bundle.join("SHA256SUMS")).unwrap();
    let second = root.join("same-content-other-location");
    common::assert_command_success(
        "repeat deterministic bundle",
        &common::command_output_with_timeout(
            "repeat deterministic bundle",
            &mut vendor(&manifest, &second),
        ),
    );
    assert_eq!(fs::read(second.join("SHA256SUMS")).unwrap(), before);
    let again = common::command_output_with_timeout(
        "reject existing bundle",
        &mut vendor(&manifest, &bundle),
    );
    assert_eq!(again.status.code(), Some(1));
    assert_eq!(fs::read(bundle.join("SHA256SUMS")).unwrap(), before);
    let value = bundle.join("stdlib/core/option.lani");
    let original = fs::read(&value).unwrap();
    fs::write(&value, b"// changed\n").unwrap();
    assert_eq!(verify(&bundle).status.code(), Some(1));
    fs::write(&value, original).unwrap();
    common::assert_command_success("restored bundle", &verify(&bundle));
    fs::write(bundle.join("unlisted.lani"), "module injected::extra;\n").unwrap();
    assert_eq!(verify(&bundle).status.code(), Some(1));
    fs::remove_file(bundle.join("unlisted.lani")).unwrap();
    fs::remove_file(&value).unwrap();
    assert_eq!(verify(&bundle).status.code(), Some(1));
    let missing = package(
        &root.join("missing-import"),
        "module app::main; import does::not_exist; fn main() { return 0; }\n",
    );
    let failed = root.join("failed");
    let rejected = common::command_output_with_timeout(
        "reject unresolved package",
        &mut vendor(&missing, &failed),
    );
    assert_eq!(rejected.status.code(), Some(1));
    assert!(!failed.exists());
    fs::remove_dir_all(root).unwrap();
}
