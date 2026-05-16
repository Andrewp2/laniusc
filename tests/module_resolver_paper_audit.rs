use std::{
    fs,
    path::{Path, PathBuf},
};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn read_repo_file(rel: &str) -> String {
    let path = repo_root().join(rel);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

fn normalize(source: &str) -> String {
    source
        .to_ascii_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn assert_contains_all(name: &str, source: &str, needles: &[&str]) {
    for needle in needles {
        assert!(
            source.contains(needle),
            "{name} should contain required text: {needle}"
        );
    }
}

#[test]
fn paper_name_extraction_shape_is_reflected_in_module_plan() {
    let paper = normalize(&read_repo_file(
        "docs/ParallelLexingParsingSemanticAnalysis.md",
    ));
    assert_contains_all(
        "ParallelLexingParsingSemanticAnalysis.md",
        &paper,
        &[
            "assigning an integer value to unique names is done by first sorting and then deduplicat",
            "gpu-friendly parallel radix sort",
            "string equality algorithm",
            "previous string in the sorted array",
            "the final integer is obtained by a parallel prefix sum",
        ],
    );

    let plan = read_repo_file("docs/MODULE_RESOLUTION_GPU_PLAN.md");
    assert_contains_all(
        "MODULE_RESOLUTION_GPU_PLAN.md",
        &plan,
        &[
            "parser/HIR arrays",
            "GPU radix sort",
            "byte equality deduplication",
            "prefix-sum ids",
            "sorted lookup tables",
            "duplicate validation",
            "resolution arrays",
            "hash equality is only a",
            "candidate filter",
        ],
    );
}

#[test]
fn first_resolver_slice_names_concrete_passes_and_buffers() {
    let plan = read_repo_file("docs/MODULE_RESOLUTION_GPU_PLAN.md");
    assert_contains_all(
        "MODULE_RESOLUTION_GPU_PLAN.md",
        &plan,
        &[
            "type_check_names_00_mark_lexemes.slang",
            "type_check_names_scan_00_local.slang",
            "type_check_names_scan_01_blocks.slang",
            "type_check_names_scan_02_apply.slang",
            "type_check_names_01_scatter_lexemes.slang",
            "type_check_names_radix_00_histogram.slang",
            "type_check_names_radix_01_scatter.slang",
            "type_check_names_radix_02_adjacent_dedup.slang",
            "type_check_names_radix_03_assign_ids.slang",
            "type_check_modules_00_mark_records.slang",
            "type_check_modules_01_scatter_paths.slang",
            "type_check_modules_02_scatter_module_records.slang",
            "type_check_modules_02b_scatter_import_records.slang",
            "type_check_modules_02c_scatter_decl_core_records.slang",
            "type_check_modules_02d_scatter_decl_span_records.slang",
            "type_check_modules_02e_build_module_keys.slang",
            "type_check_modules_03_sort_module_keys_histogram.slang",
            "type_check_modules_03b_sort_module_keys_scatter.slang",
            "type_check_modules_04_validate_modules.slang",
            "type_check_modules_05_resolve_imports.slang",
            "type_check_modules_05b_clear_file_module_map.slang",
            "type_check_modules_05c_build_file_module_map.slang",
            "type_check_modules_05d_attach_record_modules.slang",
            "type_check_modules_06a_seed_decl_key_order.slang",
            "type_check_modules_06_sort_decl_keys.slang",
            "type_check_modules_06b_sort_decl_keys_scatter.slang",
            "type_check_modules_07_validate_decls.slang",
            "type_check_modules_08_mark_decl_namespace_keys.slang",
            "type_check_modules_08b_scatter_decl_namespace_keys.slang",
            "type_check_modules_09_count_import_visibility.slang",
            "type_check_modules_09b_scatter_import_visibility.slang",
            "type_check_modules_09c_sort_import_visible_keys.slang",
            "type_check_modules_09d_sort_import_visible_keys_scatter.slang",
            "type_check_modules_09e_build_import_visible_key_tables.slang",
            "type_check_modules_09f_validate_import_visible_keys.slang",
            "type_check_modules_10_resolve_local_paths.slang",
            "type_check_modules_10b_resolve_imported_paths.slang",
            "type_check_modules_10c_resolve_qualified_paths.slang",
            "type_check_modules_10d_clear_type_path_types.slang",
            "type_check_modules_10e_project_type_paths.slang",
            "type_check_modules_10f_mark_value_call_paths.slang",
            "type_check_modules_10g_project_value_paths.slang",
            "type_check_modules_10h_consume_value_calls.slang",
            "type_check_modules_10i_consume_value_consts.slang",
            "type_check_modules_10j_consume_value_enum_units.slang",
            "type_check_modules_10k_project_type_instances.slang",
            "type_check_modules_10l_consume_value_enum_calls.slang",
            "name_id_by_token",
            "path_segment_name_id",
            "module_key_segment_name_id",
            "module_key_to_module_id",
            "import_target_module_id",
            "module_id_by_file_id",
            "decl_module_id",
            "decl_key_to_decl_id",
            "decl_status",
            "decl_type_key_flag",
            "decl_value_key_flag",
            "decl_type_key_prefix",
            "decl_value_key_prefix",
            "decl_type_key_count_out",
            "decl_value_key_count_out",
            "decl_type_key_to_decl_id",
            "decl_value_key_to_decl_id",
            "import_visible_type_count",
            "import_visible_value_count",
            "import_visible_type_prefix",
            "import_visible_value_prefix",
            "import_visible_type_count_out",
            "import_visible_value_count_out",
            "import_visible_type_module_id",
            "import_visible_type_name_id",
            "import_visible_type_decl_id",
            "import_visible_type_key_order",
            "import_visible_type_key_to_decl_id",
            "import_visible_type_status",
            "import_visible_value_module_id",
            "import_visible_value_name_id",
            "import_visible_value_decl_id",
            "import_visible_value_key_order",
            "import_visible_value_key_to_decl_id",
            "import_visible_value_status",
            "resolved_type_decl",
            "resolved_value_decl",
            "resolved_type_status",
            "resolved_value_status",
            "module_value_path_expr_head",
            "module_value_path_status",
            "decl_parent_type_decl",
            "call_fn_index",
            "call_return_type",
        ],
    );
}

#[test]
fn declaration_key_validation_reduces_record_failures_to_typecheck_status() {
    let shader = read_repo_file("shaders/type_checker/type_check_modules_07_validate_decls.slang");
    let bindings = read_repo_file("src/type_checker/module_path_body.inc");

    assert_contains_all(
        "type_check_modules_07_validate_decls.slang",
        &shader,
        &[
            "StructuredBuffer<uint> sorted_decl_key_order",
            "StructuredBuffer<uint> decl_module_id",
            "StructuredBuffer<uint> decl_namespace",
            "StructuredBuffer<uint> decl_name_id",
            "StructuredBuffer<uint> decl_token_start",
            "RWStructuredBuffer<uint> decl_status",
            "RWStructuredBuffer<uint> decl_duplicate_of",
            "RWStructuredBuffer<uint> status",
            "record_error(error_token_for_decl(decl_i), ERR_BAD_HIR, status)",
            "record_error(error_token_for_decl(decl_i), ERR_BAD_HIR, DECL_STATUS_DUPLICATE)",
        ],
    );
    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_text",
        "same_text",
    ] {
        assert!(
            !shader.contains(forbidden),
            "declaration validation should consume declaration records, not token/source text: {forbidden}"
        );
    }
    assert_contains_all(
        "module_path_body.inc validate_decl_resources",
        &bindings,
        &[
            "\"decl_token_start\".into()",
            "\"status\".into()",
            "type_check_modules_07_validate_decls",
        ],
    );
}

#[test]
fn method_key_validation_reduces_record_failures_to_typecheck_status() {
    let shader = read_repo_file("shaders/type_checker/type_check_methods_05_validate_keys.slang");
    let bindings = read_repo_file("src/type_checker/bind_support.rs");

    assert_contains_all(
        "type_check_methods_05_validate_keys.slang",
        &shader,
        &[
            "StructuredBuffer<uint> sorted_method_key_order",
            "StructuredBuffer<uint> method_decl_receiver_ref_tag",
            "StructuredBuffer<uint> method_decl_receiver_ref_payload",
            "StructuredBuffer<uint> method_decl_module_id",
            "StructuredBuffer<uint> method_decl_name_token",
            "StructuredBuffer<uint> method_decl_name_id",
            "RWStructuredBuffer<uint> method_key_status",
            "RWStructuredBuffer<uint> method_key_duplicate_of",
            "RWStructuredBuffer<uint> status",
            "record_error(error_token_for_method(fn_i), ERR_BAD_HIR, status)",
            "record_error(error_token_for_method(fn_i), ERR_BAD_HIR, METHOD_KEY_STATUS_DUPLICATE)",
        ],
    );
    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_text",
        "same_text",
    ] {
        assert!(
            !shader.contains(forbidden),
            "method validation should consume method records, not token/source text: {forbidden}"
        );
    }
    assert_contains_all(
        "bind_support.rs validate_resources",
        &bindings,
        &[
            "method_decl_name_token: &wgpu::Buffer",
            "\"method_decl_name_token\".into()",
            "\"status\".into()",
        ],
    );
}

