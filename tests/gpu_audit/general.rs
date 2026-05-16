use std::{fs, path::Path};

use super::support::{slang_files, source_between};

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
fn default_compiler_records_resident_ll1_gpu_pipeline() {
    let compiler = include_str!("../../src/compiler.rs");
    let tokens_to_kinds = include_str!("../../shaders/parser/tokens_to_kinds.slang");
    assert!(compiler.contains("with_recorded_resident_tokens"));
    assert!(compiler.contains("record_checked_resident_ll1_hir_artifacts"));
    assert!(compiler.contains("finish_recorded_resident_ll1_hir_check"));
    assert!(compiler.contains("Some(&bufs.token_file_id)"));
    assert!(compiler.contains("record_resident_token_buffer_with_hir_items_on_gpu"));
    assert!(compiler.contains("GpuTypeCheckHirItemBuffers"));
    assert!(compiler.contains("compile_source_to_wasm"));
    assert!(compiler.contains("record_wasm_from_gpu_token_buffer"));
    assert!(compiler.contains("compile_source_to_x86_64"));
    assert!(compiler.contains("prepare_source_for_gpu_codegen_from_path(path)?"));
    assert!(compiler.contains("record_x86_elf_from_gpu_hir"));
    assert!(!compiler.contains("record_x86_from_gpu_token_buffer"));
    assert!(!compiler.contains("compile_expanded_source_to_x86_64(\"\").await"));
    assert!(!compiler.contains("LANIUS_USE_GPU_WASM_CODEGEN"));
    assert!(!compiler.contains("LANIUS_USE_GPU_X86_CODEGEN"));
    assert!(!compiler.contains("record_checked_resident_syntax_hir_artifacts"));
    assert!(!compiler.contains("finish_recorded_resident_syntax_hir_check"));
    assert!(!compiler.contains("parser.direct_hir.done"));
    assert!(!compiler.contains("parser.direct_hir"));
    assert!(!compiler.contains("direct_hir"));
    assert!(!compiler.contains("cpu_wasm"));
    assert!(!compiler.contains("cpu_native"));
    assert!(!compiler.contains("parse_source"));
    assert!(!compiler.contains("expand_source_imports"));
    assert!(!compiler.contains("expand_type_aliases"));
    assert!(!compiler.contains("lexer::test_cpu"));
    assert!(!compiler.contains("lex_on_test_cpu"));
    assert!(!compiler.contains("hir::parse_source"));
    assert!(!compiler.contains("emit_wasm"));
    assert!(!compiler.contains("emit_c"));
    assert!(!compiler.contains("compile_source_to_c"));
    assert!(
        tokens_to_kinds.contains("i >= gParams.token_capacity + 2u")
            && tokens_to_kinds.contains("else if (i < out_count)")
            && tokens_to_kinds.contains("token_kinds[i] = 0u"),
        "resident LL(1) token projection must clear reused token-kind tails so stale larger inputs cannot become trailing parser input"
    );

    for (name, path) in [
        (
            "type check",
            source_between(
                compiler,
                "async fn type_check_expanded_source",
                "pub async fn compile_source_to_wasm",
            ),
        ),
        (
            "WASM codegen",
            source_between(
                compiler,
                "async fn compile_expanded_source_to_wasm",
                "fn wasm_generator",
            ),
        ),
    ] {
        assert!(
            path.contains("record_checked_resident_ll1_hir_artifacts"),
            "{name} path must record the resident LL(1) tree/HIR artifacts"
        );
        assert!(
            path.contains("Some(&bufs.token_file_id)"),
            "{name} path must pass lexer token-file metadata into LL(1) HIR construction"
        );
        assert!(
            path.contains("finish_recorded_resident_ll1_hir_check"),
            "{name} path must finish the resident LL(1) HIR check"
        );
        assert!(
            !path.contains("record_checked_resident_syntax_hir_artifacts")
                && !path.contains("finish_recorded_resident_syntax_hir_check")
                && !path.contains("direct_hir"),
            "{name} path must not use the legacy direct-HIR resident parser"
        );
    }
}

#[test]
fn leading_import_metadata_is_gpu_syntax_only() {
    let syntax = include_str!("../../shaders/parser/syntax_tokens.slang");
    let parser_tests = include_str!("../../tests/parser_tree.rs");
    let typecheck_tests = include_str!("../../tests/type_checker_modules.rs");
    let requirements = include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md");
    let readme = include_str!("../../stdlib/README.md");
    let plan = include_str!("../../stdlib/PLAN.md");

    assert!(
        syntax.contains("void check_import_decl")
            && syntax.contains("is_leading_import_decl")
            && syntax.contains("token_in_leading_import_decl"),
        "GPU syntax should validate leading import metadata on GPU"
    );
    assert!(
        parser_tests.contains(
            "gpu_syntax_accepts_leading_import_metadata_and_rejects_invalid_module_metadata"
        ),
        "parser tests should cover import metadata acceptance"
    );
    assert!(
        typecheck_tests
            .contains("type_checker_accepts_qualified_function_calls_via_hir_value_consumer",)
            && typecheck_tests.contains("std::io::flush_stdout()")
            && typecheck_tests.contains("alloc::allocator::alloc(16, 4)"),
        "type-check tests should cover regular and extern qualified calls through the HIR value consumer"
    );
    for (name, source) in [
        ("stdlib/LANGUAGE_REQUIREMENTS.md", requirements),
        ("stdlib/README.md", readme),
        ("stdlib/PLAN.md", plan),
    ] {
        assert!(
            source.contains("metadata")
                && (source.contains("not loaded") || source.contains("not load files")),
            "{name} should say imports are metadata and not loaded"
        );
        assert!(
            source.contains("source-pack")
                || source.contains("source pack")
                || source.contains("not load files")
                || source.contains("not loaded or\nresolved")
                || source.contains("not loaded, expanded, or resolved"),
            "{name} should distinguish explicit source-pack path imports from host import loading"
        );
    }
}

#[test]
fn generic_function_call_docs_distinguish_simple_substitution() {
    for (name, source) in [
        ("stdlib/README.md", include_str!("../../stdlib/README.md")),
        ("stdlib/PLAN.md", include_str!("../../stdlib/PLAN.md")),
        (
            "stdlib/LANGUAGE_REQUIREMENTS.md",
            include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md"),
        ),
    ] {
        let lowercase = source
            .to_ascii_lowercase()
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        assert!(
            lowercase.contains("simple generic function-call substitution"),
            "{name} should describe simple call substitution"
        );
        assert!(
            lowercase.contains("gpu type-check coverage"),
            "{name} should say simple call substitution now has GPU type-check coverage"
        );
        assert!(
            lowercase.contains("full monomorphization") && lowercase.contains("separate"),
            "{name} should keep full monomorphization separate from call substitution"
        );
        assert!(
            !lowercase.contains("simple generic function-call substitution is not implemented"),
            "{name} should not claim simple call substitution is still unimplemented"
        );
    }
}
