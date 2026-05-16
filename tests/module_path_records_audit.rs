use std::{
    env,
    fs,
    path::{Path, PathBuf},
    process::Command,
};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn shader_path(file_name: &str) -> PathBuf {
    repo_root()
        .join("shaders")
        .join("type_checker")
        .join(file_name)
}

fn read_shader(file_name: &str) -> String {
    let path = shader_path(file_name);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

fn read_repo_file(rel: &str) -> String {
    let path = repo_root().join(rel);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

fn pre_import_lookup_module_shader_files() -> [&'static str; 11] {
    [
        "type_check_modules_00_mark_records.slang",
        "type_check_modules_01_scatter_paths.slang",
        "type_check_modules_01b_scatter_path_segments.slang",
        "type_check_modules_02_scatter_module_records.slang",
        "type_check_modules_02b_scatter_import_records.slang",
        "type_check_modules_02c_scatter_decl_core_records.slang",
        "type_check_modules_02d_scatter_decl_span_records.slang",
        "type_check_modules_02e_build_module_keys.slang",
        "type_check_modules_03_sort_module_keys_histogram.slang",
        "type_check_modules_03b_sort_module_keys_scatter.slang",
        "type_check_modules_04_validate_modules.slang",
    ]
}

fn module_shader_files() -> [&'static str; 39] {
    [
        "type_check_modules_00_mark_records.slang",
        "type_check_modules_01_scatter_paths.slang",
        "type_check_modules_01b_scatter_path_segments.slang",
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
    ]
}

fn all_pre_import_lookup_module_shader_sources() -> String {
    pre_import_lookup_module_shader_files()
        .into_iter()
        .map(read_shader)
        .collect::<Vec<_>>()
        .join("\n")
}

fn assert_contains_all(name: &str, source: &str, needles: &[&str]) {
    for needle in needles {
        assert!(
            source.contains(needle),
            "{name} should contain required text: {needle}"
        );
    }
}

fn slangc_command() -> Option<PathBuf> {
    if let Some(path) = env::var_os("SLANGC") {
        return Some(PathBuf::from(path));
    }
    let probe = Command::new("slangc").arg("-version").output();
    probe.ok().filter(|out| out.status.success())?;
    Some(PathBuf::from("slangc"))
}

#[test]
fn module_path_record_files_are_standalone_compute_shaders() {
    for file_name in module_shader_files() {
        let shader = read_shader(file_name);
        assert!(
            shader.contains("[shader(\"compute\")]"),
            "{file_name} should declare a compute entrypoint"
        );
        assert!(
            shader.contains("[numthreads(256, 1, 1)]"),
            "{file_name} should use the repository workgroup size"
        );
        assert!(
            !shader
                .lines()
                .any(|line| line.trim_start().starts_with("import ")),
            "{file_name} should compile as a standalone Slang shader"
        );
    }
}

#[test]
fn module_mark_pass_marks_only_parser_owned_candidates() {
    let shader = read_shader("type_check_modules_00_mark_records.slang");
    assert_contains_all(
        "type_check_modules_00_mark_records.slang",
        &shader,
        &[
            "Pre-resolution GPU module/path metadata foundation",
            "candidate rows only",
            "hir_item_kind",
            "hir_item_name_token",
            "hir_item_namespace",
            "hir_item_path_start",
            "hir_item_path_end",
            "hir_item_import_target_kind",
            "HIR_PATH_EXPR",
            "module_record_flag",
            "import_record_flag",
            "decl_record_flag",
            "path_record_flag",
            "PATH_RECORD_KIND_MODULE_DECL",
            "PATH_RECORD_KIND_IMPORT_PATH",
            "PATH_RECORD_KIND_HIR_PATH_EXPR",
            "PATH_RECORD_KIND_HIR_TYPE_EXPR",
        ],
    );
}

#[test]
fn path_scatter_pass_uses_scanned_flags_and_name_ids() {
    let shader = read_shader("type_check_modules_01_scatter_paths.slang");
    assert_contains_all(
        "type_check_modules_01_scatter_paths.slang",
        &shader,
        &[
            "exclusive prefix scan over path_record_flag",
            "parser-owned HIR spans",
            "path_record_prefix",
            "path_start",
            "path_len",
            "path_segment_base",
            "path_owner_hir",
            "path_owner_token",
            "path_kind",
            "path_count_out",
        ],
    );

    let segments = read_shader("type_check_modules_01b_scatter_path_segments.slang");
    assert_contains_all(
        "type_check_modules_01b_scatter_path_segments.slang",
        &segments,
        &[
            "path_count_out",
            "path_owner_token",
            "path_kind",
            "name_id_by_token",
            "token_words",
            "qualified_path_head_end",
            "path_segment_count",
            "path_segment_name_id",
            "path_segment_token",
            "PATH_RECORD_KIND_HIR_PATH_EXPR",
            "write_segment",
            "count_segments",
        ],
    );
    assert!(
        segments.contains("uint name_id = name_id_by_token[token_i]")
            && segments.contains("if (name_id == INVALID)")
            && segments.contains("path_segment_name_id[dst] = name_id"),
        "path segment scatter should derive segment records from interned token name ids"
    );
}

#[test]
fn module_path_foundation_does_not_claim_resolution_semantics() {
    let shaders = all_pre_import_lookup_module_shader_sources();
    assert_contains_all(
        "module path record shaders",
        &shaders,
        &[
            "does not resolve imports",
            "does not perform module lookup",
            "does not perform",
            "same-source shortcuts",
            "hash-only lookup",
            "CPU path",
        ],
    );

    for forbidden in [
        "import_target_module_id",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "import_visible_type_key_to_decl_id",
        "import_visible_value_key_to_decl_id",
        "visible_decl",
        "call_fn_index",
        "call_return_type",
        "module_records",
        "import_records",
        "module_id_for_file",
        "import_resolved_module_token",
        "qualified_leaf_token",
        "source_bytes",
        "ByteAddressBuffer",
    ] {
        assert!(
            !shaders.contains(forbidden),
            "pre-resolution metadata shaders should not contain resolver output or source-scan shape: {forbidden}"
        );
    }
}

#[test]
fn import_lookup_pass_uses_sorted_module_keys_without_visibility_shortcuts() {
    let shader = read_shader("type_check_modules_05_resolve_imports.slang");
    assert_contains_all(
        "type_check_modules_05_resolve_imports.slang",
        &shader,
        &[
            "GPU import-to-module lookup",
            "sorted_module_key_order",
            "compare_path_to_module",
            "find_module_for_path",
            "import_target_module_id",
            "import_status",
            "SORT_PATH_SEGMENTS",
            "path_segment_name_id",
            "module_key_segment_name_id",
        ],
    );
    for forbidden in [
        "visible_decl",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "decl_type_key_to_decl_id",
        "decl_value_key_to_decl_id",
        "import_visible_type_key_to_decl_id",
        "import_visible_value_key_to_decl_id",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
    ] {
        assert!(
            !shader.contains(forbidden),
            "import lookup pass should only resolve import paths to module ids: {forbidden}"
        );
    }
}

#[test]
fn declaration_module_attachment_uses_gpu_written_file_module_table() {
    let clear = read_shader("type_check_modules_05b_clear_file_module_map.slang");
    let build = read_shader("type_check_modules_05c_build_file_module_map.slang");
    let attach = read_shader("type_check_modules_05d_attach_record_modules.slang");
    assert_contains_all(
        "declaration module attachment shaders",
        &format!("{clear}\n{build}\n{attach}"),
        &[
            "GPU declaration-module lookup map clear",
            "GPU file-to-module-id table construction",
            "GPU record-to-module-id attachment",
            "module_id_by_file_id",
            "module_file_id",
            "decl_module_file_id",
            "decl_module_id",
            "import_module_file_id",
            "import_module_id",
            "path_owner_module_id",
        ],
    );
    assert!(
        build.contains("module_id_by_file_id[file_id] = module_i")
            && attach.contains("module_id_by_file_id[file_id]"),
        "declaration module attachment should use a GPU-written file-id table"
    );
    for forbidden in [
        "visible_decl",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "decl_type_key_to_decl_id",
        "decl_value_key_to_decl_id",
        "import_visible_type_key_to_decl_id",
        "import_visible_value_key_to_decl_id",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
    ] {
        assert!(
            !clear.contains(forbidden) && !build.contains(forbidden) && !attach.contains(forbidden),
            "declaration module attachment should only build GPU tables: {forbidden}"
        );
    }
}

#[test]
fn declaration_key_sort_and_validation_use_radix_and_adjacent_comparison() {
    let seed = read_shader("type_check_modules_06a_seed_decl_key_order.slang");
    let histogram = read_shader("type_check_modules_06_sort_decl_keys.slang");
    let scatter = read_shader("type_check_modules_06b_sort_decl_keys_scatter.slang");
    let validate = read_shader("type_check_modules_07_validate_decls.slang");
    assert_contains_all(
        "declaration key sort shaders",
        &format!("{seed}\n{histogram}\n{scatter}\n{validate}"),
        &[
            "GPU declaration-key order seed",
            "GPU declaration-key radix histogram",
            "GPU declaration-key radix stable scatter",
            "GPU sorted declaration-key validation",
            "decl_module_id",
            "decl_namespace",
            "decl_name_id",
            "decl_key_to_decl_id",
            "decl_key_order_out",
            "decl_status",
            "decl_duplicate_of",
        ],
    );
    assert!(
        histogram.contains("key_step walks the fixed declaration key")
            && scatter.contains("local_same_key_rank")
            && validate.contains("decl_keys_equal"),
        "declaration key sort should use stable radix plus adjacent equality validation"
    );
    for forbidden in [
        "visible_decl",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "import_visible_type_key_to_decl_id",
        "import_visible_value_key_to_decl_id",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
    ] {
        assert!(
            !seed.contains(forbidden)
                && !histogram.contains(forbidden)
                && !scatter.contains(forbidden)
                && !validate.contains(forbidden),
            "declaration key sort should not resolve visibility or shortcut: {forbidden}"
        );
    }
}

#[test]
fn declaration_namespace_lookup_tables_use_scans_over_sorted_keys() {
    let mark = read_shader("type_check_modules_08_mark_decl_namespace_keys.slang");
    let scatter = read_shader("type_check_modules_08b_scatter_decl_namespace_keys.slang");
    assert_contains_all(
        "declaration namespace lookup shaders",
        &format!("{mark}\n{scatter}"),
        &[
            "GPU declaration namespace table marking",
            "GPU declaration namespace table scatter",
            "sorted declaration-key table",
            "sorted_decl_key_order",
            "decl_status",
            "decl_type_key_flag",
            "decl_value_key_flag",
            "decl_type_key_prefix",
            "decl_value_key_prefix",
            "decl_type_key_to_decl_id",
            "decl_value_key_to_decl_id",
        ],
    );
    assert!(
        mark.contains("decl_status[decl_i] != DECL_STATUS_OK")
            && scatter.contains("decl_type_key_to_decl_id[dst] = decl_i")
            && scatter.contains("decl_value_key_to_decl_id[dst] = decl_i"),
        "declaration namespace tables should filter validated sorted declarations and scatter declaration ids"
    );
    for forbidden in [
        "visible_decl",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "import_visible_type_key_to_decl_id",
        "import_visible_value_key_to_decl_id",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
    ] {
        assert!(
            !mark.contains(forbidden) && !scatter.contains(forbidden),
            "declaration namespace tables should not resolve visibility or shortcut: {forbidden}"
        );
    }
}

#[test]
fn import_visibility_tables_use_scans_radix_sort_and_adjacent_validation() {
    let count = read_shader("type_check_modules_09_count_import_visibility.slang");
    let scatter = read_shader("type_check_modules_09b_scatter_import_visibility.slang");
    let histogram = read_shader("type_check_modules_09c_sort_import_visible_keys.slang");
    let sort_scatter = read_shader("type_check_modules_09d_sort_import_visible_keys_scatter.slang");
    let build = read_shader("type_check_modules_09e_build_import_visible_key_tables.slang");
    let validate = read_shader("type_check_modules_09f_validate_import_visible_keys.slang");
    let combined = format!("{count}\n{scatter}\n{histogram}\n{sort_scatter}\n{build}\n{validate}");
    assert_contains_all(
        "import visibility shaders",
        &combined,
        &[
            "GPU imported declaration visibility counting",
            "GPU imported declaration visibility scatter",
            "GPU imported-visibility key radix histogram",
            "GPU imported-visibility key radix stable scatter",
            "GPU imported-visibility sorted key table build",
            "GPU imported-visibility sorted key validation",
            "import_target_module_id",
            "import_module_id",
            "decl_type_key_to_decl_id",
            "decl_value_key_to_decl_id",
            "decl_visibility",
            "import_visible_type_count",
            "import_visible_value_count",
            "import_visible_prefix",
            "import_visible_type_key_to_decl_id",
            "import_visible_value_key_to_decl_id",
            "IMPORT_VISIBLE_STATUS_AMBIGUOUS",
        ],
    );
    assert!(
        count.contains("lower_bound_module")
            && count.contains("decl_visibility[decl_i] == HIR_ITEM_VIS_PUBLIC")
            && scatter.contains("record_error(importing_module, ERR_NAME_LIMIT, dst)")
            && histogram.contains("key_step walks the fixed imported-visibility key")
            && sort_scatter.contains("local_same_key_rank")
            && build
                .contains("import_visible_key_to_decl_id[i] = import_visible_decl_id[visible_i]")
            && validate.contains("same_type_key(i - 1u, i)"),
        "import visibility should range-query sorted declaration tables, fail closed on overflow, stable-sort keys, and validate ambiguity"
    );
    for forbidden in [
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_call_decl",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
    ] {
        assert!(
            !combined.contains(forbidden),
            "import visibility should not resolve paths or shortcut: {forbidden}"
        );
    }
}

#[test]
fn path_resolution_checkpoint_uses_sorted_tables_without_downstream_patching() {
    let local = read_shader("type_check_modules_10_resolve_local_paths.slang");
    let imported = read_shader("type_check_modules_10b_resolve_imported_paths.slang");
    let qualified = read_shader("type_check_modules_10c_resolve_qualified_paths.slang");
    let combined = format!("{local}\n{imported}\n{qualified}");

    assert_contains_all(
        "path resolution checkpoint shaders",
        &combined,
        &[
            "GPU local unqualified path resolution",
            "GPU imported unqualified path resolution",
            "GPU qualified path resolution",
            "PATH_RECORD_KIND_HIR_PATH_EXPR",
            "path_owner_module_id",
            "path_segment_name_id",
            "decl_key_to_decl_id",
            "import_visible_key_to_decl_id",
            "import_visible_status",
            "sorted_module_key_order",
            "module_key_segment_name_id",
            "resolved_decl",
            "resolved_status",
            "PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT",
        ],
    );
    assert!(
        local.contains("find_decl")
            && imported.contains("find_visible_row")
            && qualified.contains("find_module_for_path_prefix")
            && qualified.contains("compare_path_prefix_to_module"),
        "path resolution should use binary searches over sorted module/declaration/import tables"
    );

    for forbidden in [
        "resolved_call_decl",
        "visible_decl",
        "visible_type",
        "call_fn_index",
        "call_return_type",
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "hash-only",
        "same_source",
        "same-source qualified",
        "CPU path lookup",
    ] {
        assert!(
            !combined.contains(forbidden),
            "path resolution arrays should not patch downstream consumers or shortcut: {forbidden}"
        );
    }
}

#[test]
fn type_path_projection_consumes_resolver_arrays_without_token_shortcuts() {
    let clear = read_shader("type_check_modules_10d_clear_type_path_types.slang");
    let project = read_shader("type_check_modules_10e_project_type_paths.slang");
    let mark_value = read_shader("type_check_modules_10f_mark_value_call_paths.slang");
    let project_value = read_shader("type_check_modules_10g_project_value_paths.slang");
    let consume_value_calls = read_shader("type_check_modules_10h_consume_value_calls.slang");
    let consume_value_consts = read_shader("type_check_modules_10i_consume_value_consts.slang");
    let consume_value_enum_units =
        read_shader("type_check_modules_10j_consume_value_enum_units.slang");
    let project_type_instances = read_shader("type_check_modules_10k_project_type_instances.slang");
    let consume_value_enum_calls =
        read_shader("type_check_modules_10l_consume_value_enum_calls.slang");
    let scope = read_shader("type_check_scope.slang");
    let tokens = read_shader("type_check_tokens_min.slang");
    let calls = read_shader("type_check_calls_02_functions.slang");

    assert_contains_all(
        "type path projection shaders",
        &(clear.clone() + "\n" + &project),
        &[
            "GPU type-path projection",
            "module_type_path_type",
            "module_type_path_status",
            "module_value_path_expr_head",
            "module_value_path_call_head",
            "module_value_path_status",
            "resolved_type_decl",
            "resolved_type_status",
            "path_segment_count",
            "decl_name_token",
            "decl_namespace",
            "TY_STRUCT_BASE + token_i",
            "TY_ENUM_BASE + token_i",
        ],
    );
    assert!(
        scope.contains("module_type_path_type[cur]")
            && scope.contains("module_value_path_status[i]")
            && tokens.contains("module_type_path_type[cur]")
            && tokens.contains("module_type_path_status[i]")
            && calls.contains("module_type_path_type[head]"),
        "type consumers should read the GPU resolver projection through semantic records"
    );
    assert_contains_all(
        "value path projection shaders",
        &(mark_value.clone() + "\n" + &project_value),
        &[
            "HIR_PATH_EXPR",
            "HIR_NAME_EXPR",
            "HIR_CALL_EXPR",
            "next_sibling",
            "resolved_value_status",
            "module_value_path_expr_head",
            "module_value_path_call_head",
            "module_value_path_status",
        ],
    );

    for forbidden in [
        "source_bytes",
        "ByteAddressBuffer",
        "token_hash",
        "same_source",
        "qualified_leaf_token",
        "visible_type",
        "visible_decl",
        "call_fn_index",
        "call_return_type",
    ] {
        assert!(
            !project.contains(forbidden),
            "type path projection should not scan source or patch downstream consumers: {forbidden}"
        );
        assert!(
            !project_value.contains(forbidden),
            "value path projection should not scan source or patch downstream consumers: {forbidden}"
        );
    }
    assert!(
        !project.contains("resolved_value_decl"),
        "type path projection should not consume value namespace declarations"
    );
    assert!(
        !project_value.contains("resolved_value_decl"),
        "status-only value projection should leave declaration consumption to real HIR value consumers"
    );
    assert_contains_all(
        "type_check_modules_10h_consume_value_calls.slang",
        &consume_value_calls,
        &[
            "GPU HIR-qualified value call consumer",
            "resolved_value_decl",
            "resolved_value_status",
            "module_value_path_call_open",
            "module_value_path_status",
            "call_arg_record",
            "call_fn_index",
            "call_return_type",
            "decl_token_start",
            "valid_function_decl",
            "call_fn_index[token_i] != token_i",
            "PATH_RESOLVE_STATUS_UNRESOLVED_DECL",
        ],
    );
    for forbidden in [
        "source_bytes",
        "ByteAddressBuffer",
        "token_hash",
        "token_words",
        "token_kind",
        "same_text",
        "generic_param_list",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !consume_value_calls.contains(forbidden),
            "value call consumer should use resolver arrays, not token text shortcuts: {forbidden}"
        );
    }
    assert_contains_all(
        "type_check_modules_10i_consume_value_consts.slang",
        &consume_value_consts,
        &[
            "GPU HIR-qualified constant value consumer",
            "resolved_value_decl",
            "resolved_value_status",
            "module_value_path_call_head",
            "module_value_path_status",
            "HIR_ITEM_KIND_ENUM_VARIANT",
            "visible_decl",
            "visible_type",
            "visible_type[const_token]",
            "visible_type[owner_token]",
            "decl_name_token",
            "decl_kind",
        ],
    );
    assert!(
        !consume_value_consts.contains("path_segment_count[path_i] <= 1u"),
        "value const consumer should keep imported one-segment constants on the resolver-array path"
    );
    for forbidden in [
        "source_bytes",
        "ByteAddressBuffer",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !consume_value_consts.contains(forbidden),
            "value const consumer should use resolver arrays and declaration type outputs: {forbidden}"
        );
    }
    assert_contains_all(
        "type_check_modules_10j_consume_value_enum_units.slang",
        &consume_value_enum_units,
        &[
            "GPU HIR enum unit-variant consumer",
            "resolved_value_decl",
            "resolved_value_status",
            "decl_parent_type_decl",
            "HIR_ITEM_KIND_ENUM_VARIANT",
            "TY_ENUM_BASE + enum_token",
            "module_value_path_call_head",
            "module_value_path_status",
            "visible_decl",
            "visible_type",
        ],
    );
    for forbidden in [
        "source_bytes",
        "ByteAddressBuffer",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !consume_value_enum_units.contains(forbidden),
            "value unit enum consumer should use resolver arrays and parent enum metadata: {forbidden}"
        );
    }
    assert!(
        !consume_value_enum_units.contains("path_segment_count[path_i] <= 1u"),
        "value unit enum consumer should keep local one-segment variants on the resolver-array path"
    );
    assert_contains_all(
        "type_check_modules_10k_project_type_instances.slang",
        &project_type_instances,
        &[
            "GPU type-instance projection",
            "resolved_type_decl",
            "path_segment_token",
            "decl_name_token",
            "TYPE_REF_INSTANCE",
            "type_instance_decl_token",
            "type_decl_generic_param_count",
            "type_instance_state",
        ],
    );
    assert!(
        !project_type_instances.contains("path_segment_count[path_i] <= 1u"),
        "type instance projection should keep local one-segment instances on the resolver-array path"
    );
    assert_contains_all(
        "type_check_modules_10l_consume_value_enum_calls.slang",
        &consume_value_enum_calls,
        &[
            "GPU HIR enum constructor call consumer",
            "resolved_value_decl",
            "resolved_value_status",
            "decl_parent_type_decl",
            "decl_name_token",
            "type_decl_generic_param_count",
            "GENERIC_ENUM_CTOR_OK",
            "owner_token != leaf_token",
            "TY_ENUM_BASE + enum_token",
            "module_value_path_status",
            "call_return_type",
        ],
    );
    for forbidden in [
        "source_bytes",
        "ByteAddressBuffer",
        "token_words",
        "token_kind",
        "generic_param_list",
        "token_hash",
        "same_text",
        "qualified_leaf_token",
        "module_value_path_decl_token",
    ] {
        assert!(
            !project_type_instances.contains(forbidden),
            "type instance projection should use resolver path records: {forbidden}"
        );
        assert!(
            !consume_value_enum_calls.contains(forbidden),
            "value enum call consumer should use resolver arrays and validation state: {forbidden}"
        );
    }
    assert!(
        !consume_value_enum_calls.contains("path_segment_count[path_i] <= 1u"),
        "value enum call consumer should keep local one-segment constructors on the resolver-array path"
    );
}

