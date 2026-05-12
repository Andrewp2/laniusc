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
fn default_compiler_records_resident_ll1_gpu_pipeline() {
    let compiler = include_str!("../src/compiler.rs");
    assert!(compiler.contains("with_recorded_resident_tokens"));
    assert!(compiler.contains("record_checked_resident_ll1_hir_artifacts"));
    assert!(compiler.contains("finish_recorded_resident_ll1_hir_check"));
    assert!(compiler.contains("Some(&bufs.token_file_id)"));
    assert!(compiler.contains("record_resident_token_buffer_with_hir_on_gpu"));
    assert!(compiler.contains("compile_source_to_wasm"));
    assert!(compiler.contains("record_wasm_from_gpu_token_buffer"));
    assert!(compiler.contains("compile_source_to_x86_64"));
    assert!(compiler.contains("prepare_source_for_gpu_codegen_from_path(path)?"));
    assert!(compiler.contains("GPU x86_64 codegen is not currently available"));
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
fn cli_x86_availability_claims_are_explicitly_unavailable() {
    let main = include_str!("../src/main.rs");
    assert!(main.contains("x86_64 currently reports unavailable"));
    assert!(main.contains("x86_64 is accepted only to report explicit unavailability"));
    assert!(!main.contains("supported targets: wasm, x86_64"));
    assert!(!main.contains("Emits x86_64 ELF or WASM"));
}

#[test]
fn gpu_device_does_not_request_wgpu_fallback_adapter() {
    let device = include_str!("../src/gpu/device.rs");
    assert!(device.contains("force_fallback_adapter: false"));
    assert!(device.contains("does not allow a CPU compiler fallback"));
}

#[test]
fn cpu_codegen_backends_are_deleted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for rel in [
        "src/codegen/c.rs",
        "src/codegen/wasm.rs",
        "src/codegen/cpu_wasm.rs",
        "src/codegen/cpu_native.rs",
        "src/codegen/gpu_c.rs",
        "tests/codegen_c.rs",
        "tests/sample_programs.rs",
    ] {
        assert!(!root.join(rel).exists(), "{rel} should not exist");
    }

    let codegen_mod = include_str!("../src/codegen/mod.rs");
    assert!(codegen_mod.contains("pub mod gpu_wasm;"));
    assert!(codegen_mod.contains("pub mod gpu_x86;"));
    assert!(!codegen_mod.contains("pub mod wasm;"));
    assert!(!codegen_mod.contains("pub mod cpu_wasm;"));
    assert!(!codegen_mod.contains("pub mod cpu_native;"));
    assert!(!codegen_mod.contains("pub mod c;"));
    assert!(!codegen_mod.contains("pub mod gpu_c;"));
}

#[test]
fn cpu_parser_and_rust_hir_frontend_are_deleted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for rel in [
        "src/parser/cpu.rs",
        "src/hir.rs",
        "tests/hir.rs",
        "tests/imports.rs",
        "tests/stdlib.rs",
        "src/bin/parse_gen_golden.rs",
    ] {
        assert!(!root.join(rel).exists(), "{rel} should not exist");
    }

    let lib_mod = include_str!("../src/lib.rs");
    let parser_mod = include_str!("../src/parser/mod.rs");
    assert!(!lib_mod.contains("pub mod hir;"));
    assert!(!parser_mod.contains("pub mod cpu;"));
}

#[test]
fn parser_cpu_oracles_are_explicitly_test_only() {
    let tables = include_str!("../src/parser/tables.rs");
    let parse_fuzz = include_str!("../src/bin/parse_fuzz.rs");
    assert!(tables.contains("Test-only host LL(1) oracle for parser tests and fuzz tooling"));
    assert!(tables.contains("The compiler must not call this"));
    assert!(tables.contains("test_cpu_ll1_production_stream"));
    assert!(tables.contains("test_cpu_ll1_production_stream_with_positions"));
    assert!(tables.contains("test_cpu_projected_production_stream"));
    assert!(tables.contains("not as a\n/// runtime parser fallback"));
    assert!(parse_fuzz.contains("test_cpu_oracle_only"));
    assert!(!parse_fuzz.contains("cpu_only"));
    assert!(parse_fuzz.contains("not part of the compiler pipeline"));
    assert!(parse_fuzz.contains("test CPU oracles exist only to validate GPU parser passes"));

    for source in [
        include_str!("../src/compiler.rs"),
        include_str!("../src/main.rs"),
    ] {
        assert!(!source.contains("test_cpu_ll1_production_stream"));
        assert!(!source.contains("test_cpu_projected_production_stream"));
    }

    for golden in [
        include_str!("../parser_tests/control.parse.json"),
        include_str!("../parser_tests/file.parse.json"),
        include_str!("../parser_tests/function.parse.json"),
    ] {
        assert!(golden.contains("\"test_cpu_oracle_only\": true"));
        assert!(!golden.contains("\"cpu_only\""));
    }
}

#[test]
fn cpu_lexer_oracle_is_explicitly_test_only() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    assert!(!root.join("src/lexer/cpu.rs").exists());
    assert!(!root.join("src/lexer/gpu/debug_checks.rs").exists());
    assert!(!root.join("src/lexer/gpu/debug_host.rs").exists());

    let lexer_mod = include_str!("../src/lexer/mod.rs");
    let test_cpu = include_str!("../src/lexer/test_cpu.rs");
    let lex_fuzz = include_str!("../src/bin/lex_fuzz.rs");
    assert!(lexer_mod.contains("pub mod test_cpu;"));
    assert!(!lexer_mod.contains("pub mod cpu;"));
    assert!(lexer_mod.contains("TEST-ONLY CPU lexer oracle"));
    assert!(lexer_mod.contains("must not call it or use it as a fallback"));
    assert!(test_cpu.contains("TEST-ONLY CPU lexer oracle"));
    assert!(test_cpu.contains("must not be used as a"));
    assert!(test_cpu.contains("lex_on_test_cpu"));
    assert!(lex_fuzz.contains("not part of the compiler pipeline"));
    assert!(lex_fuzz.contains("test CPU lexer oracle"));

    for source in [
        include_str!("../src/compiler.rs"),
        include_str!("../src/main.rs"),
        include_str!("../src/lexer/gpu/driver.rs"),
    ] {
        assert!(!source.contains("lex_on_test_cpu"));
        assert!(!source.contains("lexer::test_cpu"));
    }
}

#[test]
fn developer_compile_benchmark_stays_on_wasm_until_x86_is_wired() {
    let bench = include_str!("../src/bin/gpu_compile_bench.rs");
    assert!(bench.contains("compile_source_to_wasm_with_gpu_codegen_using"));
    assert!(bench.contains("unsupported --emit {other:?}; expected wasm"));
    assert!(!bench.contains("compile_source_to_x86_64_with_gpu_codegen"));
    assert!(!bench.contains("x86_64"));
}

