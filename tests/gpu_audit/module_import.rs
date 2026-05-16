use std::path::Path;

use super::support::type_checker_gpu_sources;

#[test]
fn module_import_type_checker_slice_uses_paper_aligned_tables_only() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let requirements = include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md");
    let module_plan = include_str!("../../docs/MODULE_RESOLUTION_GPU_PLAN.md");
    let type_checker = type_checker_gpu_sources();
    let calls_shader = include_str!("../../shaders/type_checker/type_check_calls_03_resolve.slang");
    let scope_shader = include_str!("../../shaders/type_checker/type_check_scope.slang");

    assert!(
        requirements.contains("module/import resolver foundation now uses")
            && requirements.contains("sort/deduplicate")
            && requirements.contains("identifiers into stable GPU name ids"),
        "LANGUAGE_REQUIREMENTS should state that the replacement module/import slice is paper-aligned"
    );
    assert!(
        module_plan.contains("Deleted Misleading Slice")
            && module_plan.contains("sort/deduplicate")
            && module_plan.contains("type_check_modules_05_resolve_imports.slang")
            && module_plan.contains("sorted lookup tables"),
        "module plan should document the deletion and the paper-aligned replacement shape"
    );

    for rel in [
        "shaders/type_checker/type_check_modules_00_collect.slang",
        "shaders/type_checker/type_check_modules_00_collect_decls.slang",
        "shaders/type_checker/type_check_modules_00_resolve_imports.slang",
        "shaders/type_checker/type_check_modules_01_same_source_types.slang",
        "shaders/type_checker/type_check_modules_02_patch_visible_types.slang",
        "shaders/type_checker/type_check_names_00_hash.slang",
        "shaders/type_checker/type_check_modules_00_clear.slang",
        "shaders/type_checker/type_check_modules_01_dense_scan.slang",
        "shaders/type_checker/type_check_modules_02_dense_scatter.slang",
        "shaders/type_checker/type_check_modules_02b_dense_scatter_imports.slang",
        "shaders/type_checker/type_check_modules_02c_dense_scatter_decls.slang",
        "shaders/type_checker/type_check_modules_03_attach_ids.slang",
    ] {
        assert!(
            !root.join(rel).exists(),
            "misleading module/import type-checker slice should stay deleted: {rel}"
        );
    }

    for needle in [
        "type_check_names_00_hash",
        "type_check_modules_00_clear",
        "type_check_modules_01_dense_scan",
        "type_check_modules_02_dense_scatter",
        "type_check_modules_02b_dense_scatter_imports",
        "type_check_modules_02c_dense_scatter_decls",
        "type_check_modules_03_attach_ids",
        "type_check.names.hash",
        "type_check_resident_modules_clear",
        "type_check.modules.dense_scan",
        "type_check.modules.dense_scatter_modules",
        "type_check.modules.dense_scatter_imports",
        "type_check.modules.dense_scatter_decls",
        "type_check.modules.dense_attach_ids",
        "ident_hash",
        "ident_len",
        "dense_counts",
        "module_id_for_file",
        "ModuleMetadataBindGroups",
        "ModuleDenseScan",
        "HirItemMetadataBuffers",
        "hir_item_metadata",
    ] {
        assert!(
            !type_checker.contains(needle),
            "GPU type checker should not keep deleted module/import slice wiring: {needle}"
        );
    }

    for needle in [
        "StructuredBuffer<uint> dense_counts",
        "StructuredBuffer<uint> module_records",
        "StructuredBuffer<uint> import_records",
        "token_belongs_to_module_metadata_ast_span",
        "same_source_qualified",
        "qualified_leaf_token",
    ] {
        assert!(
            !calls_shader.contains(needle),
            "call resolution should not keep deleted module/import shortcuts: {needle}"
        );
    }

    assert!(
        calls_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && !calls_shader.contains("token_hash"),
        "unqualified function lookup should use interned name ids, not source-byte hashes"
    );
    assert!(
        !type_checker.contains("type_check_modules_00_resolve_imports")
            && !type_checker.contains("import_resolved_module_token")
            && !type_checker.contains("type_check_modules_00_collect")
            && !type_checker.contains("type_check_modules_01_same_source_types")
            && !type_checker.contains("type_check_modules_02_patch_visible_types"),
        "scan-based and same-source module resolver wiring must stay deleted"
    );
    assert!(
        type_checker.contains("type_check_modules_05_resolve_imports")
            && type_checker.contains("type_check.modules.resolve_imports")
            && type_checker.contains("import_target_module_id")
            && type_checker.contains("import_status"),
        "the only live import resolver checkpoint should be the sorted module-key lookup"
    );
    assert!(
        !scope_shader.contains("record_error(i, ERR_BAD_HIR, TK_IMPORT)")
            && type_checker.contains("module_type_path_type")
            && type_checker.contains("module_value_path_expr_head")
            && type_checker.contains("module_value_path_status")
            && type_checker.contains("type_check.modules.project_type_paths")
            && type_checker.contains("type_check.modules.project_value_paths")
            && type_checker.contains("type_check_modules_10h_consume_value_calls")
            && type_checker.contains("type_check.modules.consume_value_calls")
            && type_checker.contains("modules_consume_value_calls")
            && type_checker.contains("type_check_modules_10i_consume_value_consts")
            && type_checker.contains("type_check.modules.consume_value_consts")
            && type_checker.contains("modules_consume_value_consts")
            && type_checker.contains("type_check_modules_10j_consume_value_enum_units")
            && type_checker.contains("type_check.modules.consume_value_enum_units")
            && type_checker.contains("modules_consume_value_enum_units")
            && type_checker.contains("type_check_modules_10k_project_type_instances")
            && type_checker.contains("type_check.modules.project_type_instances")
            && type_checker.contains("modules_project_type_instances")
            && type_checker.contains("type_check_modules_10l_consume_value_enum_calls")
            && type_checker.contains("type_check.modules.consume_value_enum_calls")
            && type_checker.contains("modules_consume_value_enum_calls")
            && type_checker.contains("decl_parent_type_decl"),
        "module/import headers should not fail through a blanket token check; consumers should use GPU resolver projections"
    );
}
