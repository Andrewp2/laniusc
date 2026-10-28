//! Reductions, reverse folds, bounded progress and explicit matching traits.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_folds")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

#[test]
fn reductions_reverse_folds_and_bounded_progress_execute_without_hidden_pulls_or_allocations() {
    let bytes = compile("contracts.lani")
        .unwrap_or_else(|error| panic!("iterator fold contracts: {error}"));
    assert!(bytes.starts_with(b"\x7fELF"), "strict native contracts");
    let executable = common::TempArtifact::new("laniusc_iterator_fold", "contracts", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let events = common::TempArtifact::new("laniusc_iterator_fold", "allocation_trace", None);
    let output = common::process_output_with_timeout(
        "iterator fold direct-pull, generic payload and pure callback contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    common::assert_command_success("iterator fold native contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = fs::read_to_string(events.path()).unwrap();
    assert!(
        events.is_empty(),
        "pure folds neither allocate nor release: {events}"
    );
}

fn rejected_bounds(names: &[&str]) {
    for &name in names {
        let error = compile(name).expect_err("no matching required iterator/callback capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit bounded API use is rejected");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::iter::") && line.contains("rejected_fold_bound"),
            "relevant bound use in {name}: {label:?}"
        );
    }
}

#[test]
fn reduction_and_reverse_folds_require_matching_iterator_and_double_ended_items() {
    rejected_bounds(&[
        "negative_missing_iterator.lani",
        "negative_wrong_iterator_item.lani",
        "negative_missing_double_ended.lani",
        "negative_wrong_double_ended_item.lani",
    ]);
}

#[test]
fn bounded_and_fallible_folds_require_matching_folder_item_and_error_types() {
    rejected_bounds(&[
        "negative_missing_folder.lani",
        "negative_wrong_folder_item.lani",
        "negative_missing_try_folder.lani",
        "negative_wrong_try_folder_error.lani",
    ]);
}