#[test]
fn stdlib_docs_do_not_claim_removed_source_prepasses() {
    for (name, source) in [
        ("TODO.md", include_str!("../TODO.md")),
        ("stdlib/README.md", include_str!("../stdlib/README.md")),
        ("stdlib/PLAN.md", include_str!("../stdlib/PLAN.md")),
        (
            "stdlib/LANGUAGE_REQUIREMENTS.md",
            include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md"),
        ),
        (
            "stdlib/STANDARD_LIBRARY_SPEC.md",
            include_str!("../stdlib/STANDARD_LIBRARY_SPEC.md"),
        ),
    ] {
        for forbidden in [
            "imports are source-level includes expanded before lexing",
            "included explicitly before user code",
            "source expansion rewrites module declarations",
            "namespace bridge",
            "codegen-only scalar lowering",
            "conformance precheck",
            "type-check-only erasure path",
            "These exercise generic struct literals",
            "self receiver method calls",
            "for traversal over range-like seed structs",
            "These can lower as direct WASM imports",
            "lower as direct WASM imports",
            "It parses and imports",
            "Top-level primitive constants are available for source stdlib modules",
            "Generic function-call substitution or monomorphization",
            "type-argument inference/substitution or monomorphization exists",
            "the CPU parser accepts that surface",
            "`src/hir.rs` now provides",
            "GPU x86_64 ELF emission for the current sample-program subset",
            "the default x86_64 CLI path compile directly",
        ] {
            assert!(
                !source.contains(forbidden),
                "{name} still claims removed prepass behavior: {forbidden}"
            );
        }
    }
}

#[test]
fn leading_import_metadata_is_gpu_syntax_only() {
    let syntax = include_str!("../shaders/parser/syntax_tokens.slang");
    let parser_tests = include_str!("../tests/parser_tree.rs");
    let typecheck_tests = include_str!("../tests/type_checker_modules.rs");
    let requirements = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let readme = include_str!("../stdlib/README.md");
    let plan = include_str!("../stdlib/PLAN.md");

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
        typecheck_tests.contains("type_checker_accepts_same_source_qualified_value_calls_only"),
        "type-check tests should keep imports metadata-only while allowing bounded same-source qualified calls"
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
            source.contains("not resolved")
                || source.contains("not load files")
                || source.contains("not loaded or resolved")
                || source.contains("not loaded or\nresolved")
                || source.contains("not loaded, expanded, or resolved"),
            "{name} should say imports are not resolved"
        );
    }
}

