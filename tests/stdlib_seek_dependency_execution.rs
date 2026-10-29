//! Positive admission probes for the buffered import / nested-bound dependency.
//! Explicitly run with --ignored; rejected compilation is a test failure.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command};

fn compile_and_execute(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/buffered_seek")
        .join(format!("{name}.lani"));
    let stdlib = root.join("stdlib");
    let context = format!("seek dependency {name}");
    let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("seek dependency {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_seek_dependency", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output =
        common::short_process_output_with_timeout(&context, &mut Command::new(file.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[ignore = "positive compiler-dependency probe; explicitly run to observe current admission"]
fn buffered_import_compiles_and_executes() {
    compile_and_execute("dependency_import");
}

#[test]
#[ignore = "positive compiler-dependency probe; explicitly run to observe current admission"]
fn nested_generic_trait_bound_compiles_and_executes() {
    compile_and_execute("dependency_nested_bound");
}

#[test]
#[ignore = "positive control paired with nested bound; explicitly run with dependency probes"]
fn flat_generic_trait_bound_control_compiles_and_executes() {
    compile_and_execute("dependency_flat_control");
}

fn compile_user_module_and_execute(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/buffered_seek");
    let entry = fixtures.join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let context = format!("seek imported dependency {name}");
    let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("seek imported dependency {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_seek_dependency", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output =
        common::short_process_output_with_timeout(&context, &mut Command::new(file.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[ignore = "positive imported compiler-dependency probe; explicitly run to observe admission"]
fn imported_nested_generic_trait_bound_compiles_and_executes() {
    compile_user_module_and_execute("dependency_imported_nested");
}

#[test]
#[ignore = "positive imported flat control; explicitly run with imported dependency probes"]
fn imported_flat_generic_trait_bound_control_compiles_and_executes() {
    compile_user_module_and_execute("dependency_imported_flat");
}

struct SnapshotRoot(common::TempArtifact);
impl Drop for SnapshotRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.0.path());
    }
}

fn copy_stdlib_tree(source: &std::path::Path, destination: &std::path::Path) {
    fs::create_dir(destination).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let target = destination.join(entry.file_name());
        let kind = entry.file_type().unwrap();
        if kind.is_dir() {
            copy_stdlib_tree(&entry.path(), &target);
        } else {
            assert!(
                kind.is_file(),
                "only actual stdlib files/directories are copied"
            );
            fs::copy(entry.path(), &target).unwrap();
            assert_eq!(fs::read(entry.path()).unwrap(), fs::read(target).unwrap());
        }
    }
}

fn exact_snapshot(root: &std::path::Path, name: &str) -> String {
    let directory = root.join("tests/fixtures/stdlib_foundation/buffered_seek/admission_snapshots");
    let full = fs::read_to_string(directory.join("full_failed.lani")).unwrap();
    // Reconstruct from the historical full source, independently of later
    // production corrections. The failed snapshot records hash 08adf326.
    let reader_start = full
        .find("pub impl<R> core::io::Seek for Reader<R>")
        .unwrap();
    let reader_end = full[reader_start..].find("pub impl<W> Writer<W>").unwrap() + reader_start;
    let reader_block = &full[reader_start..reader_end];
    let writer_start = full
        .find("\npub impl<W> core::io::Seek for Writer<W>")
        .unwrap();
    let writer_block = &full[writer_start..];
    assert_eq!(full.matches(reader_block).count(), 1);
    assert_eq!(full.matches(writer_block).count(), 1);
    let baseline = full
        .replacen(reader_block, "", 1)
        .replacen(writer_block, "", 1);
    let reader_only = full.replacen(writer_block, "", 1);
    let writer_only = full.replacen(reader_block, "", 1);
    for (variant, reconstructed) in [
        ("baseline", &baseline),
        ("reader_only", &reader_only),
        ("writer_only", &writer_only),
    ] {
        assert_eq!(
            &fs::read_to_string(directory.join(format!("{variant}.lani"))).unwrap(),
            reconstructed,
            "snapshot must differ only by deletion of the exact added Seek impls"
        );
    }
    assert!(matches!(name, "baseline" | "reader_only" | "writer_only"));
    fs::read_to_string(directory.join(format!("{name}.lani"))).unwrap()
}

fn compile_snapshot_and_execute(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let source = exact_snapshot(&root, name);
    let copied = SnapshotRoot(common::TempArtifact::new(
        "laniusc_seek_snapshot",
        name,
        None,
    ));
    copy_stdlib_tree(&root.join("stdlib"), copied.0.path());
    // This is the only override: one complete, exact historical module body.
    fs::write(copied.0.path().join("alloc/buffered.lani"), source).unwrap();
    let stdlib = copied.0.path().to_owned();
    let entry = root.join("tests/fixtures/stdlib_foundation/buffered_seek/dependency_import.lani");
    let context = format!("seek exact buffered snapshot {name}");
    let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("seek exact buffered snapshot {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_seek_dependency", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output =
        common::short_process_output_with_timeout(&context, &mut Command::new(file.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[ignore = "positive exact-module isolation; explicitly run to observe current admission"]
fn snapshot_baseline_buffered_import_compiles_and_executes() {
    compile_snapshot_and_execute("baseline");
}

#[test]
#[ignore = "positive exact-module isolation; explicitly run to observe current admission"]
fn snapshot_reader_only_buffered_import_compiles_and_executes() {
    compile_snapshot_and_execute("reader_only");
}

#[test]
#[ignore = "positive exact-module isolation; explicitly run to observe current admission"]
fn snapshot_writer_only_buffered_import_compiles_and_executes() {
    compile_snapshot_and_execute("writer_only");
}

#[test]
#[ignore = "positive literal-fallback source probe; explicitly run to observe current admission"]
fn wildcard_literal_zero_payload_compiles_and_executes() {
    compile_and_execute("dependency_wildcard_literal_zero");
}

#[test]
#[ignore = "positive typed-fallback control; explicitly run with literal source probe"]
fn wildcard_typed_zero_payload_control_compiles_and_executes() {
    compile_and_execute("dependency_wildcard_typed_zero");
}