#[test]
fn module_plan_forbids_deleted_resolver_slice_and_shortcuts() {
    let plan = read_repo_file("docs/MODULE_RESOLUTION_GPU_PLAN.md");
    assert_contains_all(
        "MODULE_RESOLUTION_GPU_PLAN.md",
        &plan,
        &[
            "Forbidden legacy resolver shapes",
            "hash-prefix-scan slice",
            "same-source qualified shortcut",
            "source rewriting",
            "CPU import expansion",
            "CPU path lookup",
            "CPU declaration visibility",
            "hash-only lookup",
            "No CPU source concatenation, import expansion",
        ],
    );

    let deleted_shader_names = [
        "type_check_names_00_hash.slang",
        "type_check_modules_00_collect.slang",
        "type_check_modules_00_collect_decls.slang",
        "type_check_modules_00_resolve_imports.slang",
        "type_check_modules_00_clear.slang",
        "type_check_modules_01_dense_scan.slang",
        "type_check_modules_01_same_source_types.slang",
        "type_check_modules_02_dense_scatter.slang",
        "type_check_modules_02b_dense_scatter_imports.slang",
        "type_check_modules_02c_dense_scatter_decls.slang",
        "type_check_modules_02_patch_visible_types.slang",
        "type_check_modules_03_attach_ids.slang",
    ];

    for shader_name in deleted_shader_names {
        assert!(
            plan.contains(shader_name),
            "plan should explicitly forbid deleted resolver shader: {shader_name}"
        );
        let rel = Path::new("shaders").join("type_checker").join(shader_name);
        assert!(
            !repo_root().join(&rel).exists(),
            "deleted resolver shader should not exist: {}",
            rel.display()
        );
    }
}

