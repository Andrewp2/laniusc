#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture_root = root.join("tests/fixtures/compiler_empty_body");
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
    let bytes = compile(name).unwrap_or_else(|error| {
        panic!("{name}: empty blocks must emit callable void definitions: {error}")
    });
    let exe = common::TempArtifact::new("empty_body", "native", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::short_process_output_with_timeout(
        "empty void definitions preserve calls and adjacent payloads",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

fn reject(name: &str, expected_code: &str, source_call: &str) {
    let error =
        compile(name).expect_err("a required declaration cannot supply a missing implementation");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, expected_code, "{name}: {error:?}");
    let label = diagnostic
        .primary_label
        .expect("the invalid call needs a source location");
    assert!(label.path.ends_with(name), "{name}: {label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .is_some_and(|line| line.contains(source_call)),
        "{name}: {label:?}"
    );
}

#[test]
fn empty_void_definitions_execute_while_bodyless_trait_members_remain_required() {
    execute("native.lani");
    execute("empty_entry.lani");
    execute("bare_return_entry.lani");
    reject("missing_impl.lani", "LNC0008", "imported_destroy<Missing>");
    reject("bodyless_direct.lani", "LNC0027", "Missing::destroy_value");
    // Reuse the process after rejection to ensure required declarations did not
    // seed executable identities or displace the next program's empty symbols.
    execute("native.lani");
}
