#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture_root = root.join("tests/fixtures/compiler_trait_return_context");
    let entry = fixture_root.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixture_root],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

fn execute(name: &str) {
    let bytes = compile(name)
        .unwrap_or_else(|error| panic!("{name}: expected executable control: {error}"));
    let exe = common::TempArtifact::new("trait_return_context", "native", None);
    // This checks all reachable x86 transfers before publishing the executable.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::short_process_output_with_timeout(
        "required method native payload checks",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

fn reject(name: &str, expected_code: &str) {
    let error =
        compile(name).expect_err("invalid required-method application must not emit an ELF");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, expected_code, "{name}: {error:?}");
    let label = diagnostic
        .primary_label
        .expect("source call must retain a diagnostic location");
    assert!(label.path.ends_with(name), "{name}: {label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .is_some_and(|line| line.contains("T::produce")),
        "{name}: {label:?}"
    );
}

#[test]
fn imported_required_method_returns_preserve_bound_identity_across_compilation_jobs() {
    execute("native.lani");
    reject("symbolic_conflict.lani", "LNC0006");
    reject("closed_conflict.lani", "LNC0006");
    reject("wrong_source.lani", "LNC0006");
    reject("missing_bound.lani", "LNC0027");
    // Reuse the same GPU process after trait jobs with a different ordinary
    // generic program. Sparse trait-owner metadata cannot classify this job.
    execute("ordinary_inference.lani");
    execute("native.lani");
}
