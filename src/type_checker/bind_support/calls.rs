use super::{super::*, common::reflected_bind_group_from_resources};

pub(in crate::type_checker) fn create_call_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<CallBindGroups> {
    Ok(CallBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_clear",
            &passes.calls_clear,
            resources,
        )?,
        return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_return_refs",
            &passes.calls_return_refs,
            resources,
        )?,
        entrypoints: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_entrypoints",
            &passes.calls_entrypoints,
            resources,
        )?,
        functions: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_functions",
            &passes.calls_functions,
            resources,
        )?,
        param_types: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_param_types",
            &passes.calls_param_types,
            resources,
        )?,
        intrinsics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_intrinsics",
            &passes.calls_intrinsics,
            resources,
        )?,
        clear_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_clear_hir_call_args",
            &passes.calls_clear_hir_call_args,
            resources,
        )?,
        pack_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_pack_hir_call_args",
            &passes.calls_pack_hir_call_args,
            resources,
        )?,
        resolve: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_resolve",
            &passes.calls_resolve,
            resources,
        )?,
        infer_array_generics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_infer_array_generics",
            &passes.calls_infer_array_generics,
            resources,
        )?,
        validate_array_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_validate_array_results",
            &passes.calls_validate_array_results,
            resources,
        )?,
        erase_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_erase_generic_params",
            &passes.calls_erase_generic_params,
            resources,
        )?,
    })
}
