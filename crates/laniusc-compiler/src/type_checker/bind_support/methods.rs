use super::{super::*, common::reflected_bind_group_from_resources};

/// Builds method declaration and method-call resolution bind groups.
pub(in crate::type_checker) fn create_method_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    keys: MethodKeyBindGroups,
) -> Result<MethodBindGroups> {
    Ok(MethodBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_clear",
            &passes.methods_clear,
            resources,
        )?,
        collect: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_collect",
            &passes.methods_collect,
            resources,
        )?,
        attach_metadata: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_attach_metadata",
            &passes.methods_attach_metadata,
            resources,
        )?,
        bind_self_receivers: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_bind_self_receivers",
            &passes.methods_bind_self_receivers,
            resources,
        )?,
        keys,
        mark_call_keys: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_mark_call_keys",
            &passes.methods_mark_call_keys,
            resources,
        )?,
        mark_call_return_keys: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_mark_call_return_keys",
            &passes.methods_mark_call_return_keys,
            resources,
        )?,
        resolve_table: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_resolve_table",
            &passes.methods_resolve_table,
            resources,
        )?,
        resolve: reflected_bind_group_from_resources(
            device,
            "type_check_resident_methods_resolve",
            &passes.methods_resolve,
            resources,
        )?,
    })
}