#[test]
fn record_scatter_passes_use_scanned_flags_without_resolution_outputs() {
    let modules = read_shader("type_check_modules_02_scatter_module_records.slang");
    assert_contains_all(
        "type_check_modules_02_scatter_module_records.slang",
        &modules,
        &[
            "module_record_flag",
            "module_record_prefix",
            "hir_item_file_id",
            "path_record_prefix",
            "module_file_id",
            "module_path_id",
            "module_owner_hir",
        ],
    );

    let imports = read_shader("type_check_modules_02b_scatter_import_records.slang");
    assert_contains_all(
        "type_check_modules_02b_scatter_import_records.slang",
        &imports,
        &[
            "import_record_flag",
            "import_record_prefix",
            "hir_item_import_target_kind",
            "import_module_file_id",
            "import_path_id",
            "import_kind",
            "import_owner_hir",
            "HIR_ITEM_IMPORT_TARGET_PATH",
        ],
    );

    let decl_core = read_shader("type_check_modules_02c_scatter_decl_core_records.slang");
    assert_contains_all(
        "type_check_modules_02c_scatter_decl_core_records.slang",
        &decl_core,
        &[
            "decl_record_flag",
            "decl_record_prefix",
            "hir_item_name_token",
            "name_id_by_token",
            "decl_module_file_id",
            "decl_name_id",
            "decl_kind",
            "decl_namespace",
            "decl_visibility",
            "decl_hir_node",
            "decl_parent_type_decl",
            "parent_enum_decl_for_variant",
        ],
    );

    let decl_spans = read_shader("type_check_modules_02d_scatter_decl_span_records.slang");
    assert_contains_all(
        "type_check_modules_02d_scatter_decl_span_records.slang",
        &decl_spans,
        &[
            "decl_record_flag",
            "decl_record_prefix",
            "hir_item_name_token",
            "hir_token_pos",
            "hir_token_end",
            "decl_name_token",
            "decl_token_start",
            "decl_token_end",
        ],
    );
}