#[test]
fn generic_function_call_docs_distinguish_simple_substitution() {
    for (name, source) in [
        ("stdlib/README.md", include_str!("../stdlib/README.md")),
        ("stdlib/PLAN.md", include_str!("../stdlib/PLAN.md")),
        (
            "stdlib/LANGUAGE_REQUIREMENTS.md",
            include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md"),
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

#[test]
fn module_import_metadata_and_path_import_resolver_are_gpu_resident() {
    let requirements = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let module_plan = include_str!("../docs/MODULE_RESOLUTION_GPU_PLAN.md");
    let type_checker = include_str!("../src/type_checker/gpu.rs");
    let clear_shader = include_str!("../shaders/type_checker/type_check_modules_00_clear.slang");
    let collect_shader =
        include_str!("../shaders/type_checker/type_check_modules_00_collect.slang");
    let collect_decls_shader =
        include_str!("../shaders/type_checker/type_check_modules_00_collect_decls.slang");
    let resolve_imports_shader =
        include_str!("../shaders/type_checker/type_check_modules_00_resolve_imports.slang");
    let scope_shader = include_str!("../shaders/type_checker/type_check_scope.slang");

    assert!(
        requirements.contains("module/import metadata slice")
            && requirements.contains("path-import resolver"),
        "LANGUAGE_REQUIREMENTS should describe the metadata slice and bounded path-import resolver"
    );
    assert!(
        module_plan.contains("GPU-resident sparse metadata artifact")
            && module_plan.contains("resolved path-import")
            && module_plan.contains("import_resolved_module_token")
            && module_plan.contains("Cross-file declaration")
            && module_plan.contains("visibility still does not exist"),
        "module plan should distinguish bounded import resolution from declaration visibility"
    );

    for needle in [
        "type_check_modules_00_clear",
        "type_check_modules_00_collect",
        "type_check_modules_00_collect_decls",
        "type_check_modules_00_resolve_imports",
        "type_check_resident_modules_clear",
        "type_check.modules.collect",
        "type_check.modules.collect_decls",
        "type_check.modules.resolve_imports",
        "module_item_kind",
        "module_path_start",
        "module_path_end",
        "module_path_hash",
        "import_enclosing_module_token",
        "import_target_kind",
        "import_resolved_module_token",
        "decl_item_kind",
        "decl_name_hash",
        "decl_name_len",
        "decl_namespace",
        "decl_visibility",
        "decl_file_id",
        "decl_hir_node",
    ] {
        assert!(
            type_checker.contains(needle),
            "GPU type checker should wire module/import metadata artifact: {needle}"
        );
    }

    for needle in [
        "RWStructuredBuffer<uint> module_item_kind",
        "RWStructuredBuffer<uint> module_path_hash",
        "RWStructuredBuffer<uint> import_target_kind",
        "RWStructuredBuffer<uint> import_resolved_module_token",
        "RWStructuredBuffer<uint> decl_item_kind",
        "RWStructuredBuffer<uint> decl_name_hash",
        "RWStructuredBuffer<uint> decl_name_len",
        "RWStructuredBuffer<uint> decl_namespace",
        "RWStructuredBuffer<uint> decl_visibility",
        "RWStructuredBuffer<uint> decl_file_id",
        "RWStructuredBuffer<uint> decl_hir_node",
    ] {
        assert!(
            clear_shader.contains(needle),
            "module metadata clear shader should initialize artifact: {needle}"
        );
    }

    for needle in [
        "MODULE_ITEM_MODULE",
        "MODULE_ITEM_IMPORT",
        "HIR_ITEM_KIND_MODULE",
        "HIR_ITEM_KIND_IMPORT",
        "StructuredBuffer<uint> hir_item_kind",
        "StructuredBuffer<uint> hir_item_path_start",
        "StructuredBuffer<uint> hir_item_path_end",
        "StructuredBuffer<uint> hir_item_file_id",
        "StructuredBuffer<uint> hir_item_import_target_kind",
        "HIR_ITEM_IMPORT_TARGET_PATH",
        "HIR_ITEM_IMPORT_TARGET_STRING",
        "IMPORT_TARGET_PATH",
        "IMPORT_TARGET_STRING",
        "path_hash",
        "collect_module",
        "collect_import",
    ] {
        assert!(
            collect_shader.contains(needle),
            "module metadata collect shader should build module/import artifact: {needle}"
        );
    }

    for needle in [
        "HIR_ITEM_KIND_CONST",
        "HIR_ITEM_KIND_FN",
        "HIR_ITEM_KIND_EXTERN_FN",
        "HIR_ITEM_KIND_STRUCT",
        "HIR_ITEM_KIND_ENUM",
        "HIR_ITEM_KIND_TYPE_ALIAS",
        "StructuredBuffer<uint> hir_item_kind",
        "StructuredBuffer<uint> hir_item_name_token",
        "StructuredBuffer<uint> hir_item_namespace",
        "StructuredBuffer<uint> hir_item_visibility",
        "StructuredBuffer<uint> hir_item_file_id",
        "RWStructuredBuffer<uint> decl_item_kind",
        "RWStructuredBuffer<uint> decl_name_hash",
        "RWStructuredBuffer<uint> decl_name_len",
        "RWStructuredBuffer<uint> decl_namespace",
        "RWStructuredBuffer<uint> decl_visibility",
        "RWStructuredBuffer<uint> decl_file_id",
        "RWStructuredBuffer<uint> decl_hir_node",
        "collect_declaration",
        "is_declaration_item",
        "decl_item_kind[name_i] = hir_item_kind[hir_i]",
        "decl_name_hash[name_i] = token_hash(name_i)",
        "decl_name_len[name_i] = token_len(name_i)",
    ] {
        assert!(
            collect_decls_shader.contains(needle),
            "declaration metadata collect shader should build AST/HIR declaration artifact: {needle}"
        );
    }
    assert!(
        !collect_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_shader.contains("record_error"),
        "metadata-only module slice must not accept or reject programs by itself"
    );
    assert!(
        !collect_decls_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_decls_shader.contains("record_error"),
        "metadata-only declaration slice must not accept or reject programs by itself"
    );
    assert!(
        !collect_shader.contains("uint kind = token_kind(i);"),
        "module/import metadata collection should be driven by HIR item records, not token-neighborhood discovery"
    );
    assert!(
        !collect_decls_shader.contains("token_kind("),
        "declaration metadata collection should use parser-owned HIR item fields, not classify tokens"
    );
    assert!(
        !collect_shader.contains("StructuredBuffer<uint> hir_kind")
            && !collect_shader.contains("StructuredBuffer<uint> hir_token_pos")
            && !collect_shader.contains("StructuredBuffer<uint> hir_token_end")
            && !collect_shader.contains("StructuredBuffer<uint> hir_token_file_id"),
        "module/import metadata collection should consume parser-owned HIR item fields instead of rediscovering item spans"
    );
    assert!(
        type_checker.contains("HirItemMetadataBuffers")
            && type_checker.contains("\"hir_item_kind\".into()")
            && type_checker.contains("\"hir_item_name_token\".into()")
            && type_checker.contains("\"hir_item_namespace\".into()")
            && type_checker.contains("\"hir_item_visibility\".into()")
            && type_checker.contains("\"hir_item_path_start\".into()")
            && type_checker.contains("\"hir_item_path_end\".into()")
            && type_checker.contains("\"hir_item_file_id\".into()")
            && type_checker.contains("\"hir_item_import_target_kind\".into()")
            && type_checker.contains("\"decl_item_kind\".into()")
            && type_checker.contains("\"decl_name_hash\".into()")
            && type_checker.contains("\"decl_name_len\".into()")
            && type_checker.contains("\"decl_namespace\".into()")
            && type_checker.contains("\"decl_visibility\".into()")
            && type_checker.contains("\"decl_file_id\".into()")
            && type_checker.contains("\"decl_hir_node\".into()"),
        "GPU type checker should bind parser-owned HIR item fields into module metadata collection"
    );
    assert!(
        !collect_shader.contains("token_kind(path_start_i)")
            && !collect_shader.contains("token_kind(item_start + 1u)"),
        "module/import metadata collection must not classify import targets by peeking at tokens"
    );
    assert!(
        resolve_imports_shader.contains("StructuredBuffer<uint> module_item_kind")
            && resolve_imports_shader.contains("StructuredBuffer<uint> module_path_hash")
            && resolve_imports_shader
                .contains("RWStructuredBuffer<uint> import_resolved_module_token")
            && resolve_imports_shader.contains("find_module_for_import")
            && resolve_imports_shader.contains("validate_duplicate_module")
            && resolve_imports_shader.contains("path_tokens_equal")
            && resolve_imports_shader.contains("record_error(import_i, ERR_UNRESOLVED_IDENT")
            && resolve_imports_shader
                .contains("record_error(import_i, ERR_BAD_HIR, IMPORT_TARGET_STRING)"),
        "path imports should resolve or reject through GPU module metadata"
    );
    assert!(
        !scope_shader.contains("module_item_kind[i] == MODULE_ITEM_IMPORT"),
        "scope must not own import rejection once the module resolver consumes import metadata"
    );
}

#[test]
fn parser_hir_item_field_metadata_is_tree_driven() {
    let parser_buffers = include_str!("../src/parser/gpu/buffers.rs");
    let parser_passes = include_str!("../src/parser/gpu/passes/mod.rs");
    let parser_driver = include_str!("../src/parser/gpu/driver.rs");
    let parser_readback = include_str!("../src/parser/gpu/readback.rs");
    let pass = include_str!("../src/parser/gpu/passes/hir_item_fields.rs");
    let shader = include_str!("../shaders/parser/hir_item_fields.slang");
    let parser_tests = include_str!("../tests/parser_tree.rs");

    for needle in [
        "hir_item_fields_params",
        "hir_item_kind",
        "hir_item_name_token",
        "hir_item_namespace",
        "hir_item_visibility",
        "hir_item_path_start",
        "hir_item_path_end",
        "hir_item_file_id",
        "hir_item_import_target_kind",
    ] {
        assert!(
            parser_buffers.contains(needle),
            "parser buffers should carry HIR item metadata: {needle}"
        );
    }

    for needle in [
        "hir_item_kind",
        "hir_item_name_token",
        "hir_item_namespace",
        "hir_item_visibility",
        "hir_item_path_start",
        "hir_item_path_end",
        "hir_item_file_id",
        "hir_item_import_target_kind",
    ] {
        assert!(
            parser_readback.contains(needle),
            "parser readback should expose HIR item metadata for tests: {needle}"
        );
    }

    assert!(
        parser_passes.contains("pub mod hir_item_fields;")
            && parser_passes.contains("hir_item_fields: hir_item_fields::HirItemFieldsPass")
            && parser_passes.contains("p.hir_item_fields.record_pass"),
        "parser pass list should wire the HIR item field pass"
    );
    assert!(
        parser_driver.contains("parser.hir_item_fields")
            && parser_driver.contains("self.passes.hir_item_fields.record_pass"),
        "resident LL(1) parser path should run HIR item metadata after HIR spans"
    );
    assert!(
        pass.contains("\"hir_item_fields\"")
            && pass.contains("\"node_kind\".into()")
            && pass.contains("\"parent\".into()")
            && pass.contains("\"first_child\".into()")
            && pass.contains("\"hir_kind\".into()")
            && pass.contains("\"hir_token_pos\".into()")
            && pass.contains("\"hir_token_end\".into()")
            && pass.contains("\"hir_token_file_id\".into()"),
        "Rust pass wrapper should bind tree/HIR inputs"
    );

    for needle in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> parent",
        "StructuredBuffer<uint> first_child",
        "RWStructuredBuffer<uint> hir_item_import_target_kind",
        "StructuredBuffer<uint> hir_kind",
        "StructuredBuffer<uint> hir_token_pos",
        "StructuredBuffer<uint> hir_token_end",
        "StructuredBuffer<uint> hir_token_file_id",
        "PROD_ITEM_FN",
        "PROD_PUB_FN",
        "PROD_ITEM_PUB",
        "PROD_IMPORT_PATH",
        "PROD_IMPORT_STRING",
        "import_target_kind",
        "parent_kind",
        "grandparent_kind",
        "is_private_top_level_child",
        "is_public_top_level_child",
        "hir_kind_matches_item_production",
    ] {
        assert!(
            shader.contains(needle),
            "HIR item metadata shader should derive declarations from AST/HIR arrays: {needle}"
        );
    }

    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_kind(",
        "same_text(",
        "find_",
        "for (uint j",
        "i - 1u",
        "record_error",
        "RWStructuredBuffer<uint> status",
    ] {
        assert!(
            !shader.contains(forbidden),
            "HIR item metadata must not rediscover declarations from token neighborhoods: {forbidden}"
        );
    }

    assert!(
        parser_tests.contains("gpu_ll1_hir_item_fields_are_ast_derived_and_exclude_methods")
            && parser_tests.contains("!fn_names.contains(&\"method\".to_string())"),
        "parser tests should prove item metadata excludes impl methods by ancestry"
    );
}

#[test]
fn source_file_metadata_slice_is_gpu_resident_and_single_source_only() {
    let requirements = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let readme = include_str!("../stdlib/README.md");
    let plan = include_str!("../stdlib/PLAN.md");
    let module_plan = include_str!("../docs/MODULE_RESOLUTION_GPU_PLAN.md");
    let buffers = include_str!("../src/lexer/gpu/buffers.rs");
    let driver = include_str!("../src/lexer/gpu/driver.rs");
    let passes = include_str!("../src/lexer/gpu/passes/mod.rs");
    let pass = include_str!("../src/lexer/gpu/passes/tokens_file_ids.rs");
    let shader = include_str!("../shaders/lexer/tokens_file_ids.slang");
    let dfa_01_shader = include_str!("../shaders/lexer/dfa_01_scan_inblock.slang");
    let dfa_03_shader = include_str!("../shaders/lexer/dfa_03_apply_block_prefix.slang");
    let tokens_build_shader = include_str!("../shaders/lexer/tokens_build.slang");
    let dfa_01_pass = include_str!("../src/lexer/gpu/passes/dfa_01_scan_inblock.rs");
    let dfa_03_pass = include_str!("../src/lexer/gpu/passes/dfa_03_apply_block_prefix.rs");
    let tokens_build_pass = include_str!("../src/lexer/gpu/passes/tokens_build.rs");
    let compiler = include_str!("../src/compiler.rs");
    let parser_driver = include_str!("../src/parser/gpu/driver.rs");
    let parser_buffers = include_str!("../src/parser/gpu/buffers.rs");
    let parser_direct_hir_shader = include_str!("../shaders/parser/direct_hir.slang");
    let parser_hir_nodes_shader = include_str!("../shaders/parser/hir_nodes.slang");
    let parser_hir_nodes_pass = include_str!("../src/parser/gpu/passes/hir_nodes.rs");
    let parser_syntax = include_str!("../src/parser/gpu/syntax.rs");
    let parser_syntax_shader = include_str!("../shaders/parser/syntax_tokens.slang");
    let calls_resolve_shader =
        include_str!("../shaders/type_checker/type_check_calls_03_resolve.slang");
    let modules_same_source_types_shader =
        include_str!("../shaders/type_checker/type_check_modules_01_same_source_types.slang");
    let modules_patch_visible_types_shader =
        include_str!("../shaders/type_checker/type_check_modules_02_patch_visible_types.slang");
    let parser_tests = include_str!("../tests/parser_tree.rs");
    let typecheck_tests = include_str!("../tests/type_checker_modules.rs");
    let lexer_tests = include_str!("../tests/lexer_retag.rs");

    for needle in [
        "source_file_count",
        "source_file_start",
        "source_file_len",
        "token_file_id",
    ] {
        assert!(
            buffers.contains(needle),
            "GPU lexer buffers should expose source-file metadata: {needle}"
        );
        assert!(
            shader.contains(needle),
            "source-file metadata shader should bind {needle}"
        );
    }

    assert!(
        passes.contains("pub mod tokens_file_ids;")
            && passes.contains("tokens_file_ids: tokens_file_ids::TokensFileIdsPass")
            && passes.contains("p.tokens_file_ids.record_pass"),
        "lexer pass list should run the token file-id pass after token compaction"
    );
    assert!(
        pass.contains("\"tokens_file_ids\"")
            && pass.contains("source_file_count")
            && pass.contains("token_file_id"),
        "Rust pass wrapper should bind source metadata buffers"
    );
    assert!(
        driver.contains("write_current_source_file_metadata")
            && driver.contains("write_buffer(&bufs.source_file_count, 0, &1u32.to_le_bytes())")
            && driver.contains("write_buffer(&bufs.source_file_start, 0, &0u32.to_le_bytes())")
            && driver.contains("write_buffer(&bufs.source_file_len, 0, &n.to_le_bytes())"),
        "GPU lexer driver should initialize the current single-source file table"
    );
    assert!(
        driver.contains("with_resident_source_pack_tokens")
            && driver.contains("with_recorded_resident_source_pack_tokens")
            && driver.contains("build_source_pack")
            && driver.contains("write_source_pack_metadata"),
        "GPU lexer driver should expose an explicit source-pack upload path without import expansion"
    );
    assert!(
        compiler.contains("type_check_source_pack_with_gpu")
            && compiler.contains("type_check_explicit_source_pack")
            && compiler.contains("with_recorded_resident_source_pack_tokens")
            && !compiler.contains("expand_source_imports"),
        "compiler should expose explicit source-pack type checking without CPU import expansion"
    );
    assert!(
        dfa_01_shader.contains("is_file_start")
            && dfa_01_shader.contains("state = gParams.start_state")
            && dfa_01_pass.contains("\"source_file_start\".into()"),
        "DFA block summaries should reset on GPU-visible file starts"
    );
    assert!(
        dfa_03_shader.contains("is_file_start")
            && dfa_03_shader.contains("state_before = gParams.start_state")
            && dfa_03_pass.contains("\"source_file_start\".into()"),
        "DFA prefix application should reset in-block state at file starts"
    );
    assert!(
        tokens_build_shader.contains("file_start_for_token_end")
            && tokens_build_shader
                .contains("start = max(start, file_start_for_token_end(end_excl))")
            && tokens_build_pass.contains("\"source_file_len\".into()"),
        "token construction should clamp starts to containing source files after skipped trivia"
    );
    assert!(
        shader.contains("MAX_FILES_SCAN")
            && shader.contains("for (uint f = 0u; f < files; f += 1u)")
            && shader.contains("token_file_id[k] = file_id;"),
        "token file-id shader should assign compacted tokens from GPU-visible file spans"
    );
    assert!(
        !shader.contains("status") && !shader.contains("record_error"),
        "source-file metadata pass must not accept or reject programs by itself"
    );
    assert!(
        parser_syntax.contains("record_token_buffer_check_with_file_ids")
            && parser_syntax.contains("default_token_file_id")
            && parser_syntax.contains("\"token_file_id\""),
        "GPU syntax checker should bind token_file_id with a single-source default"
    );
    assert!(
        parser_driver.contains("token_file_id_buf: Option<&wgpu::Buffer>")
            && parser_driver.contains("record_token_buffer_check_with_file_ids"),
        "resident parser syntax path should accept lexer-provided token_file_id metadata"
    );
    assert!(
        parser_driver.contains("pub struct RecordedResidentLl1HirCheck")
            && parser_driver.contains("syntax_check: super::syntax::RecordedSyntaxCheck")
            && parser_driver.contains("copy_buffer_to_buffer(")
            && parser_driver.contains("&bufs.default_token_file_id")
            && parser_driver.contains("finish_recorded_resident_ll1_hir_check")
            && parser_driver.contains("GpuSyntaxChecker::finish_recorded_check"),
        "resident LL(1) parser path should validate syntax and feed lexer token-file metadata into tree/HIR passes"
    );
    assert!(
        parser_syntax_shader.contains("StructuredBuffer<uint> token_file_id")
            && parser_syntax_shader.contains("uint token_file(uint i)")
            && parser_syntax_shader.contains("token_file(i) == INVALID")
            && parser_syntax_shader.contains("file_first_token")
            && parser_syntax_shader.contains("same_token_file"),
        "GPU syntax shader should consume token_file_id and validate file-local metadata"
    );
    assert!(
        parser_tests.contains("gpu_syntax_rejects_invalid_token_file_ids_from_gpu_metadata")
            && parser_tests
                .contains("gpu_syntax_treats_source_pack_module_import_metadata_file_locally")
            && typecheck_tests.contains(
                "type_checker_source_pack_resolves_path_import_metadata_without_visibility"
            )
            && lexer_tests.contains("gpu_lexer_records_source_pack_token_file_ids_on_gpu")
            && lexer_tests.contains("comment without newline"),
        "tests should prove syntax/type-check consume token_file_id metadata and source-pack lexing respects file starts"
    );
    assert!(
        parser_buffers.contains("default_token_file_id")
            && parser_buffers.contains("hir_token_file_id"),
        "parser buffers should carry default token file ids and HIR file-id sideband storage"
    );
    assert!(
        parser_driver.contains("token_file_id_buf.unwrap_or(&bufs.default_token_file_id)")
            && parser_driver.contains("\"token_file_id\".into()")
            && parser_driver.contains("\"hir_token_file_id\".into()"),
        "resident direct HIR bind groups should consume token_file_id and write hir_token_file_id"
    );
    assert!(
        parser_direct_hir_shader.contains("StructuredBuffer<uint> token_file_id")
            && parser_direct_hir_shader.contains("RWStructuredBuffer<uint> hir_token_file_id")
            && parser_direct_hir_shader.contains("hir_token_file_id[out_i] = token_file(i);"),
        "direct HIR shader should mirror token ownership into HIR file-id metadata"
    );
    assert!(
        parser_hir_nodes_shader.contains("RWStructuredBuffer<uint> hir_token_file_id")
            && parser_hir_nodes_shader.contains("StructuredBuffer<uint> token_file_id")
            && parser_hir_nodes_shader
                .contains("hir_token_file_id[i] = hir_file_for_emit_pos(emit_pos[i]);")
            && parser_hir_nodes_pass.contains("\"token_file_id\".into()")
            && parser_hir_nodes_pass.contains("\"hir_token_file_id\".into()"),
        "LL(1) HIR construction should derive HIR file ownership from token metadata"
    );

    for (name, shader) in [
        ("type_check_calls_03_resolve.slang", calls_resolve_shader),
        (
            "type_check_modules_01_same_source_types.slang",
            modules_same_source_types_shader,
        ),
        (
            "type_check_modules_02_patch_visible_types.slang",
            modules_patch_visible_types_shader,
        ),
    ] {
        assert!(
            shader.contains("StructuredBuffer<uint> module_item_kind")
                && shader.contains("StructuredBuffer<uint> module_path_start")
                && shader.contains("StructuredBuffer<uint> module_path_end")
                && shader.contains("token_belongs_to_module_metadata_ast_span")
                && shader.contains("parser/HIR item pass owns module/import header spans"),
            "{name} should suppress module metadata through parser-owned HIR spans"
        );
    }

    for (name, source) in [
        ("stdlib/LANGUAGE_REQUIREMENTS.md", requirements),
        ("stdlib/README.md", readme),
        ("stdlib/PLAN.md", plan),
        ("docs/MODULE_RESOLUTION_GPU_PLAN.md", module_plan),
    ] {
        let normalized = source
            .to_ascii_lowercase()
            .replace('`', "")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        assert!(
            normalized.contains("source-pack") || normalized.contains("source pack"),
            "{name} should document the explicit source-pack lexer/syntax groundwork"
        );
        assert!(
            normalized.contains("not load")
                || normalized.contains("does not load")
                || normalized.contains("not loaded"),
            "{name} should avoid claiming import loading"
        );
        assert!(
            (normalized.contains("does not") && normalized.contains("resolve"))
                || normalized.contains("does not resolve")
                || normalized.contains("not resolve"),
            "{name} should avoid claiming module/import resolution"
        );
        assert!(
            normalized.contains("parser-owned hir item spans")
                || normalized.contains("parser-owned hir item"),
            "{name} should document that module metadata semantics come from AST/HIR spans"
        );
    }
}

#[test]
fn generic_type_instance_metadata_and_bounded_consumers_are_gpu_resident() {
    let generics_plan = include_str!("../docs/GENERICS_GPU_PLAN.md");
    let semantics_paper = include_str!("../docs/ParallelLexingParsingSemanticAnalysis.md");
    let requirements = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let semantics_tests = include_str!("../tests/type_checker_semantics.rs");
    let type_checker = include_str!("../src/type_checker/gpu.rs");
    let tokens_shader = include_str!("../shaders/type_checker/type_check_tokens_min.slang");
    let collect_shader =
        include_str!("../shaders/type_checker/type_check_type_instances_01_collect.slang");
    let bind_shader =
        include_str!("../shaders/type_checker/type_check_type_instances_02_struct_fields.slang");
    let member_shader =
        include_str!("../shaders/type_checker/type_check_type_instances_03_member_results.slang");
    let init_shader = include_str!(
        "../shaders/type_checker/type_check_type_instances_04_struct_init_fields.slang"
    );
    let array_return_shader = include_str!(
        "../shaders/type_checker/type_check_type_instances_05_array_return_refs.slang"
    );
    let enum_ctor_shader =
        include_str!("../shaders/type_checker/type_check_type_instances_06_enum_ctors.slang");
    let array_index_shader = include_str!(
        "../shaders/type_checker/type_check_type_instances_07_array_index_results.slang"
    );

    assert!(
        generics_plan.contains("## Next Slice: GPU Type-Instance Metadata"),
        "GENERICS_GPU_PLAN should name the next generics slice"
    );
    assert!(
        generics_plan.contains("enables narrow consumers")
            && generics_plan.contains("GENERIC_ENUM_CTOR_OK"),
        "GENERICS_GPU_PLAN should distinguish metadata from bounded consumers"
    );
    assert!(
        generics_plan.contains("must not rediscover generic")
            && generics_plan.contains("arguments by walking item headers"),
        "generic substitution must not move into token-local scans"
    );
    assert!(
        semantics_paper.contains("data type resolution tree")
            && semantics_paper.contains("evaluating the node-local rules"),
        "paper text should describe type resolution forests and local validation"
    );
    assert!(
        requirements.contains("type_check_type_instances_07_array_index_results.slang")
            && requirements.contains("Generic array/slice calls")
            && requirements.contains("remain rejected"),
        "LANGUAGE_REQUIREMENTS should describe bounded generic array acceptance without claiming calls/codegen"
    );
    assert!(
        requirements.contains("bounded GPU-only consumer")
            && requirements.contains("concrete identifier returns"),
        "LANGUAGE_REQUIREMENTS should describe the bounded array-return consumer"
    );
    assert!(
        requirements.contains("Bounded generic enum constructor")
            && requirements.contains("Maybe<i32> = Some(1)"),
        "LANGUAGE_REQUIREMENTS should describe the bounded generic enum constructor consumer"
    );
    assert!(
        semantics_tests.contains("type_checker_accepts_concrete_identifier_array_returns_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_array_returns_outside_bounded_gpu_slice")
            && semantics_tests
                .contains("type_checker_accepts_contextual_generic_enum_constructors_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_invalid_generic_enum_constructor_payloads_on_gpu")
            && semantics_tests
                .contains("type_checker_accepts_generic_array_and_slice_elements_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_invalid_generic_array_element_returns_on_gpu"),
        "semantic tests should cover accepted and still-rejected bounded consumer slices"
    );

    for needle in [
        "type_check_type_instances_01_collect",
        "type_check.resident.type_instances_collect.pass",
        "type_check.type_instances_collect.pass",
        "type_expr_ref_tag",
        "type_instance_kind",
        "type_instance_decl_token",
        "type_instance_arg_count",
        "type_instance_arg_ref_tag",
        "type_instance_elem_ref_tag",
        "type_instance_len_kind",
        "fn_return_ref_tag",
        "member_result_ref_tag",
        "struct_init_field_expected_ref_tag",
        "type_check_type_instances_03_member_results",
        "type_check_type_instances_04_struct_init_fields",
        "type_check_type_instances_05_array_return_refs",
        "type_check.resident.type_instances_array_return_refs.pass",
        "type_check.type_instances_array_return_refs.pass",
        "type_check_type_instances_06_enum_ctors",
        "type_check.resident.type_instances_enum_ctors.pass",
        "type_check.type_instances_enum_ctors.pass",
        "type_check_type_instances_07_array_index_results",
        "type_check.resident.type_instances_array_index_results.pass",
        "type_check.type_instances_array_index_results.pass",
    ] {
        assert!(
            type_checker.contains(needle),
            "GPU type checker should wire type-instance metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_expr_ref_tag",
        "TYPE_REF_INSTANCE",
        "TYPE_INSTANCE_ARRAY",
        "TYPE_INSTANCE_SLICE",
        "type_instance_arg_count",
        "fn_return_ref_tag",
    ] {
        assert!(
            collect_shader.contains(needle),
            "type-instance shader should build metadata artifact: {needle}"
        );
    }
    assert!(
        bind_shader.contains("RWStructuredBuffer<uint> type_instance_decl_token")
            && bind_shader.contains("RWStructuredBuffer<uint> type_instance_arg_ref_tag")
            && bind_shader.contains("type_instance_state[i] = TYPE_INSTANCE_RESOLVED"),
        "type-instance binding pass should publish declaration and argument refs"
    );
    assert!(
        member_shader.contains("RWStructuredBuffer<uint> member_result_ref_tag")
            && member_shader.contains("substituted_ref")
            && member_shader.contains("visible_decl[base_i]"),
        "member-result pass should publish substituted member refs from declaration arrays"
    );
    assert!(
        init_shader.contains("RWStructuredBuffer<uint> struct_init_field_expected_ref_tag")
            && init_shader.contains("fn_return_ref_tag")
            && init_shader.contains("context_instance_for_struct_literal_head"),
        "struct-init pass should publish expected field refs from contextual instances"
    );
    assert!(
        !collect_shader.contains("status") && !collect_shader.contains("record_error"),
        "metadata-only slice must not accept or reject programs by itself"
    );
    assert!(
        array_return_shader.contains("ARRAY_RETURN_OK")
            && array_return_shader.contains("concrete_i32_array_instance")
            && array_return_shader.contains("same_concrete_array")
            && !array_return_shader.contains("record_error"),
        "array-return consumer should compare precomputed concrete array refs without issuing errors"
    );
    assert!(
        tokens_shader.contains("ARRAY_RETURN_OK")
            && tokens_shader.contains("call_return_type[return_i] != ARRAY_RETURN_OK"),
        "token checker should only consume the precomputed array-return sentinel"
    );
    assert!(
        enum_ctor_shader.contains("GENERIC_ENUM_CTOR_OK")
            && enum_ctor_shader.contains("instance_from_annotated_let")
            && enum_ctor_shader.contains("substituted_ref")
            && enum_ctor_shader.contains("type_instance_arg_ref_tag")
            && enum_ctor_shader.contains("kind == TK_LET_ASSIGN || kind == TK_ASSIGN")
            && !enum_ctor_shader.contains("record_error"),
        "generic enum constructor consumer should validate contextual refs and publish a sentinel without issuing errors"
    );
    assert!(
        tokens_shader.contains("GENERIC_ENUM_CTOR_OK")
            && tokens_shader.contains("call_return_type[callee_i] == GENERIC_ENUM_CTOR_OK"),
        "token checker should only consume the precomputed generic enum constructor sentinel"
    );
    assert!(
        array_index_shader.contains("type_instance_elem_ref_tag")
            && array_index_shader.contains("generic_param_decl_for_use")
            && array_index_shader.contains("call_return_type[i + 1u] = elem_ty")
            && !array_index_shader.contains("record_error"),
        "array-index consumer should publish precomputed element types without issuing errors"
    );
    assert!(
        tokens_shader.contains("call_return_type[cur + 1u]")
            && tokens_shader.contains("indexed_ty != TY_UNKNOWN"),
        "token checker should consume precomputed generic array index result types"
    );
}

#[test]
fn method_lookup_slice_is_gpu_resident_and_bounded() {
    let semantics_paper = include_str!("../docs/ParallelLexingParsingSemanticAnalysis.md");
    let requirements = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let type_checker = include_str!("../src/type_checker/gpu.rs");
    let clear_shader = include_str!("../shaders/type_checker/type_check_methods_01_clear.slang");
    let collect_shader =
        include_str!("../shaders/type_checker/type_check_methods_02_collect.slang");
    let resolve_shader =
        include_str!("../shaders/type_checker/type_check_methods_03_resolve.slang");

    assert!(
        semantics_paper.contains("Function Resolution")
            && semantics_paper.contains("function application nodes")
            && semantics_paper.contains("corresponding function declaration node"),
        "paper text should describe function-call resolution to declaration nodes"
    );
    assert!(
        requirements.contains("bounded GPU resolver")
            && requirements.contains("concrete inherent calls"),
        "LANGUAGE_REQUIREMENTS should describe the current method-call slice"
    );

    for needle in [
        "type_check_methods_01_clear",
        "type_check_methods_02_collect",
        "type_check_methods_03_resolve",
        "type_check_resident_methods_clear",
        "type_check_resident_methods_resolve",
        "type_check.methods.collect",
        "type_check.methods.resolve",
        "method_decl_receiver_type",
        "method_decl_param_offset",
        "method_lookup_key",
        "method_lookup_receiver",
        "method_lookup_name_token",
        "method_lookup_fn",
    ] {
        assert!(
            type_checker.contains(needle),
            "GPU type checker should wire method metadata artifact: {needle}"
        );
    }

    for needle in [
        "RWStructuredBuffer<uint> method_decl_receiver_type",
        "RWStructuredBuffer<uint> method_lookup_fn",
        "method_lookup_receiver",
        "method_lookup_name_token",
    ] {
        assert!(
            clear_shader.contains(needle),
            "method clear shader should initialize metadata artifact: {needle}"
        );
    }

    for needle in [
        "RWStructuredBuffer<uint> method_decl_receiver_type",
        "RWStructuredBuffer<uint> method_lookup_fn",
        "collect_impl_methods",
        "impl_receiver_type_start",
        "method_decl_param_offset",
        "InterlockedCompareExchange(method_lookup_fn",
    ] {
        assert!(
            collect_shader.contains(needle),
            "method collect shader should build metadata artifact: {needle}"
        );
    }
    assert!(
        !collect_shader.contains("status") && !collect_shader.contains("record_error"),
        "metadata-only method slice must not accept or reject programs by itself"
    );

    for needle in [
        "StructuredBuffer<uint> method_lookup_fn",
        "RWStructuredBuffer<uint> call_fn_index",
        "RWStructuredBuffer<uint> call_return_type",
        "RWStructuredBuffer<uint> visible_type",
        "lookup_method",
        "validate_method_args",
        "MAX_METHOD_LOOKUP_PROBE",
    ] {
        assert!(
            resolve_shader.contains(needle),
            "method resolve shader should consume metadata artifact: {needle}"
        );
    }
}

#[test]
fn stdlib_docs_distinguish_for_type_checking_from_codegen() {
    let source = include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md");
    let normalized = source
        .to_ascii_lowercase()
        .replace('`', "")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    assert!(
        normalized.contains("for loops have gpu type-check coverage"),
        "LANGUAGE_REQUIREMENTS should record current GPU type-check support for for loops"
    );
    assert!(
        normalized.contains("backend lowering"),
        "LANGUAGE_REQUIREMENTS should keep for-loop execution/codegen separate"
    );
    assert!(
        !normalized.contains("fast-failing rejection test for trait declarations, trait impl declarations, for loops, and match"),
        "LANGUAGE_REQUIREMENTS should not claim for loops are still semantically rejected"
    );
}

#[test]
fn gpu_codegen_has_no_source_recognition_patterns() {
    let codegen_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("shaders")
        .join("codegen");
    for path in slang_files(&codegen_dir).into_iter().filter(|path| {
        path.file_stem().is_some_and(|stem| {
            let stem = stem.to_string_lossy();
            stem.starts_with("wasm") || stem.starts_with("x86")
        })
    }) {
        let shader = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for forbidden in [
            "source_contains",
            "pattern_byte",
            "P_ABS",
            "P_ARITH",
            "fn fact",
            "factorial",
            "abs_i32",
            "arithmetic_precedence",
            "bool_branch",
            "function_calls",
            "loop_control",
            "sample-specific",
            "canned",
        ] {
            assert!(
                !shader.contains(forbidden),
                "{} contains forbidden recognition pattern {forbidden:?}",
                path.display()
            );
        }
    }

    let body = include_str!("../shaders/codegen/wasm_body.slang");
    assert!(body.contains("StructuredBuffer<uint> visible_decl"));

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(gpu_wasm.contains("hir_kind_buf"));
    assert!(gpu_wasm.contains("visible_decl_buf"));
    assert!(gpu_wasm.contains("codegen.wasm.arrays"));
    assert!(gpu_wasm.contains("codegen.wasm.body"));
    assert!(gpu_wasm.contains("codegen.wasm.bool_body"));
    assert!(gpu_wasm.contains("codegen.wasm.module"));
    assert!(
        !gpu_wasm.contains("wasm_functions.spv") && !gpu_wasm.contains("codegen.wasm.functions"),
        "WASM generator must not initialize the stalled function-module shader path"
    );
}

#[test]
fn gpu_codegen_passes_do_not_use_one_lane_entrypoints() {
    for (name, source) in [
        (
            "wasm_simple_lets",
            include_str!("../shaders/codegen/wasm_simple_lets.slang"),
        ),
        (
            "wasm_arrays",
            include_str!("../shaders/codegen/wasm_arrays.slang"),
        ),
        (
            "wasm_body",
            include_str!("../shaders/codegen/wasm_body.slang"),
        ),
        (
            "wasm_bool_body",
            include_str!("../shaders/codegen/wasm_bool_body.slang"),
        ),
        (
            "wasm_module",
            include_str!("../shaders/codegen/wasm_module.slang"),
        ),
        (
            "wasm_functions_probe",
            include_str!("../shaders/codegen/wasm_functions_probe.slang"),
        ),
        (
            "wasm_functions",
            include_str!("../shaders/codegen/wasm_functions.slang"),
        ),
        (
            "x86_regalloc",
            include_str!("../shaders/codegen/x86_regalloc.slang"),
        ),
        (
            "x86_from_wasm",
            include_str!("../shaders/codegen/x86_from_wasm.slang"),
        ),
        (
            "pack_output",
            include_str!("../shaders/codegen/pack_output.slang"),
        ),
    ] {
        assert!(
            !source.contains("if (tid.x != 0u)"),
            "{name} should not gate shader work to a single lane"
        );
    }
}

#[test]
fn gpu_codegen_module_and_array_passes_are_parallel() {
    let arrays = include_str!("../shaders/codegen/wasm_arrays.slang");
    assert!(
        arrays.contains("uint i = tid.x;"),
        "wasm_arrays should assign token ownership from the dispatch id"
    );

    let module = include_str!("../shaders/codegen/wasm_module.slang");
    assert!(
        !module.contains("if (tid.x != 0u)"),
        "wasm_module should not copy the body from one lane"
    );
    assert!(
        module.contains("uint word_i = linear_dispatch_id(tid);"),
        "wasm_module should assign packed module words from the dispatch id"
    );
    assert!(
        !module.contains("word_i += WORKGROUP_SIZE"),
        "wasm_module should scale dispatch instead of looping one workgroup over output"
    );
    assert!(
        module.contains("status[1u] = ok ? 3u : 0u;"),
        "wasm_module should mark packed output for readback"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        !gpu_wasm.contains("dispatch_workgroups(1, 1, 1)"),
        "WASM codegen should not dispatch any emitter as a single workgroup"
    );
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups(simple_groups, 1, 1);"),
        "WASM arrays dispatch should scale with token capacity"
    );
    assert!(
        gpu_wasm.contains("workgroup_grid_1d(packed_output_groups)")
            && gpu_wasm.contains(
                "compute.dispatch_workgroups(packed_output_groups_x, packed_output_groups_y, 1);"
            ),
        "WASM module dispatch should scale with output capacity"
    );

    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(
        !gpu_x86.contains("dispatch_workgroups(1, 1, 1)"),
        "x86 codegen should not dispatch any emitter as a single workgroup"
    );
    assert!(
        gpu_x86.contains("let token_groups = token_capacity.div_ceil(256).max(1);"),
        "x86 reused WASM arrays dispatch should scale with token capacity"
    );
}

#[test]
fn gpu_codegen_emitters_write_output_across_lanes() {
    for (name, source, output) in [
        (
            "wasm_body",
            include_str!("../shaders/codegen/wasm_body.slang"),
            "body_words[cursor] = value & 0xffu;",
        ),
        (
            "wasm_functions",
            include_str!("../shaders/codegen/wasm_functions.slang"),
            "out_words[cursor] = value & 0xffu;",
        ),
        (
            "x86_from_wasm",
            include_str!("../shaders/codegen/x86_from_wasm.slang"),
            "out_words[cursor] = value & 0xffu;",
        ),
    ] {
        assert!(
            source.contains("uint lane = tid.x;")
                || source.contains("uint target = tid.x;")
                || source.contains("linear_dispatch_id(tid)")
                || source.contains("tid.x);"),
            "{name} should derive emission ownership from the dispatch id"
        );
        assert!(
            source.contains("cursor == target"),
            "{name} should shard byte emission across lanes"
        );
        assert!(
            source.contains(output),
            "{name} should still write generated bytes to the expected output buffer"
        );
    }
}

#[test]
fn gpu_wasm_bool_body_emits_top_level_statements_in_parallel() {
    let bool_body = include_str!("../shaders/codegen/wasm_bool_body.slang");
    assert!(
        bool_body.contains("is_top_level_statement(tid.x)"),
        "bool-body codegen should assign top-level statement ownership by dispatch id"
    );
    assert!(
        bool_body.contains("emit_statement(cursor, tid.x, true, tid.x);"),
        "bool-body codegen should emit each owned statement without replaying the full body"
    );
    assert!(
        bool_body.contains("BOOL_BODY_BYTES_PER_TOKEN")
            && bool_body.contains("tid.x * BOOL_BODY_BYTES_PER_TOKEN"),
        "bool-body codegen should compute per-statement output offsets without a quadratic prefix replay"
    );
    assert!(
        !bool_body.contains("top_level_statement_bytes_before(tid.x)"),
        "bool-body codegen should not rescan all prior tokens for every statement"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups(simple_groups, 1, 1);"),
        "WASM bool-body dispatch should scale with token capacity"
    );
    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(
        gpu_x86.contains("compute.dispatch_workgroups(token_groups, 1, 1);"),
        "x86 reused bool-body dispatch should scale with token capacity"
    );
}

#[test]
fn gpu_wasm_simple_let_fast_path_packs_output_bytes() {
    let simple = include_str!("../shaders/codegen/wasm_simple_lets.slang");
    assert!(
        simple.contains("emit_packed_out_word"),
        "simple-let fast path should pack final WASM bytes before readback"
    );
    assert!(
        simple.contains("out_words[word_i] = packed;"),
        "simple-let fast path should write one u32 per four output bytes"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        !gpu_wasm.contains("compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);"),
        "default WASM codegen should not launch the legacy body shader that stalls pipeline creation"
    );
    let compiler = include_str!("../src/compiler.rs");
    assert!(
        !compiler.contains("cpu_wasm::compile_source")
            && !compiler.contains("LANIUS_USE_GPU_WASM_CODEGEN"),
        "WASM codegen must not route through a CPU backend"
    );
    assert!(
        gpu_wasm.contains("let (len, source_buf)"),
        "WASM readback should detect packed output"
    );
    assert!(
        gpu_wasm.contains("len.div_ceil(4) * 4"),
        "packed WASM readback should copy packed bytes, not one u32 per byte"
    );
    assert!(
        gpu_wasm.contains("mode == 1 || mode == 5"),
        "WASM readback should use the explicit pack buffer for unpacked byte streams"
    );
}

#[test]
fn gpu_codegen_packs_remaining_unpacked_outputs_before_readback() {
    let pack = include_str!("../shaders/codegen/pack_output.slang");
    assert!(
        pack.contains("uint word_i = linear_dispatch_id(tid);"),
        "pack pass should assign packed words from dispatch id"
    );
    assert!(
        pack.contains("packed_words[word_i] ="),
        "pack pass should write one u32 per four emitted bytes"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(gpu_wasm.contains("codegen.wasm.pack_output"));
    assert!(gpu_wasm.contains("packed_out_buf"));
    assert!(gpu_wasm.contains("output_capacity.div_ceil(4)"));
    assert!(
        gpu_wasm.contains("mode == 1 || mode == 5"),
        "WASM readback should use pack output for function-path byte streams"
    );

    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(gpu_x86.contains("codegen.x86.pack_output"));
    assert!(gpu_x86.contains("packed_out_buf"));
    assert!(gpu_x86.contains("output_capacity.div_ceil(4)"));
    assert!(
        gpu_x86.contains("for &byte in data.iter().take(len)"),
        "x86 readback should read packed bytes, not one u32 per byte"
    );
}

#[test]
fn gpu_x86_codegen_module_exists_but_is_not_wired_into_compiler() {
    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(gpu_x86.contains("x86_regalloc.spv"));
    assert!(gpu_x86.contains("x86_from_wasm.spv"));
    assert!(gpu_x86.contains("wasm_body.spv"));
    assert!(gpu_x86.contains("wasm_bool_body.spv"));
    assert!(gpu_x86.contains("wasm_functions_probe.spv"));
    assert!(gpu_x86.contains("wasm_functions.spv"));
    assert!(gpu_x86.contains("codegen.x86.regalloc"));
    assert!(gpu_x86.contains("codegen.x86.elf"));
    assert!(gpu_x86.contains("let output_groups = (output_capacity as u32).div_ceil(256).max(1);"));
    assert!(gpu_x86.contains("workgroup_grid_1d(output_groups)"));
    assert!(gpu_x86.contains("compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);"));
    assert!(gpu_x86.contains("reg_map_buf"));
    assert!(gpu_x86.contains("reg_status_buf"));
    assert!(gpu_x86.contains("functions_status_buf"));
    assert!(gpu_x86.contains("codegen.x86.wasm_functions_probe"));
    assert!(
        gpu_x86.contains("compute.dispatch_workgroups_indirect(&bufs.functions_dispatch_buf, 0);"),
        "x86 reused function module lowering should launch through GPU-written indirect dispatch args"
    );
    assert!(gpu_x86.contains("compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);"));
    let compiler = include_str!("../src/compiler.rs");
    assert!(
        !compiler.contains("record_x86_from_gpu_token_buffer"),
        "x86 module should not be wired into the compiler until it has a non-hanging GPU path"
    );

    let regalloc = include_str!("../shaders/codegen/x86_regalloc.slang");
    assert!(regalloc.contains("RWStructuredBuffer<uint> reg_map"));
    assert!(regalloc.contains("RWStructuredBuffer<uint> reg_status"));
    assert!(regalloc.contains("visible_decl"));

    let lowering = include_str!("../shaders/codegen/x86_from_wasm.slang");
    assert!(lowering.contains("StructuredBuffer<uint> body_words"));
    assert!(lowering.contains("StructuredBuffer<uint> functions_words"));
    assert!(lowering.contains("StructuredBuffer<uint> reg_map"));
    assert!(lowering.contains("RWStructuredBuffer<uint> out_words"));
    assert!(lowering.contains("ELF_HEADER_SIZE"));
}

fn slang_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    collect_slang_files(root, &mut out);
    out
}

fn source_between<'a>(source: &'a str, start: &str, end: &str) -> &'a str {
    let start_idx = source
        .find(start)
        .unwrap_or_else(|| panic!("missing source marker: {start}"));
    let rest = &source[start_idx..];
    let end_idx = rest
        .find(end)
        .unwrap_or_else(|| panic!("missing source marker after {start}: {end}"));
    &rest[..end_idx]
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
