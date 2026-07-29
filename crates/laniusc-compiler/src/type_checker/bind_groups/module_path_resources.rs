use super::super::*;

/// Registers module/path outputs or shape-compatible aliases for the no-HIR path.
pub(super) fn register_module_path_resources<'a>(
    resources: &mut ResourceMap<'a>,
    module_path: Option<&'a ModulePathState>,
) {
    if let Some(module_path) = module_path {
        resources.buffer("module_record_count_out", &module_path.module_count_out);
        resources.buffer("import_record_count_out", &module_path.import_count_out);
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
        resources.buffer("resolved_type_status", &module_path.resolved_type_status);
        resources.buffer("resolved_value_decl", &module_path.resolved_value_decl);
        resources.buffer("resolved_value_status", &module_path.resolved_value_status);
        resources.buffer("decl_token_start", &module_path.decl_token_start);
        resources.buffer("decl_count_out", &module_path.decl_count_out);
        resources.buffer("decl_hir_node", &module_path.decl_hir_node);
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
        resources.buffer("decl_namespace", &module_path.decl_namespace);
        resources.buffer("decl_visibility", &module_path.decl_visibility);
        resources.buffer("decl_duplicate_of", &module_path.decl_duplicate_of);
        resources.buffer("decl_status", &module_path.decl_status);
        resources.buffer("decl_type_key_flag", &module_path.decl_type_key_flag);
        resources.buffer("decl_value_key_flag", &module_path.decl_value_key_flag);
        resources.buffer("decl_type_key_prefix", &module_path.decl_type_key_prefix);
        resources.buffer("decl_value_key_prefix", &module_path.decl_value_key_prefix);
        resources.buffer("decl_type_public_prefix", &module_path.decl_status);
        resources.buffer(
            "decl_key_radix_dispatch_args",
            &module_path.decl_key_radix_dispatch_args,
        );
        resources.buffer("import_dispatch_args", &module_path.import_dispatch_args);
        resources.buffer(
            "import_visible_type_count",
            &module_path.import_visible_type_count,
        );
        resources.buffer(
            "import_visible_type_prefix",
            &module_path.import_visible_type_prefix,
        );
        resources.buffer(
            "import_visible_value_count",
            &module_path.import_visible_value_count,
        );
        resources.buffer(
            "import_visible_value_prefix",
            &module_path.import_visible_value_prefix,
        );
        resources.buffer("decl_id_by_name_token", &module_path.decl_id_by_name_token);
        resources.buffer(
            "sorted_module_key_order",
            &module_path.module_key_to_module_id,
        );
        resources.buffer(
            "module_key_canonical_id",
            &module_path.module_key_canonical_id,
        );
        resources.buffer("path_prefix_id", &module_path.path_prefix_id_a);
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
        "module_record_count_out",
        "import_record_count_out",
        "module_table_count_out",
        "path_count_out",
        "decl_type_key_count_out",
        "decl_value_key_count_out",
        "decl_count_out",
        "import_visible_type_count_out",
        "import_visible_value_count_out",
    ] {
        resources.add(name, resources["hir_active_count"].clone());
    }
    for name in [
        "module_id_by_file_id",
        "resolved_type_decl",
        "resolved_type_status",
        "resolved_value_decl",
        "resolved_value_status",
        "decl_token_start",
        "decl_hir_node",
        "decl_type_key_to_decl_id",
        "decl_value_key_to_decl_id",
        "decl_module_id",
        "decl_name_id",
        "decl_namespace",
        "decl_visibility",
        "decl_duplicate_of",
        "decl_status",
        "decl_type_key_flag",
        "decl_value_key_flag",
        "decl_type_key_prefix",
        "decl_value_key_prefix",
        "decl_type_public_prefix",
        "decl_key_radix_dispatch_args",
        "import_dispatch_args",
        "import_visible_type_count",
        "import_visible_type_prefix",
        "import_visible_value_count",
        "import_visible_value_prefix",
        "sorted_module_key_order",
        "module_key_canonical_id",
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
        "path_prefix_id",
    ] {
        resources.add(name, resources["parent"].clone());
    }
    resources.add(
        "path_owner_module_id",
        resources["module_value_path_status"].clone(),
    );
}