#[test]
fn module_key_build_pass_copies_path_segments_without_sorting_or_lookup() {
    let shader = read_shader("type_check_modules_02e_build_module_keys.slang");
    assert_contains_all(
        "type_check_modules_02e_build_module_keys.slang",
        &shader,
        &[
            "Pre-resolution GPU module key construction",
            "module_count_out",
            "module_path_id",
            "path_segment_count",
            "path_segment_base",
            "path_segment_name_id",
            "module_status",
            "module_key_segment_count",
            "module_key_segment_base",
            "module_key_segment_name_id",
            "module_key_to_module_id",
            "MAX_PATH_SEGMENTS",
        ],
    );
    for forbidden in [
        "import_target_module_id",
        "resolved_type_decl",
        "decl_type_key_to_decl_id",
        "module_key_hash",
        "same_source",
    ] {
        assert!(
            !shader.contains(forbidden),
            "module key build pass should not sort, resolve, or shortcut: {forbidden}"
        );
    }
}

#[test]
fn module_key_sort_and_validation_use_radix_and_adjacent_comparison() {
    let histogram = read_shader("type_check_modules_03_sort_module_keys_histogram.slang");
    assert_contains_all(
        "type_check_modules_03_sort_module_keys_histogram.slang",
        &histogram,
        &[
            "GPU module-key radix histogram",
            "key_step",
            "SORT_PATH_SEGMENTS",
            "module_key_radix_key",
            "name_id + 1",
            "InterlockedAdd(radix_block_histogram",
        ],
    );

    let scatter = read_shader("type_check_modules_03b_sort_module_keys_scatter.slang");
    assert_contains_all(
        "type_check_modules_03b_sort_module_keys_scatter.slang",
        &scatter,
        &[
            "GPU module-key radix stable scatter",
            "radix_bucket_base",
            "radix_block_bucket_prefix",
            "local_same_key_rank",
            "module_key_order_out[dst] = module_i",
        ],
    );

    let validate = read_shader("type_check_modules_04_validate_modules.slang");
    assert_contains_all(
        "type_check_modules_04_validate_modules.slang",
        &validate,
        &[
            "GPU sorted module-key validation",
            "sorted_module_key_order",
            "module_keys_equal",
            "module_key_segment_name_id",
            "MODULE_STATUS_DUPLICATE",
        ],
    );
    for forbidden in [
        "import_target_module_id",
        "resolved_type_decl",
        "decl_type_key_to_decl_id",
        "hash-only",
        "same_source",
        "ByteAddressBuffer",
    ] {
        assert!(
            !histogram.contains(forbidden)
                && !scatter.contains(forbidden)
                && !validate.contains(forbidden),
            "module sort/validation should not resolve, source-scan, or shortcut: {forbidden}"
        );
    }
}

