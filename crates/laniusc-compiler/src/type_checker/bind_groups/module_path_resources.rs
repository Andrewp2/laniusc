use super::super::*;

/// Registers module/path outputs or shape-compatible aliases for the no-HIR path.
pub(super) fn register_module_path_resources<'a>(
    resources: &mut ResourceMap<'a>,
    module_path: Option<&'a ModulePathState>,
) -> Result<()> {
    if let Some(module_path) = module_path {
        module_path.resources.register_resources(resources);
        if let Some(dependency_visibility) = module_path.dependency_visibility.as_ref() {
            resources.buffer(
                "resolved_dependency_library_id",
                &dependency_visibility.resolved_dependency_library_id,
            );
            resources.buffer(
                "resolved_dependency_unit_id",
                &dependency_visibility.resolved_dependency_unit_id,
            );
            resources.buffer(
                "resolved_dependency_local_index",
                &dependency_visibility.resolved_dependency_local_index,
            );
        } else {
            // Keep the reflected semantic projection bindable for local-only
            // units. The aliases are never consumed because all dependency
            // identity columns remain INVALID in this mode.
            resources.alias("resolved_dependency_library_id", "resolved_value_decl")?;
            resources.alias("resolved_dependency_unit_id", "resolved_value_decl")?;
            resources.alias("resolved_dependency_local_index", "resolved_value_decl")?;
        }
        resources.buffer("module_record_count_out", &module_path.module_count_out);
        resources.buffer("import_record_count_out", &module_path.import_count_out);
        resources.buffer("decl_type_public_prefix", &module_path.decl_status);
        resources.buffer(
            "sorted_module_key_order",
            &module_path.module_key_to_module_id,
        );
        resources.buffer("path_prefix_id", &module_path.path_prefix_id_a);
        return Ok(());
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
        "resolved_dependency_library_id",
        "resolved_dependency_unit_id",
        "resolved_dependency_local_index",
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
    Ok(())
}
