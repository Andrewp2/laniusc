use super::super::*;

/// Registers module/path outputs or shape-compatible aliases for the no-HIR path.
pub(super) fn register_module_path_resources<'a>(
    resources: &mut ResourceMap<'a>,
    module_path: Option<&'a ModulePathState>,
) {
    if let Some(module_path) = module_path {
        resources.buffer(
            "module_table_count_out",
            &module_path.module_table_count_out,
        );
        resources.buffer("module_id_by_file_id", &module_path.module_id_by_file_id);
        resources.buffer("path_count_out", &module_path.path_count_out);
        resources.buffer("path_kind", &module_path.path_kind);
        resources.buffer("path_segment_count", &module_path.path_segment_count);
        resources.buffer("path_segment_base", &module_path.path_segment_base);
        resources.buffer("path_segment_name_id", &module_path.path_segment_name_id);
        resources.buffer("path_segment_token", &module_path.path_segment_token);
        resources.buffer("path_owner_hir", &module_path.path_owner_hir);
        resources.buffer("path_owner_token", &module_path.path_owner_token);
        resources.buffer("path_id_by_owner_hir", &module_path.path_id_by_owner_hir);
        resources.buffer(
            "path_id_by_owner_token",
            &module_path.path_id_by_owner_token,
        );
        resources.buffer("path_owner_module_id", &module_path.path_owner_module_id);
        resources.buffer("resolved_type_decl", &module_path.resolved_type_decl);
        resources.buffer("resolved_value_decl", &module_path.resolved_value_decl);
        resources.buffer("resolved_value_status", &module_path.resolved_value_status);
        resources.buffer("decl_token_start", &module_path.decl_token_start);
        resources.buffer(
            "decl_type_key_count_out",
            &module_path.decl_type_key_count_out,
        );
        resources.buffer(
            "decl_type_key_to_decl_id",
            &module_path.decl_type_key_to_decl_id,
        );
        resources.buffer(
            "decl_value_key_count_out",
            &module_path.decl_value_key_count_out,
        );
        resources.buffer(
            "decl_value_key_to_decl_id",
            &module_path.decl_value_key_to_decl_id,
        );
        resources.buffer("decl_module_id", &module_path.decl_module_id);
        resources.buffer("decl_name_id", &module_path.decl_name_id);
        resources.buffer("decl_name_token", &module_path.decl_name_token);
        resources.buffer("decl_kind", &module_path.decl_kind);
        resources.buffer(
            "import_visible_type_count_out",
            &module_path.import_visible_type_count_out,
        );
        resources.buffer(
            "import_visible_type_key_module_id",
            &module_path.import_visible_type_key_module_id,
        );
        resources.buffer(
            "import_visible_type_key_name_id",
            &module_path.import_visible_type_key_name_id,
        );
        resources.buffer(
            "import_visible_type_key_to_decl_id",
            &module_path.import_visible_type_key_to_decl_id,
        );
        resources.buffer(
            "import_visible_type_status",
            &module_path.import_visible_type_status,
        );
        resources.buffer(
            "import_visible_value_count_out",
            &module_path.import_visible_value_count_out,
        );
        resources.buffer(
            "import_visible_value_key_module_id",
            &module_path.import_visible_value_key_module_id,
        );
        resources.buffer(
            "import_visible_value_key_name_id",
            &module_path.import_visible_value_key_name_id,
        );
        resources.buffer(
            "import_visible_value_key_to_decl_id",
            &module_path.import_visible_value_key_to_decl_id,
        );
        resources.buffer(
            "import_visible_value_status",
            &module_path.import_visible_value_status,
        );
        return;
    }

    for name in [
        "module_table_count_out",
        "path_count_out",
        "decl_type_key_count_out",
        "decl_value_key_count_out",
        "import_visible_type_count_out",
        "import_visible_value_count_out",
    ] {
        resources.add(name, resources["hir_active_count"].clone());
    }
    for name in [
        "module_id_by_file_id",
        "resolved_type_decl",
        "resolved_value_decl",
        "resolved_value_status",
        "decl_token_start",
        "decl_type_key_to_decl_id",
        "decl_value_key_to_decl_id",
        "decl_module_id",
        "decl_name_id",
        "decl_name_token",
        "decl_kind",
        "import_visible_type_key_module_id",
        "import_visible_type_key_name_id",
        "import_visible_type_key_to_decl_id",
        "import_visible_type_status",
        "import_visible_value_key_module_id",
        "import_visible_value_key_name_id",
        "import_visible_value_key_to_decl_id",
        "import_visible_value_status",
    ] {
        resources.add(name, resources["visible_decl"].clone());
    }
    for name in [
        "path_kind",
        "path_segment_count",
        "path_segment_base",
        "path_segment_name_id",
        "path_segment_token",
        "path_owner_hir",
        "path_owner_token",
        "path_id_by_owner_hir",
        "path_id_by_owner_token",
    ] {
        resources.add(name, resources["parent"].clone());
    }
    resources.add(
        "path_owner_module_id",
        resources["module_value_path_status"].clone(),
    );
}
