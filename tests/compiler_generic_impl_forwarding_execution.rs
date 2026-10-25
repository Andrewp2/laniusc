#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture_root = root.join("tests/fixtures/compiler_generic_impl_forwarding");
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
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("generic_impl_forwarding", "native", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::short_process_output_with_timeout(
        "forwarded implementation stream contracts",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{name}: {output:?}"
    );
    eprintln!("native {name}: exit 0, empty stdout/stderr");
}

fn reject(name: &str, source_call: &str) {
    let error = compile(name)
        .expect_err("an unrelated or missing trait implementation cannot authorize this call");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error:?}");
    let label = diagnostic
        .primary_label
        .expect("the bad consumer call needs a retained source location");
    assert!(label.path.ends_with(name), "{name}: {label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .is_some_and(|line| line.contains(source_call)),
        "{name}: {label:?}"
    );
    eprintln!(
        "rejected {name}: {} at {}:{}",
        diagnostic.code,
        label.path.display(),
        label.line
    );
}

#[test]
fn imported_generic_implementation_applications_preserve_stream_and_owner_contracts() {
    execute("controls.lani");
    execute("imported_write.lani");
    execute("contracts.lani");
    reject("missing_write_impl.lani", "core::io::write_all");
    reject("missing_read_impl.lani", "core::io::read_exact");
    reject("unrelated_owner_bound.lani", "core::io::write_all");
    // Exercise the same owners after failed proof jobs in one GPU process.
    execute("contracts.lani");
}

#[test]
fn typed_constant_implementation_applications_preserve_values_and_layouts() {
    execute("constant_application.lani");
}
