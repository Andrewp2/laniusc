use super::support::type_checker_gpu_sources;

#[test]
fn parser_hir_item_field_metadata_is_tree_driven() {
    let parser_buffers = include_str!("../../src/parser/buffers.rs");
    let parser_passes = include_str!("../../src/parser/passes/mod.rs");
    let parser_driver = include_str!("../../src/parser/driver.rs");
    let parser_readback = include_str!("../../src/parser/readback.rs");
    let pass = include_str!("../../src/parser/passes/hir_item_fields.rs");
    let decl_pass = include_str!("../../src/parser/passes/hir_item_decl_tokens.rs");
    let shader = include_str!("../../shaders/parser/hir_item_fields.slang");
    let decl_shader = include_str!("../../shaders/parser/hir_item_decl_tokens.slang");
    let generated_ids = include_str!("../../shaders/parser/generated_parse_production_ids.slang");
    let table_generator = include_str!("../../src/bin/parse_gen_tables.rs");
    let parser_tests = include_str!("../../tests/parser_tree.rs");

    for needle in [
        "hir_item_fields_params",
        "hir_item_kind",
        "hir_item_name_token",
        "hir_item_decl_token",
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
        "hir_item_decl_token",
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
            && parser_passes.contains("pub mod hir_item_decl_tokens;")
            && parser_passes.contains("hir_item_fields: hir_item_fields::HirItemFieldsPass")
            && parser_passes
                .contains("hir_item_decl_tokens: hir_item_decl_tokens::HirItemDeclTokensPass")
            && parser_passes.contains("p.hir_item_fields.record_pass"),
        "parser pass list should wire the HIR item field pass"
    );
    assert!(
        parser_driver.contains("parser.hir_item_fields")
            && parser_driver.contains("parser.hir_item_decl_tokens")
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
    assert!(
        decl_pass.contains("\"hir_item_decl_tokens\"")
            && decl_pass.contains("\"hir_item_kind\".into()")
            && decl_pass.contains("\"hir_token_pos\".into()")
            && decl_pass.contains("\"hir_item_decl_token\".into()"),
        "decl-token pass should bind only parser-owned item metadata"
    );
    assert!(
        shader.contains("import generated_parse_production_ids;")
            && !shader.contains("static const uint PROD_ITEM_FN =")
            && !shader.contains("static const uint PROD_TYPE_ALIAS =")
            && generated_ids.contains("static const uint PROD_ITEM_FN =")
            && generated_ids.contains("static const uint PROD_FN =")
            && generated_ids.contains("static const uint PROD_IMPORT =")
            && generated_ids.contains("static const uint PROD_MODULE =")
            && generated_ids.contains("static const uint PROD_TYPE_ALIAS =")
            && table_generator.contains("write_production_id_slang"),
        "HIR item metadata should import generated production IDs instead of embedding copied numeric ids"
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
    for needle in [
        "StructuredBuffer<uint> hir_item_kind",
        "StructuredBuffer<uint> hir_token_pos",
        "RWStructuredBuffer<uint> hir_item_decl_token",
        "has_declaration_target",
    ] {
        assert!(
            decl_shader.contains(needle),
            "HIR item declaration-token shader should project parser-owned declaration ids: {needle}"
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
        assert!(
            !decl_shader.contains(forbidden),
            "HIR item declaration-token metadata must not rediscover declarations from token neighborhoods: {forbidden}"
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
    let requirements = include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md");
    let readme = include_str!("../../stdlib/README.md");
    let plan = include_str!("../../stdlib/PLAN.md");
    let module_plan = include_str!("../../docs/MODULE_RESOLUTION_GPU_PLAN.md");
    let buffers = include_str!("../../src/lexer/buffers.rs");
    let driver = include_str!("../../src/lexer/driver.rs");
    let passes = include_str!("../../src/lexer/passes/mod.rs");
    let pass = include_str!("../../src/lexer/passes/tokens_file_ids.rs");
    let shader = include_str!("../../shaders/lexer/tokens_file_ids.slang");
    let dfa_01_shader = include_str!("../../shaders/lexer/dfa_01_scan_inblock.slang");
    let dfa_03_shader = include_str!("../../shaders/lexer/dfa_03_apply_block_prefix.slang");
    let tokens_build_shader = include_str!("../../shaders/lexer/tokens_build.slang");
    let dfa_01_pass = include_str!("../../src/lexer/passes/dfa_01_scan_inblock.rs");
    let dfa_03_pass = include_str!("../../src/lexer/passes/dfa_03_apply_block_prefix.rs");
    let tokens_build_pass = include_str!("../../src/lexer/passes/tokens_build.rs");
    let compiler = include_str!("../../src/compiler.rs");
    let parser_driver = include_str!("../../src/parser/driver.rs");
    let parser_buffers = include_str!("../../src/parser/buffers.rs");
    let parser_direct_hir_shader = include_str!("../../shaders/parser/direct_hir.slang");
    let parser_hir_nodes_shader = include_str!("../../shaders/parser/hir_nodes.slang");
    let parser_hir_nodes_pass = include_str!("../../src/parser/passes/hir_nodes.rs");
    let parser_syntax = include_str!("../../src/parser/syntax.rs");
    let parser_syntax_shader = include_str!("../../shaders/parser/syntax_tokens.slang");
    let type_checker = type_checker_gpu_sources();
    let visible_scatter_shader =
        include_str!("../../shaders/type_checker/type_check_visible_02_scatter.slang");
    let calls_resolve_shader =
        include_str!("../../shaders/type_checker/type_check_calls_03_resolve.slang");
    let parser_tests = include_str!("../../tests/parser_tree.rs");
    let typecheck_tests = include_str!("../../tests/type_checker_modules.rs");
    let lexer_tests = include_str!("../../tests/lexer_retag.rs");

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
        passes.contains("cache.remove(&p.dfa_03.data().shader_id)")
            && passes.contains("cache.remove(&p.pair_03.data().shader_id)")
            && lexer_tests.contains("gpu_lexer_reuses_resident_buffers_after_stdlib_source_shrink"),
        "resident lexer reuse must rebuild dynamic ping/pong bind groups when source-size scan parity changes"
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
            && compiler.contains("compile_source_pack_to_wasm_with_gpu_codegen")
            && compiler.contains("compile_source_pack_to_wasm")
            && compiler.contains("with_recorded_resident_source_pack_tokens")
            && !compiler.contains("expand_source_imports"),
        "compiler should expose explicit source-pack type checking/codegen without CPU import expansion"
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
        type_checker.contains("\"token_file_id\".into()")
            && type_checker.contains("buffer_fingerprint(&[")
            && compiler.contains("&bufs.token_file_id"),
        "GPU type checker should bind lexer-produced token_file_id metadata into resident type-check passes"
    );
    assert!(
        visible_scatter_shader.contains("StructuredBuffer<uint> token_file_id")
            && visible_scatter_shader.contains("bool same_file")
            && visible_scatter_shader.contains("if (!same_file(j, ident_i))")
            && visible_scatter_shader.contains("if (!is_const_decl_at(j))"),
        "legacy lexical const visibility should be file-local so module imports are resolved by GPU resolver arrays"
    );
    assert!(
        parser_tests.contains("gpu_syntax_rejects_invalid_token_file_ids_from_gpu_metadata")
            && parser_tests
                .contains("gpu_syntax_treats_source_pack_module_import_metadata_file_locally")
            && typecheck_tests.contains(
                "type_checker_source_pack_accepts_module_metadata_and_resolved_path_imports"
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

    assert!(
        !calls_resolve_shader.contains("StructuredBuffer<uint> dense_counts")
            && !calls_resolve_shader.contains("StructuredBuffer<uint> module_records")
            && !calls_resolve_shader.contains("StructuredBuffer<uint> import_records")
            && !calls_resolve_shader.contains("token_belongs_to_module_metadata_ast_span"),
        "call resolution should not suppress module/import headers through the deleted metadata slice"
    );

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
