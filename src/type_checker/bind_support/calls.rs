use super::{
    super::*,
    common::reflected_bind_group_from_resources,
    scan::create_counted_u32_scan_bind_groups_with_passes,
};

pub(in crate::type_checker) struct CompactCallArgScanInput<'a> {
    pub(in crate::type_checker) scan_steps: &'a [NameScanStep],
    pub(in crate::type_checker) scan_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_input: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_output_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_total: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_local_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_block_sum: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_prefix_a: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_prefix_b: &'a wgpu::Buffer,
    pub(in crate::type_checker) n_blocks: u32,
}

pub(in crate::type_checker) fn create_call_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    compact_arg_scan: CompactCallArgScanInput<'_>,
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
        mark_compact_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_mark_compact_hir_call_args",
            &passes.calls_mark_compact_hir_call_args,
            resources,
        )?,
        compact_hir_call_arg_scan: create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.calls.compact_hir_call_arg_scan",
            compact_arg_scan.scan_steps,
            compact_arg_scan.scan_count,
            compact_arg_scan.scan_input,
            compact_arg_scan.scan_output_prefix,
            compact_arg_scan.scan_total,
            compact_arg_scan.scan_local_prefix,
            compact_arg_scan.scan_block_sum,
            compact_arg_scan.scan_prefix_a,
            compact_arg_scan.scan_prefix_b,
        )?,
        compact_hir_call_arg_scan_n_blocks: compact_arg_scan.n_blocks,
        scatter_compact_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_scatter_compact_hir_call_args",
            &passes.calls_scatter_compact_hir_call_args,
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
