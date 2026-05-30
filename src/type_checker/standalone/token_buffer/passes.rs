use super::super::super::*;
use crate::gpu::passes_core::PassData;

pub(super) struct TokenTypeCheckPasses {
    pub(super) tokens: &'static PassData,
    pub(super) control: &'static PassData,
    pub(super) scope: &'static PassData,
    pub(super) language_names_clear: &'static PassData,
    pub(super) language_names_mark: &'static PassData,
    pub(super) language_type_codes_clear: &'static PassData,
    pub(super) language_decls_materialize: &'static PassData,
    pub(super) calls_clear: &'static PassData,
    pub(super) calls_return_refs: &'static PassData,
    pub(super) calls_entrypoints: &'static PassData,
    pub(super) calls_functions: &'static PassData,
    pub(super) calls_param_types: &'static PassData,
    pub(super) calls_intrinsics: &'static PassData,
    pub(super) calls_clear_hir_call_args: &'static PassData,
    pub(super) calls_pack_hir_call_args: &'static PassData,
    pub(super) calls_resolve: &'static PassData,
    pub(super) calls_infer_array_generics: &'static PassData,
    pub(super) calls_validate_array_results: &'static PassData,
    pub(super) calls_erase_generic_params: &'static PassData,
    pub(super) methods_clear: &'static PassData,
    pub(super) methods_collect: &'static PassData,
    pub(super) methods_attach_metadata: &'static PassData,
    pub(super) methods_bind_self_receivers: &'static PassData,
    pub(super) methods_seed_key_order: &'static PassData,
    pub(super) methods_sort_keys: &'static PassData,
    pub(super) methods_sort_keys_scatter: &'static PassData,
    pub(super) methods_validate_keys: &'static PassData,
    pub(super) methods_mark_call_keys: &'static PassData,
    pub(super) methods_mark_call_return_keys: &'static PassData,
    pub(super) methods_resolve_table: &'static PassData,
    pub(super) methods_resolve: &'static PassData,
    pub(super) counted_scan_local: &'static PassData,
    pub(super) counted_scan_blocks: &'static PassData,
    pub(super) counted_scan_apply: &'static PassData,
    pub(super) names_radix_dispatch_args: &'static PassData,
    pub(super) names_radix_bucket_prefix: &'static PassData,
    pub(super) names_radix_bucket_bases: &'static PassData,
    pub(super) type_instances_clear: &'static PassData,
    pub(super) type_instances_mark_generic_param_records: &'static PassData,
    pub(super) type_instances_propagate_generic_decl_owner: &'static PassData,
    pub(super) type_instances_decl_generic_params: &'static PassData,
    pub(super) type_instances_sort_generic_param_keys: &'static PassData,
    pub(super) type_instances_sort_generic_param_keys_scatter: &'static PassData,
    pub(super) type_instances_generic_param_use_slots: &'static PassData,
    pub(super) type_instances_seed_struct_field_keys: &'static PassData,
    pub(super) type_instances_sort_struct_field_keys: &'static PassData,
    pub(super) type_instances_sort_struct_field_keys_scatter: &'static PassData,
    pub(super) type_instances_collect: &'static PassData,
    pub(super) type_instances_collect_named: &'static PassData,
    pub(super) type_instances_collect_aggregate_refs: &'static PassData,
    pub(super) type_instances_collect_aggregate_details: &'static PassData,
    pub(super) type_instances_collect_named_arg_refs: &'static PassData,
    pub(super) type_instances_decl_refs: &'static PassData,
    pub(super) type_instances_member_receivers: &'static PassData,
    pub(super) type_instances_member_results: &'static PassData,
    pub(super) type_instances_member_substitute: &'static PassData,
    pub(super) type_instances_struct_init_clear: &'static PassData,
    pub(super) type_instances_struct_init_contexts: &'static PassData,
    pub(super) type_instances_struct_init_fields: &'static PassData,
    pub(super) type_instances_struct_init_substitute: &'static PassData,
    pub(super) type_instances_array_return_refs: &'static PassData,
    pub(super) type_instances_array_literal_return_refs: &'static PassData,
    pub(super) type_instances_enum_ctors: &'static PassData,
    pub(super) type_instances_array_index_results: &'static PassData,
    pub(super) type_instances_validate_aggregate_access: &'static PassData,
    pub(super) conditions_hir: &'static PassData,
}