#[test]
fn resident_type_checker_schedules_module_keys_and_import_lookup_foundation() {
    let gpu = read_repo_file("src/type_checker/mod.rs")
        + "\n"
        + &read_repo_file("src/type_checker/resident.rs")
        + "\n"
        + &read_repo_file("src/type_checker/record.rs");
    let compiler = read_repo_file("src/compiler.rs");
    let plan = read_repo_file("docs/MODULE_RESOLUTION_GPU_PLAN.md");

    assert_contains_all(
        "resident type checker",
        &gpu,
        &[
            "modules_mark_records",
            "modules_scatter_paths",
            "modules_scatter_path_segments",
            "modules_scatter_module_records",
            "modules_scatter_import_records",
            "modules_scatter_decl_core_records",
            "modules_scatter_decl_span_records",
            "modules_build_module_keys",
            "modules_sort_module_keys_histogram",
            "modules_sort_module_keys_scatter",
            "modules_validate_modules",
            "modules_resolve_imports",
            "modules_clear_file_module_map",
            "modules_build_file_module_map",
            "modules_attach_record_modules",
            "modules_seed_decl_key_order",
            "modules_sort_decl_keys",
            "modules_sort_decl_keys_scatter",
            "modules_validate_decls",
            "modules_mark_decl_namespace_keys",
            "modules_scatter_decl_namespace_keys",
            "modules_count_import_visibility",
            "modules_scatter_import_visibility",
            "modules_sort_import_visible_keys",
            "modules_sort_import_visible_keys_scatter",
            "modules_build_import_visible_key_tables",
            "modules_validate_import_visible_keys",
            "modules_resolve_local_paths",
            "modules_resolve_imported_paths",
            "modules_resolve_qualified_paths",
            "modules_clear_type_path_types",
            "modules_project_type_paths",
            "modules_project_type_instances",
            "modules_mark_value_call_paths",
            "modules_project_value_paths",
            "modules_consume_value_calls",
            "modules_consume_value_consts",
            "modules_consume_value_enum_units",
            "modules_consume_value_enum_calls",
            "ModulePathState",
            "path_record_flag",
            "path_record_prefix",
            "path_segment_name_id",
            "module_record_prefix",
            "import_record_prefix",
            "decl_record_prefix",
            "module_file_id",
            "module_key_segment_name_id",
            "module_key_to_module_id",
            "module_key_order_tmp",
            "module_key_radix_block_histogram",
            "module_id_by_file_id",
            "import_path_id",
            "import_module_id",
            "import_target_module_id",
            "import_status",
            "decl_module_id",
            "path_owner_module_id",
            "decl_key_to_decl_id",
            "decl_key_order_tmp",
            "decl_key_radix_block_histogram",
            "decl_status",
            "decl_duplicate_of",
            "decl_parent_type_decl",
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
            "import_visible_key_radix_block_histogram",
            "resolved_type_decl",
            "resolved_value_decl",
            "resolved_type_status",
            "resolved_value_status",
            "module_type_path_type",
            "module_type_path_status",
            "module_value_path_expr_head",
            "module_value_path_call_head",
            "module_value_path_status",
            "project_type_instances",
            "consume_value_calls",
            "consume_value_consts",
            "consume_value_enum_units",
            "consume_value_enum_calls",
            "decl_name_id",
            "record_module_path_state_with_passes",
            "type_check.modules.mark_records",
            "type_check.modules.path_scan_local",
            "type_check.modules.path_scan_blocks",
            "type_check.modules.path_scan_apply",
            "type_check.modules.scatter_paths",
            "type_check.modules.scatter_path_segments",
            "type_check.modules.module_record_scan",
            "type_check.modules.import_record_scan",
            "type_check.modules.decl_record_scan",
            "type_check.modules.scatter_module_records",
            "type_check.modules.build_module_keys",
            "type_check.modules.sort_module_keys_histogram",
            "type_check.modules.sort_module_keys_scatter",
            "type_check.modules.validate_modules",
            "type_check.modules.clear_file_module_map",
            "type_check.modules.build_file_module_map",
            "type_check.modules.scatter_import_records",
            "type_check.modules.resolve_imports",
            "type_check.modules.scatter_decl_core_records",
            "type_check.modules.attach_record_modules",
            "type_check.modules.seed_decl_key_order",
            "type_check.modules.sort_decl_keys_histogram",
            "type_check.modules.sort_decl_keys_scatter",
            "type_check.modules.validate_decls",
            "type_check.modules.mark_decl_namespace_keys",
            "type_check.modules.decl_type_key_scan",
            "type_check.modules.decl_value_key_scan",
            "type_check.modules.scatter_decl_namespace_keys",
            "type_check.modules.count_import_visibility",
            "type_check.modules.import_visible_type_scan",
            "type_check.modules.import_visible_value_scan",
            "type_check.modules.scatter_import_visible_type",
            "type_check.modules.scatter_import_visible_value",
            "type_check.modules.sort_import_visible_type_keys_histogram",
            "type_check.modules.sort_import_visible_type_keys_scatter",
            "type_check.modules.sort_import_visible_value_keys_histogram",
            "type_check.modules.sort_import_visible_value_keys_scatter",
            "type_check.modules.build_import_visible_type_key_table",
            "type_check.modules.build_import_visible_value_key_table",
            "type_check.modules.validate_import_visible_keys",
            "type_check.modules.resolve_local_type_paths",
            "type_check.modules.resolve_local_value_paths",
            "type_check.modules.resolve_imported_type_paths",
            "type_check.modules.resolve_imported_value_paths",
            "type_check.modules.resolve_qualified_type_paths",
            "type_check.modules.resolve_qualified_value_paths",
            "type_check.modules.clear_type_path_types",
            "type_check.modules.project_type_paths",
            "type_check.modules.project_type_instances",
            "type_check.modules.mark_value_call_paths",
            "type_check.modules.project_value_paths",
            "type_check.modules.consume_value_calls",
            "type_check.modules.consume_value_consts",
            "type_check.modules.consume_value_enum_units",
            "type_check.modules.consume_value_enum_calls",
            "type_check.modules.scatter_decl_span_records",
        ],
    );
    assert_contains_all(
        "compiler",
        &compiler,
        &[
            "record_resident_token_buffer_with_hir_items_on_gpu",
            "GpuTypeCheckHirItemBuffers",
            "hir_item_kind",
            "hir_item_path_start",
            "hir_item_import_target_kind",
        ],
    );
    assert!(
        plan.contains("scheduled by the resident type checker after name id")
            && plan.contains("assignment")
            && plan.contains("prefix-scan path flags")
            && plan.contains("segment name ids")
            && plan.contains("GPU prefix scans over module/import/declaration flags")
            && plan.contains("sorted lookup against `module_key_to_module_id`")
            && plan.contains("`name_id_by_token`"),
        "module plan should describe the wired module-key and import lookup checkpoint"
    );

    for forbidden in [
        "resolved_call_decl",
        "import_resolved_module_token",
        "same_source_qualified",
        "qualified_leaf_token",
        "module_id_for_file",
    ] {
        assert!(
            !gpu.contains(forbidden),
            "pre-resolution path wiring should not contain resolver output or shortcut: {forbidden}"
        );
    }
}

