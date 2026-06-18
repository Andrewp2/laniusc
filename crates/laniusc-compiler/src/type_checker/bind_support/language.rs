use super::{super::*, common::reflected_bind_group_from_resources};

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
            &passes.language_names_clear,
            resources,
        )?,
        type_codes_clear: reflected_bind_group_from_resources(
            device,
            "type_check_language_type_codes_clear",
            &passes.language_type_codes_clear,
            resources,
        )?,
        decls_materialize: reflected_bind_group_from_resources(
            device,
            "type_check_language_decls_materialize",
            &passes.language_decls_materialize,
            resources,
        )?,
    })
}
