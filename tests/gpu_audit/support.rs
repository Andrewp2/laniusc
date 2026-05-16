use std::{
    fs,
    path::{Path, PathBuf},
};

pub fn repo_path(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

pub fn repo_file(rel: &str) -> String {
    let path = repo_path(rel);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

pub fn assert_contains_all(source: &str, label: &str, needles: &[&str]) {
    for needle in needles {
        assert!(source.contains(needle), "{label} should contain {needle:?}");
    }
}

pub fn assert_contains_none(source: &str, label: &str, needles: &[&str]) {
    for needle in needles {
        assert!(
            !source.contains(needle),
            "{label} should not contain {needle:?}"
        );
    }
}

pub fn slang_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    collect_slang_files(root, &mut out);
    out
}

pub fn source_between<'a>(source: &'a str, start: &str, end: &str) -> &'a str {
    let start_idx = source
        .find(start)
        .unwrap_or_else(|| panic!("missing source marker: {start}"));
    let rest = &source[start_idx..];
    let end_idx = rest
        .find(end)
        .unwrap_or_else(|| panic!("missing source marker after {start}: {end}"));
    &rest[..end_idx]
}

pub fn type_checker_gpu_sources() -> String {
    [
        include_str!("../../src/type_checker/mod.rs"),
        include_str!("../../src/type_checker/bind_groups.rs"),
        include_str!("../../src/type_checker/bind_support.rs"),
        include_str!("../../src/type_checker/module_path.rs"),
        include_str!("../../src/type_checker/module_path_body.inc"),
        include_str!("../../src/type_checker/pass_loaders.rs"),
        include_str!("../../src/type_checker/record.rs"),
        include_str!("../../src/type_checker/resident.rs"),
        include_str!("../../src/type_checker/standalone.rs"),
        include_str!("../../src/type_checker/util.rs"),
    ]
    .join("\n")
}

fn collect_slang_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let entries =
        fs::read_dir(dir).unwrap_or_else(|err| panic!("read dir {}: {err}", dir.display()));
    for entry in entries {
        let path = entry
            .unwrap_or_else(|err| panic!("read dir entry in {}: {err}", dir.display()))
            .path();
        if path.is_dir() {
            collect_slang_files(&path, out);
        } else if path.extension().is_some_and(|ext| ext == "slang") {
            out.push(path);
        }
    }
}