#[test]
fn qualified_path_handling_uses_hir_path_nodes_not_token_segment_scans() {
    let calls = read_repo_file("shaders/type_checker/type_check_calls_03_resolve.slang");
    let tokens_min = read_repo_file("shaders/type_checker/type_check_tokens_min.slang");
    let segments =
        read_repo_file("shaders/type_checker/type_check_modules_01b_scatter_path_segments.slang");
    let projection =
        read_repo_file("shaders/type_checker/type_check_modules_10e_project_type_paths.slang");
    let value_projection =
        read_repo_file("shaders/type_checker/type_check_modules_10g_project_value_paths.slang");
    let value_call_consumer =
        read_repo_file("shaders/type_checker/type_check_modules_10h_consume_value_calls.slang");
    let value_const_consumer =
        read_repo_file("shaders/type_checker/type_check_modules_10i_consume_value_consts.slang");
    let value_enum_consumer = read_repo_file(
        "shaders/type_checker/type_check_modules_10j_consume_value_enum_units.slang",
    );
    let type_instance_projection =
        read_repo_file("shaders/type_checker/type_check_modules_10k_project_type_instances.slang");
    let value_enum_call_consumer = read_repo_file(
        "shaders/type_checker/type_check_modules_10l_consume_value_enum_calls.slang",
    );

    for forbidden in [
        "qualified_path_start_for_segment",
        "qualified_path_end",
        "segment_in_qualified_path",
        "is_qualified_type_context",
        "is_qualified_type_expr_head",
    ] {
        assert!(
            !calls.contains(forbidden) && !tokens_min.contains(forbidden),
            "qualified path handling should not be token-segment special casing: {forbidden}"
        );
    }

    assert_contains_all(
        "type_check_modules_01b_scatter_path_segments.slang",
        &segments,
        &[
            "PATH_RECORD_KIND_HIR_PATH_EXPR",
            "path_segment_count[path_slot] = count",
            "path_segment_name_id[dst] = name_id",
        ],
    );
    assert!(
        !segments.contains("record_error")
            && !segments.contains("count > 1u")
            && !segments.contains("ERR_BAD_HIR"),
        "path segment scattering must not reject qualified HIR paths before resolver consumers run"
    );
    assert_contains_all(
        "type_check_modules_10e_project_type_paths.slang",
        &projection,
        &[
            "resolved_type_decl",
            "resolved_type_status",
            "module_type_path_status",
            "decl_name_token",
            "module_type_path_type",
        ],
    );
    assert_contains_all(
        "type_check_modules_10g_project_value_paths.slang",
        &value_projection,
        &[
            "resolved_value_status",
            "module_value_path_expr_head",
            "module_value_path_call_head",
            "module_value_path_status",
        ],
    );
    assert!(
        !value_projection.contains("module_value_path_decl_token")
            && !value_projection.contains("call_fn_index")
            && !value_projection.contains("call_return_type"),
        "value status projection must stay fail-closed until a real HIR value/call consumer reads resolved_value_decl"
    );
    assert_contains_all(
        "type_check_modules_10h_consume_value_calls.slang",
        &value_call_consumer,
        &[
            "resolved_value_decl",
            "resolved_value_status",
            "module_value_path_call_open",
            "call_arg_record",
            "call_fn_index",
            "call_return_type",
            "decl_token_start",
            "valid_function_decl",
        ],
    );
    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !value_call_consumer.contains(forbidden),
            "HIR value call consumer should not resolve through token text shortcuts: {forbidden}"
        );
    }
    assert_contains_all(
        "type_check_modules_10i_consume_value_consts.slang",
        &value_const_consumer,
        &[
            "resolved_value_decl",
            "resolved_value_status",
            "module_value_path_call_head",
            "visible_decl",
            "visible_type",
        ],
    );
    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !value_const_consumer.contains(forbidden),
            "HIR value const consumer should not resolve through token text shortcuts: {forbidden}"
        );
    }
    assert_contains_all(
        "type_check_modules_10j_consume_value_enum_units.slang",
        &value_enum_consumer,
        &[
            "resolved_value_decl",
            "resolved_value_status",
            "decl_parent_type_decl",
            "decl_name_token",
            "HIR_ITEM_KIND_ENUM_VARIANT",
            "visible_decl",
            "visible_type",
        ],
    );
    assert_contains_all(
        "type_check_modules_10k_project_type_instances.slang",
        &type_instance_projection,
        &[
            "resolved_type_decl",
            "path_segment_token",
            "decl_name_token",
            "TYPE_REF_INSTANCE",
            "type_instance_decl_token",
            "type_decl_generic_param_count",
        ],
    );
    assert_contains_all(
        "type_check_modules_10l_consume_value_enum_calls.slang",
        &value_enum_call_consumer,
        &[
            "resolved_value_decl",
            "resolved_value_status",
            "decl_parent_type_decl",
            "decl_name_token",
            "type_decl_generic_param_count",
            "GENERIC_ENUM_CTOR_OK",
            "call_return_type",
        ],
    );
    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_words",
        "token_kind",
        "generic_param_list",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !value_enum_consumer.contains(forbidden)
                && !type_instance_projection.contains(forbidden)
                && !value_enum_call_consumer.contains(forbidden),
            "HIR value enum consumers should not resolve through token text shortcuts: {forbidden}"
        );
    }
}
