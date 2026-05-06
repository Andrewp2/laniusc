use std::{
    fs,
    path::{Path, PathBuf},
};

#[test]
fn gpu_shader_entrypoints_are_wave_sized() {
    let shader_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("shaders");
    let mut checked = 0usize;
    for path in slang_files(&shader_dir) {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for (line_no, line) in source.lines().enumerate() {
            let Some(start) = line.find("[numthreads(") else {
                continue;
            };
            checked += 1;
            let args = &line[start + "[numthreads(".len()..];
            let first_arg = args
                .split(',')
                .next()
                .unwrap_or("")
                .trim()
                .trim_end_matches(')');
            assert!(
                matches!(first_arg, "256" | "WORKGROUP_SIZE" | "WG_SIZE"),
                "{}:{} uses non-wave numthreads: {}",
                path.display(),
                line_no + 1,
                line.trim()
            );
        }
    }
    assert!(checked > 0, "expected to find shader entrypoints");
}

#[test]
fn gpu_type_checker_has_no_generic_unsupported_language_error() {
    let type_checker_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("shaders")
        .join("type_checker");
    for path in slang_files(&type_checker_dir) {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        assert!(
            !source.contains("ERR_UNSUPPORTED"),
            "{} still contains a generic unsupported error",
            path.display()
        );
    }
}

#[test]
fn default_compiler_records_resident_gpu_pipeline() {
    let compiler = include_str!("../src/compiler.rs");
    assert!(compiler.contains("with_recorded_resident_tokens"));
    assert!(compiler.contains("record_checked_resident_ll1_hir_artifacts"));
    assert!(compiler.contains("record_resident_token_buffer_with_hir_on_gpu"));
    assert!(compiler.contains("record_c_from_gpu_token_buffer_with_hir"));
}

fn slang_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    collect_slang_files(root, &mut out);
    out
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
