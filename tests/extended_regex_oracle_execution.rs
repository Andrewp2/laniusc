#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
//! Differential oracle for `ext::regex`: find_iter with captures, template
//! replacement and the grep-like line filter, each against CPython `re` on
//! seeded grammar-generated patterns from the shared dialect subset.
//! See `docs/extended-regex-oracle.md` and
//! `tests/fixtures/extended/regex_oracle/oracle.py`.
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, time::Duration};

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

fn executable(root: &PathBuf, entry: &str, stem: &str) -> common::TempArtifact {
    let entry = root.join(entry);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(stem, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{stem}: {error}"));
    let exe = common::TempArtifact::new("laniusc_regex_oracle", stem, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn regex_find_replace_and_grep_agree_with_python_re_on_generated_patterns() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let input = executable(
        &root,
        "tests/fixtures/extended_library/regex_input.lani",
        "regex_input",
    );
    let replace = executable(
        &root,
        "sample_programs/library/regex_replace.lani",
        "regex_replace",
    );
    let grep = executable(&root, "sample_programs/library/text_grep.lani", "text_grep");
    let output = common::process_output_with_timeout(
        "regex Python oracle",
        std::process::Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/regex_oracle/oracle.py"))
            .arg(input.path())
            .arg(replace.path())
            .arg(grep.path()),
        Duration::from_secs(120),
    );
    let report = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "{report}\n{output:?}");
    for line in [
        "find_iter_captures 12000/12000",
        "replace_template 1000/1000",
        "grep_filter 1000/1000",
        "linear_time 5/5",
        "disagreements 0",
    ] {
        assert!(report.lines().any(|l| l == line), "missing {line:?} in\n{report}");
    }
}
