use super::super::*;

/// Builds bind groups for builtin language names and builtin declarations.
pub(in crate::type_checker) fn create_language_name_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<LanguageNameBindGroups> {
    Ok(LanguageNameBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_language_names_clear",
            &passes.kernel("type_checker/language/names/00_clear"),
            resources,
        )?,
        type_codes_clear: reflected_bind_group_from_resources(
            device,
            "type_check_language_type_codes_clear",
            &passes.kernel("type_checker/language/decls/00a_clear_type_codes"),
            resources,
        )?,
        decls_materialize: reflected_bind_group_from_resources(
            device,
            "type_check_language_decls_materialize",
            &passes.kernel("type_checker/language/decls/00_materialize"),
            resources,
        )?,
    })
}
