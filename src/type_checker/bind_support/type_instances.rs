use super::{super::*, common::reflected_bind_group_from_resources};

pub(in crate::type_checker) fn create_type_instance_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<TypeInstanceBindGroups> {
    Ok(TypeInstanceBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear",
            &passes.type_instances_clear,
            resources,
        )?,
        decl_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_generic_params",
            &passes.type_instances_decl_generic_params,
            resources,
        )?,
        generic_param_use_slots: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_generic_param_use_slots",
            &passes.type_instances_generic_param_use_slots,
            resources,
        )?,
        collect: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect",
            &passes.type_instances_collect,
            resources,
        )?,
        collect_named: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named",
            &passes.type_instances_collect_named,
            resources,
        )?,
        collect_aggregate_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_refs",
            &passes.type_instances_collect_aggregate_refs,
            resources,
        )?,
        collect_aggregate_details: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_details",
            &passes.type_instances_collect_aggregate_details,
            resources,
        )?,
        collect_named_arg_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named_arg_refs",
            &passes.type_instances_collect_named_arg_refs,
            resources,
        )?,
        decl_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_refs",
            &passes.type_instances_decl_refs,
            resources,
        )?,
        member_receivers: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_receivers",
            &passes.type_instances_member_receivers,
            resources,
        )?,
        member_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_results",
            &passes.type_instances_member_results,
            resources,
        )?,
        member_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_substitute",
            &passes.type_instances_member_substitute,
            resources,
        )?,
        struct_init_clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_clear",
            &passes.type_instances_struct_init_clear,
            resources,
        )?,
        struct_init_fields: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_fields",
            &passes.type_instances_struct_init_fields,
            resources,
        )?,
        struct_init_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_substitute",
            &passes.type_instances_struct_init_substitute,
            resources,
        )?,
        array_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_return_refs",
            &passes.type_instances_array_return_refs,
            resources,
        )?,
        array_literal_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_literal_return_refs",
            &passes.type_instances_array_literal_return_refs,
            resources,
        )?,
        array_index_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_index_results",
            &passes.type_instances_array_index_results,
            resources,
        )?,
        validate_aggregate_access: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_validate_aggregate_access",
            &passes.type_instances_validate_aggregate_access,
            resources,
        )?,
    })
}
