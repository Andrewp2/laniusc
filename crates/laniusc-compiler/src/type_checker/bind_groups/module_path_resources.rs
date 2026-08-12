use super::super::*;

/// Registers the compact module/path artifact and local aliases for absent
/// dependency interfaces.
pub(super) fn register_module_path_resources<'a>(
    resources: &mut ResourceMap<'a>,
    module_path: &'a ModulePathState,
) -> Result<()> {
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
        resources.buffer(
            "dependency_declaration_field_count",
            &dependency_visibility.declaration_field_count,
        );
    } else {
        // Local-only units never consume dependency identities, but reflected
        // bindings still require shape-compatible resources.
        resources.alias("resolved_dependency_library_id", "resolved_value_decl")?;
        resources.alias("resolved_dependency_unit_id", "resolved_value_decl")?;
        resources.alias("resolved_dependency_local_index", "resolved_value_decl")?;
        resources.alias("dependency_declaration_field_count", "resolved_value_decl")?;
    }
    resources.buffer("module_record_count_out", &module_path.module_count_out);
    resources.buffer("import_record_count_out", &module_path.import_count_out);
    resources.buffer("decl_type_public_prefix", &module_path.decl_status);
    resources.buffer(
        "module_by_canonical_id",
        &module_path.module_by_canonical_id,
    );
    resources.buffer("path_prefix_id", &module_path.path_prefix_id_a);
    Ok(())
}
