//! Lazy map insertion: executable callback, candidate recovery and generic contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_lazy_map/direct")
        .join(name)
}

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(name: &str) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_lazy_map", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        name,
        &mut Command::new(executable.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn lazy_maps_preserve_representatives_and_return_candidates_with_exact_callback_effects() {
    execute("contracts.lani");
}

#[test]
fn lazy_maps_execute_nested_options_arrays_and_zero_sized_values_and_reports() {
    execute("shapes.lani");
}

#[test]
fn lazy_maps_require_exact_producer_mapper_and_query_capabilities() {
    for name in [
        "negative_hash_producer.lani",
        "negative_hash_mapper.lani",
        "negative_tree_producer_result.lani",
        "negative_hash_query_hash.lani",
        "negative_tree_comparator.lani",
    ] {
        let error = compile(name).expect_err("lazy operation requires its declared capabilities");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("rejected_lazy_bound"),
            "{name}: {label:?}"
        );
    }
}
