use super::super::*;

/// Registers the compact module/path artifact. Absent dependency identities
/// bind immutable empty-page storage, never a writable workspace placeholder.
pub(super) fn register_module_path_resources<'a>(
    resources: &mut ResourceMap<'a>,
    module_path: &'a ModulePathState,
    empty_dependency_words: &'a LaniusBuffer<u32>,
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
            "resolved_dependency_value_library_id",
            &dependency_visibility.resolved_dependency_value_library_id,
        );
        resources.buffer(
            "resolved_dependency_value_unit_id",
            &dependency_visibility.resolved_dependency_value_unit_id,
        );
        resources.buffer(
            "resolved_dependency_value_local_index",
            &dependency_visibility.resolved_dependency_value_local_index,
        );
        resources.buffer(
            "dependency_declaration_field_count",
            &dependency_visibility.declaration_field_count,
        );
    } else {
        // These reflected inputs can share immutable storage. Aliasing a
        // workspace table here hides its lifetime from the resource graph and
        // can bind one physical buffer as both read-only and writable.
        for name in [
            "resolved_dependency_library_id",
            "resolved_dependency_unit_id",
            "resolved_dependency_local_index",
            "resolved_dependency_value_library_id",
            "resolved_dependency_value_unit_id",
            "resolved_dependency_value_local_index",
            "resolved_dependency_trait_header",
            "dependency_declaration_field_count",
        ] {
            resources.buffer(name, empty_dependency_words);
        }
        resources.alias("import_target_dependency_module_id", "resolved_value_decl")?;
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