impl TokenTypeCheckPasses {
    pub(super) fn load(
        device: &wgpu::Device,
        hir_node_capacity: u32,
    ) -> Result<Self, GpuTypeCheckError> {
        Ok(Self {
            tokens: type_check_tokens_pass(device)?,
            control: if hir_node_capacity > 0 {
                type_check_control_hir_pass(device)?
            } else {
                type_check_control_pass(device)?
            },
            scope: type_check_scope_pass(device)?,
            language_names_clear: type_check_language_names_clear_pass(device)?,
            language_names_mark: type_check_language_names_mark_pass(device)?,
            language_type_codes_clear: type_check_language_type_codes_clear_pass(device)?,
            language_decls_materialize: type_check_language_decls_materialize_pass(device)?,
            calls_clear: type_check_calls_clear_pass(device)?,
            calls_return_refs: type_check_calls_return_refs_pass(device)?,
            calls_entrypoints: type_check_calls_entrypoints_pass(device)?,
            calls_functions: type_check_calls_functions_pass(device)?,
            calls_param_types: type_check_calls_param_types_pass(device)?,
            calls_intrinsics: type_check_calls_intrinsics_pass(device)?,
            calls_clear_hir_call_args: type_check_calls_clear_hir_call_args_pass(device)?,
            calls_pack_hir_call_args: type_check_calls_pack_hir_call_args_pass(device)?,
            calls_resolve: type_check_calls_resolve_pass(device)?,
            calls_infer_array_generics: type_check_calls_infer_array_generics_pass(device)?,
            calls_validate_array_results: type_check_calls_validate_array_results_pass(device)?,
            calls_erase_generic_params: type_check_calls_erase_generic_params_pass(device)?,
            methods_clear: type_check_methods_clear_pass(device)?,
            methods_collect: type_check_methods_collect_pass(device)?,
            methods_attach_metadata: type_check_methods_attach_metadata_pass(device)?,
            methods_bind_self_receivers: type_check_methods_bind_self_receivers_pass(device)?,
            methods_seed_key_order: type_check_methods_seed_key_order_pass(device)?,
            methods_sort_keys: type_check_methods_sort_keys_pass(device)?,
            methods_sort_keys_scatter: type_check_methods_sort_keys_scatter_pass(device)?,
            methods_validate_keys: type_check_methods_validate_keys_pass(device)?,
            methods_mark_call_keys: type_check_methods_mark_call_keys_pass(device)?,
            methods_mark_call_return_keys: type_check_methods_mark_call_return_keys_pass(device)?,
            methods_resolve_table: type_check_methods_resolve_table_pass(device)?,
            methods_resolve: type_check_methods_resolve_pass(device)?,
            counted_scan_local: type_check_counted_scan_local_pass(device)?,
            counted_scan_blocks: type_check_counted_scan_blocks_pass(device)?,
            counted_scan_apply: type_check_counted_scan_apply_pass(device)?,
            names_radix_dispatch_args: type_check_names_radix_dispatch_args_pass(device)?,
            names_radix_bucket_prefix: type_check_names_radix_bucket_prefix_pass(device)?,
            names_radix_bucket_bases: type_check_names_radix_bucket_bases_pass(device)?,
            type_instances_clear: type_check_type_instances_clear_pass(device)?,
            type_instances_mark_generic_param_records:
                type_check_type_instances_mark_generic_param_records_pass(device)?,
            type_instances_propagate_generic_decl_owner:
                type_check_type_instances_propagate_generic_decl_owner_pass(device)?,
            type_instances_decl_generic_params: type_check_type_instances_decl_generic_params_pass(
                device,
            )?,
            type_instances_sort_generic_param_keys:
                type_check_type_instances_sort_generic_param_keys_pass(device)?,
            type_instances_sort_generic_param_keys_scatter:
                type_check_type_instances_sort_generic_param_keys_scatter_pass(device)?,
            type_instances_generic_param_use_slots:
                type_check_type_instances_generic_param_use_slots_pass(device)?,
            type_instances_seed_struct_field_keys:
                type_check_type_instances_seed_struct_field_keys_pass(device)?,
            type_instances_sort_struct_field_keys:
                type_check_type_instances_sort_struct_field_keys_pass(device)?,
            type_instances_sort_struct_field_keys_scatter:
                type_check_type_instances_sort_struct_field_keys_scatter_pass(device)?,
            type_instances_collect: type_check_type_instances_collect_pass(device)?,
            type_instances_collect_named: type_check_type_instances_collect_named_pass(device)?,
            type_instances_collect_aggregate_refs:
                type_check_type_instances_collect_aggregate_refs_pass(device)?,
            type_instances_collect_aggregate_details:
                type_check_type_instances_collect_aggregate_details_pass(device)?,
            type_instances_collect_named_arg_refs:
                type_check_type_instances_collect_named_arg_refs_pass(device)?,
            type_instances_decl_refs: type_check_type_instances_decl_refs_pass(device)?,
            type_instances_member_receivers: type_check_type_instances_member_receivers_pass(
                device,
            )?,
            type_instances_member_results: type_check_type_instances_member_results_pass(device)?,
            type_instances_member_substitute: type_check_type_instances_member_substitute_pass(
                device,
            )?,
            type_instances_struct_init_clear: type_check_type_instances_struct_init_clear_pass(
                device,
            )?,
            type_instances_struct_init_contexts:
                type_check_type_instances_struct_init_contexts_pass(device)?,
            type_instances_struct_init_fields: type_check_type_instances_struct_init_fields_pass(
                device,
            )?,
            type_instances_struct_init_substitute:
                type_check_type_instances_struct_init_substitute_pass(device)?,
            type_instances_array_return_refs: type_check_type_instances_array_return_refs_pass(
                device,
            )?,
            type_instances_array_literal_return_refs:
                type_check_type_instances_array_literal_return_refs_pass(device)?,
            type_instances_enum_ctors: type_check_type_instances_enum_ctors_pass(device)?,
            type_instances_array_index_results: type_check_type_instances_array_index_results_pass(
                device,
            )?,
            type_instances_validate_aggregate_access:
                type_check_type_instances_validate_aggregate_access_pass(device)?,
            conditions_hir: type_check_conditions_hir_pass(device)?,
        })
    }
}