#[test]
fn deleted_module_shader_names_remain_absent() {
    for shader_name in [
        "type_check_modules_00_clear.slang",
        "type_check_modules_00_collect.slang",
        "type_check_modules_00_collect_decls.slang",
        "type_check_modules_00_resolve_imports.slang",
        "type_check_modules_01_same_source_types.slang",
        "type_check_modules_02_patch_visible_types.slang",
        "type_check_modules_01_dense_scan.slang",
        "type_check_modules_02_dense_scatter.slang",
        "type_check_modules_02b_dense_scatter_imports.slang",
        "type_check_modules_02c_dense_scatter_decls.slang",
        "type_check_modules_03_attach_ids.slang",
    ] {
        assert!(
            !shader_path(shader_name).exists(),
            "deleted resolver shader should stay absent: {shader_name}"
        );
    }
}

#[test]
fn new_module_path_shaders_compile_with_slangc_when_available() {
    let Some(slangc) = slangc_command() else {
        eprintln!("skipping direct slangc audit because SLANGC/slangc is unavailable");
        return;
    };

    let out_dir = env::temp_dir().join(format!(
        "laniusc_module_path_records_audit_{}",
        std::process::id()
    ));
    fs::create_dir_all(&out_dir).unwrap_or_else(|err| {
        panic!(
            "create direct slangc audit output dir {}: {err}",
            out_dir.display()
        )
    });

    for file_name in module_shader_files() {
        let stem = Path::new(file_name)
            .file_stem()
            .and_then(|s| s.to_str())
            .expect("shader file stem");
        let spv_out = out_dir.join(format!("{stem}.spv"));
        let refl_out = out_dir.join(format!("{stem}.reflect.json"));
        let output = Command::new(&slangc)
            .arg("-target")
            .arg("spirv")
            .arg("-profile")
            .arg("glsl_450")
            .arg("-fvk-use-entrypoint-name")
            .arg("-reflection-json")
            .arg(&refl_out)
            .arg("-emit-spirv-directly")
            .arg("-O1")
            .arg("-I")
            .arg(repo_root().join("shaders"))
            .arg("-I")
            .arg(repo_root().join("shaders").join("type_checker"))
            .arg("-o")
            .arg(&spv_out)
            .arg(shader_path(file_name))
            .output()
            .unwrap_or_else(|err| panic!("run slangc for {file_name}: {err}"));
        assert!(
            output.status.success(),
            "slangc should compile {file_name}\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
