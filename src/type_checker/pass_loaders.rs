use super::*;

impl TypeCheckPasses {
    pub(super) fn new(device: &wgpu::Device) -> Result<Self> {
        macro_rules! pass {
            ($label:literal, $file:literal) => {
                crate::gpu::passes_core::make_main_pass!(device, $label, shader: $file)?
            };
        }

        Ok(Self {
            names_mark_lexemes: pass!(
                "type_check_names_00_mark_lexemes",
                "type_check_names_00_mark_lexemes"
            ),
            names_scan_local: pass!(
                "type_check_names_scan_00_local",
                "type_check_names_scan_00_local"
            ),
            names_scan_blocks: pass!(
                "type_check_names_scan_01_blocks",
                "type_check_names_scan_01_blocks"
            ),
            names_scan_apply: pass!(
                "type_check_names_scan_02_apply",
                "type_check_names_scan_02_apply"
            ),
            names_scatter_lexemes: pass!(
                "type_check_names_01_scatter_lexemes",
                "type_check_names_01_scatter_lexemes"
            ),
            names_radix_histogram: pass!(
                "type_check_names_radix_00_histogram",
                "type_check_names_radix_00_histogram"
            ),
            names_radix_bucket_prefix: pass!(
                "type_check_names_radix_00b_bucket_prefix",
                "type_check_names_radix_00b_bucket_prefix"
            ),
            names_radix_bucket_bases: pass!(
                "type_check_names_radix_00c_bucket_bases",
                "type_check_names_radix_00c_bucket_bases"
            ),
            names_radix_scatter: pass!(
                "type_check_names_radix_01_scatter",
                "type_check_names_radix_01_scatter"
            ),
            names_radix_dedup: pass!(
                "type_check_names_radix_02_adjacent_dedup",
                "type_check_names_radix_02_adjacent_dedup"
            ),
            names_radix_assign_ids: pass!(
                "type_check_names_radix_03_assign_ids",
                "type_check_names_radix_03_assign_ids"
            ),
            language_names_clear: pass!(
                "type_check_language_names_00_clear",
                "type_check_language_names_00_clear"
            ),
            language_names_mark: pass!(
                "type_check_language_names_01_mark",
                "type_check_language_names_01_mark"
            ),
            language_decls_materialize: pass!(
                "type_check_language_decls_00_materialize",
                "type_check_language_decls_00_materialize"
            ),
            modules_mark_records: pass!(
                "type_check_modules_00_mark_records",
                "type_check_modules_00_mark_records"
            ),
            modules_scatter_paths: pass!(
                "type_check_modules_01_scatter_paths",
                "type_check_modules_01_scatter_paths"
            ),
            modules_scatter_path_segments: pass!(
                "type_check_modules_01b_scatter_path_segments",
                "type_check_modules_01b_scatter_path_segments"
            ),
            modules_scatter_module_records: pass!(
                "type_check_modules_02_scatter_module_records",
                "type_check_modules_02_scatter_module_records"
            ),
            modules_scatter_import_records: pass!(
                "type_check_modules_02b_scatter_import_records",
                "type_check_modules_02b_scatter_import_records"
            ),
            modules_scatter_decl_core_records: pass!(
                "type_check_modules_02c_scatter_decl_core_records",
                "type_check_modules_02c_scatter_decl_core_records"
            ),
            modules_scatter_decl_span_records: pass!(
                "type_check_modules_02d_scatter_decl_span_records",
                "type_check_modules_02d_scatter_decl_span_records"
            ),
            modules_build_module_keys: pass!(
                "type_check_modules_02e_build_module_keys",
                "type_check_modules_02e_build_module_keys"
            ),
            modules_sort_module_keys_histogram: pass!(
                "type_check_modules_03_sort_module_keys_histogram",
                "type_check_modules_03_sort_module_keys_histogram"
            ),
            modules_sort_module_keys_scatter: pass!(
                "type_check_modules_03b_sort_module_keys_scatter",
                "type_check_modules_03b_sort_module_keys_scatter"
            ),
            modules_validate_modules: pass!(
                "type_check_modules_04_validate_modules",
                "type_check_modules_04_validate_modules"
            ),
            modules_resolve_imports: pass!(
                "type_check_modules_05_resolve_imports",
                "type_check_modules_05_resolve_imports"
            ),
            modules_clear_file_module_map: pass!(
                "type_check_modules_05b_clear_file_module_map",
                "type_check_modules_05b_clear_file_module_map"
            ),
            modules_build_file_module_map: pass!(
                "type_check_modules_05c_build_file_module_map",
                "type_check_modules_05c_build_file_module_map"
            ),
            modules_attach_record_modules: pass!(
                "type_check_modules_05d_attach_record_modules",
                "type_check_modules_05d_attach_record_modules"
            ),
            modules_seed_decl_key_order: pass!(
                "type_check_modules_06a_seed_decl_key_order",
                "type_check_modules_06a_seed_decl_key_order"
            ),
            modules_sort_decl_keys: pass!(
                "type_check_modules_06_sort_decl_keys",
                "type_check_modules_06_sort_decl_keys"
            ),
            modules_sort_decl_keys_scatter: pass!(
                "type_check_modules_06b_sort_decl_keys_scatter",
                "type_check_modules_06b_sort_decl_keys_scatter"
            ),
            modules_validate_decls: pass!(
                "type_check_modules_07_validate_decls",
                "type_check_modules_07_validate_decls"
            ),
            modules_mark_decl_namespace_keys: pass!(
                "type_check_modules_08_mark_decl_namespace_keys",
                "type_check_modules_08_mark_decl_namespace_keys"
            ),
            modules_scatter_decl_namespace_keys: pass!(
                "type_check_modules_08b_scatter_decl_namespace_keys",
                "type_check_modules_08b_scatter_decl_namespace_keys"
            ),
            modules_count_import_visibility: pass!(
                "type_check_modules_09_count_import_visibility",
                "type_check_modules_09_count_import_visibility"
            ),
            modules_scatter_import_visibility: pass!(
                "type_check_modules_09b_scatter_import_visibility",
                "type_check_modules_09b_scatter_import_visibility"
            ),
            modules_sort_import_visible_keys: pass!(
                "type_check_modules_09c_sort_import_visible_keys",
                "type_check_modules_09c_sort_import_visible_keys"
            ),
            modules_sort_import_visible_keys_scatter: pass!(
                "type_check_modules_09d_sort_import_visible_keys_scatter",
                "type_check_modules_09d_sort_import_visible_keys_scatter"
            ),
            modules_build_import_visible_key_tables: pass!(
                "type_check_modules_09e_build_import_visible_key_tables",
                "type_check_modules_09e_build_import_visible_key_tables"
            ),
            modules_validate_import_visible_keys: pass!(
                "type_check_modules_09f_validate_import_visible_keys",
                "type_check_modules_09f_validate_import_visible_keys"
            ),
            modules_resolve_local_paths: pass!(
                "type_check_modules_10_resolve_local_paths",
                "type_check_modules_10_resolve_local_paths"
            ),
            modules_resolve_imported_paths: pass!(
                "type_check_modules_10b_resolve_imported_paths",
                "type_check_modules_10b_resolve_imported_paths"
            ),
            modules_resolve_qualified_paths: pass!(
                "type_check_modules_10c_resolve_qualified_paths",
                "type_check_modules_10c_resolve_qualified_paths"
            ),
            modules_clear_type_path_types: pass!(
                "type_check_modules_10d_clear_type_path_types",
                "type_check_modules_10d_clear_type_path_types"
            ),
            modules_project_type_paths: pass!(
                "type_check_modules_10e_project_type_paths",
                "type_check_modules_10e_project_type_paths"
            ),
            modules_project_type_aliases: pass!(
                "type_check_modules_10e2_project_type_aliases",
                "type_check_modules_10e2_project_type_aliases"
            ),
            modules_project_type_instances: pass!(
                "type_check_modules_10k_project_type_instances",
                "type_check_modules_10k_project_type_instances"
            ),
            modules_mark_value_call_paths: pass!(
                "type_check_modules_10f_mark_value_call_paths",
                "type_check_modules_10f_mark_value_call_paths"
            ),
            modules_project_value_paths: pass!(
                "type_check_modules_10g_project_value_paths",
                "type_check_modules_10g_project_value_paths"
            ),
            modules_consume_value_calls: pass!(
                "type_check_modules_10h_consume_value_calls",
                "type_check_modules_10h_consume_value_calls"
            ),
            modules_consume_value_consts: pass!(
                "type_check_modules_10i_consume_value_consts",
                "type_check_modules_10i_consume_value_consts"
            ),
            modules_consume_value_enum_units: pass!(
                "type_check_modules_10j_consume_value_enum_units",
                "type_check_modules_10j_consume_value_enum_units"
            ),
            modules_consume_value_enum_calls: pass!(
                "type_check_modules_10l_consume_value_enum_calls",
                "type_check_modules_10l_consume_value_enum_calls"
            ),
            modules_bind_match_patterns: pass!(
                "type_check_modules_10m_bind_match_patterns",
                "type_check_modules_10m_bind_match_patterns"
            ),
            modules_type_match_payloads: pass!(
                "type_check_modules_10m2_type_match_payloads",
                "type_check_modules_10m2_type_match_payloads"
            ),
            modules_type_match_exprs: pass!(
                "type_check_modules_10n_type_match_exprs",
                "type_check_modules_10n_type_match_exprs"
            ),
            type_instances_clear: pass!(
                "type_check_type_instances_00_clear",
                "type_check_type_instances_00_clear"
            ),
            type_instances_decl_generic_params: pass!(
                "type_check_type_instances_00b_decl_generic_params",
                "type_check_type_instances_00b_decl_generic_params"
            ),
            type_instances_collect: pass!(
                "type_check_type_instances_01_collect",
                "type_check_type_instances_01_collect"
            ),
            type_instances_collect_named: pass!(
                "type_check_type_instances_01b_collect_named_instances",
                "type_check_type_instances_01b_collect_named_instances"
            ),
            type_instances_collect_aggregate_refs: pass!(
                "type_check_type_instances_01c_collect_aggregate_refs",
                "type_check_type_instances_01c_collect_aggregate_refs"
            ),
            type_instances_collect_aggregate_details: pass!(
                "type_check_type_instances_01d_collect_aggregate_details",
                "type_check_type_instances_01d_collect_aggregate_details"
            ),
            type_instances_collect_named_arg_refs: pass!(
                "type_check_type_instances_01e_collect_named_arg_refs",
                "type_check_type_instances_01e_collect_named_arg_refs"
            ),
            type_instances_decl_refs: pass!(
                "type_check_type_instances_01f_decl_refs",
                "type_check_type_instances_01f_decl_refs"
            ),
            type_instances_member_receivers: pass!(
                "type_check_type_instances_03a_member_receivers",
                "type_check_type_instances_03a_member_receivers"
            ),
            type_instances_member_results: pass!(
                "type_check_type_instances_03_member_results",
                "type_check_type_instances_03_member_results"
            ),
            type_instances_member_substitute: pass!(
                "type_check_type_instances_03b_member_substitute",
                "type_check_type_instances_03b_member_substitute"
            ),
            type_instances_struct_init_clear: pass!(
                "type_check_type_instances_04a_struct_init_clear",
                "type_check_type_instances_04a_struct_init_clear"
            ),
            type_instances_struct_init_fields: pass!(
                "type_check_type_instances_04_struct_init_fields",
                "type_check_type_instances_04_struct_init_fields"
            ),
            type_instances_struct_init_substitute: pass!(
                "type_check_type_instances_04b_struct_init_substitute",
                "type_check_type_instances_04b_struct_init_substitute"
            ),
            type_instances_array_return_refs: pass!(
                "type_check_type_instances_05_array_return_refs",
                "type_check_type_instances_05_array_return_refs"
            ),
            type_instances_array_literal_return_refs: pass!(
                "type_check_type_instances_05b_array_literal_return_refs",
                "type_check_type_instances_05b_array_literal_return_refs"
            ),
            type_instances_enum_ctors: pass!(
                "type_check_type_instances_06_enum_ctors",
                "type_check_type_instances_06_enum_ctors"
            ),
            type_instances_array_index_results: pass!(
                "type_check_type_instances_07_array_index_results",
                "type_check_type_instances_07_array_index_results"
            ),
            type_instances_validate_aggregate_access: pass!(
                "type_check_type_instances_08_validate_aggregate_access",
                "type_check_type_instances_08_validate_aggregate_access"
            ),
            conditions_hir: pass!("type_check_conditions_hir", "type_check_conditions_hir"),
            tokens: pass!("type_check_tokens", "type_check_tokens_min"),
            control: pass!("type_check_control", "type_check_control"),
            control_hir: pass!("type_check_control_hir", "type_check_control_hir"),
            scope: pass!("type_check_scope", "type_check_scope"),
            calls_clear: pass!("type_check_calls_01_resolve", "type_check_calls_01_resolve"),
            calls_return_refs: pass!(
                "type_check_calls_02a_return_refs_from_hir",
                "type_check_calls_02a_return_refs_from_hir"
            ),
            calls_entrypoints: pass!(
                "type_check_calls_02b_entrypoints",
                "type_check_calls_02b_entrypoints"
            ),
            calls_functions: pass!(
                "type_check_calls_02_functions",
                "type_check_calls_02_functions"
            ),
            calls_param_types: pass!(
                "type_check_calls_02f_params_from_hir",
                "type_check_calls_02f_params_from_hir"
            ),
            calls_intrinsics: pass!(
                "type_check_calls_02c_intrinsics",
                "type_check_calls_02c_intrinsics"
            ),
            calls_clear_hir_call_args: pass!(
                "type_check_calls_02d_clear_hir_call_args",
                "type_check_calls_02d_clear_hir_call_args"
            ),
            calls_pack_hir_call_args: pass!(
                "type_check_calls_02e_pack_hir_call_args",
                "type_check_calls_02e_pack_hir_call_args"
            ),
            calls_resolve: pass!("type_check_calls_03_resolve", "type_check_calls_03_resolve"),
            calls_erase_generic_params: pass!(
                "type_check_calls_04_erase_generic_params",
                "type_check_calls_04_erase_generic_params"
            ),
            methods_clear: pass!("type_check_methods_01_clear", "type_check_methods_01_clear"),
            methods_collect: pass!(
                "type_check_methods_02_collect",
                "type_check_methods_02_collect"
            ),
            methods_attach_metadata: pass!(
                "type_check_methods_02b_attach_metadata",
                "type_check_methods_02b_attach_metadata"
            ),
            methods_bind_self_receivers: pass!(
                "type_check_methods_02c_bind_self_receivers",
                "type_check_methods_02c_bind_self_receivers"
            ),
            methods_seed_key_order: pass!(
                "type_check_methods_03_seed_key_order",
                "type_check_methods_03_seed_key_order"
            ),
            methods_sort_keys: pass!(
                "type_check_methods_04_sort_keys",
                "type_check_methods_04_sort_keys"
            ),
            methods_sort_keys_scatter: pass!(
                "type_check_methods_04b_sort_keys_scatter",
                "type_check_methods_04b_sort_keys_scatter"
            ),
            methods_validate_keys: pass!(
                "type_check_methods_05_validate_keys",
                "type_check_methods_05_validate_keys"
            ),
            methods_mark_call_keys: pass!(
                "type_check_methods_06_mark_call_keys",
                "type_check_methods_06_mark_call_keys"
            ),
            methods_mark_call_return_keys: pass!(
                "type_check_methods_06b_mark_call_return_keys",
                "type_check_methods_06b_mark_call_return_keys"
            ),
            methods_resolve_table: pass!(
                "type_check_methods_07_resolve_table",
                "type_check_methods_07_resolve_table"
            ),
            methods_resolve: pass!(
                "type_check_methods_03_resolve",
                "type_check_methods_03_resolve"
            ),
            visible_clear: pass!("type_check_visible_01_clear", "type_check_visible_01_clear"),
            visible_scope_blocks: pass!(
                "type_check_visible_02_scope_blocks",
                "type_check_visible_02_scope_blocks"
            ),
            visible_scatter: pass!(
                "type_check_visible_02_scatter",
                "type_check_visible_02_scatter"
            ),
            visible_decode: pass!(
                "type_check_visible_03_decode",
                "type_check_visible_03_decode"
            ),
            fn_context_clear: pass!(
                "type_check_fn_context_01_clear",
                "type_check_fn_context_01_clear"
            ),
            fn_context_mark: pass!(
                "type_check_fn_context_02_mark",
                "type_check_fn_context_02_mark"
            ),
            fn_context_local: pass!(
                "type_check_fn_context_03_local",
                "type_check_fn_context_03_local"
            ),
            fn_context_scan: pass!(
                "type_check_fn_context_04_scan_blocks",
                "type_check_fn_context_04_scan_blocks"
            ),
            fn_context_apply: pass!(
                "type_check_fn_context_05_apply",
                "type_check_fn_context_05_apply"
            ),
            loop_depth_clear: pass!(
                "type_check_loop_depth_01_clear",
                "type_check_loop_depth_01_clear"
            ),
            loop_depth_mark: pass!(
                "type_check_loop_depth_02_mark",
                "type_check_loop_depth_02_mark"
            ),
            loop_depth_local: pass!(
                "type_check_loop_depth_03_local",
                "type_check_loop_depth_03_local"
            ),
            loop_depth_scan: pass!(
                "type_check_loop_depth_04_scan_blocks",
                "type_check_loop_depth_04_scan_blocks"
            ),
            loop_depth_apply: pass!(
                "type_check_loop_depth_05_apply",
                "type_check_loop_depth_05_apply"
            ),
        })
    }
}

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    #[allow(dead_code)]
    pub(super) fn type_check_tokens_pass(device),
    label: "type_check_tokens",
    shader: "type_check_tokens_min"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_clear_pass(device),
    label: "type_check_type_instances_00_clear",
    shader: "type_check_type_instances_00_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_decl_generic_params_pass(device),
    label: "type_check_type_instances_00b_decl_generic_params",
    shader: "type_check_type_instances_00b_decl_generic_params"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_collect_pass(device),
    label: "type_check_type_instances_01_collect",
    shader: "type_check_type_instances_01_collect"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_collect_named_pass(device),
    label: "type_check_type_instances_01b_collect_named_instances",
    shader: "type_check_type_instances_01b_collect_named_instances"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_collect_aggregate_refs_pass(device),
    label: "type_check_type_instances_01c_collect_aggregate_refs",
    shader: "type_check_type_instances_01c_collect_aggregate_refs"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_collect_aggregate_details_pass(device),
    label: "type_check_type_instances_01d_collect_aggregate_details",
    shader: "type_check_type_instances_01d_collect_aggregate_details"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_collect_named_arg_refs_pass(device),
    label: "type_check_type_instances_01e_collect_named_arg_refs",
    shader: "type_check_type_instances_01e_collect_named_arg_refs"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_decl_refs_pass(device),
    label: "type_check_type_instances_01f_decl_refs",
    shader: "type_check_type_instances_01f_decl_refs"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_member_receivers_pass(device),
    label: "type_check_type_instances_03a_member_receivers",
    shader: "type_check_type_instances_03a_member_receivers"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_member_results_pass(device),
    label: "type_check_type_instances_03_member_results",
    shader: "type_check_type_instances_03_member_results"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_member_substitute_pass(device),
    label: "type_check_type_instances_03b_member_substitute",
    shader: "type_check_type_instances_03b_member_substitute"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_struct_init_fields_pass(device),
    label: "type_check_type_instances_04_struct_init_fields",
    shader: "type_check_type_instances_04_struct_init_fields"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_struct_init_clear_pass(device),
    label: "type_check_type_instances_04a_struct_init_clear",
    shader: "type_check_type_instances_04a_struct_init_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_struct_init_substitute_pass(device),
    label: "type_check_type_instances_04b_struct_init_substitute",
    shader: "type_check_type_instances_04b_struct_init_substitute"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_array_return_refs_pass(device),
    label: "type_check_type_instances_05_array_return_refs",
    shader: "type_check_type_instances_05_array_return_refs"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_array_literal_return_refs_pass(device),
    label: "type_check_type_instances_05b_array_literal_return_refs",
    shader: "type_check_type_instances_05b_array_literal_return_refs"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_enum_ctors_pass(device),
    label: "type_check_type_instances_06_enum_ctors",
    shader: "type_check_type_instances_06_enum_ctors"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_array_index_results_pass(device),
    label: "type_check_type_instances_07_array_index_results",
    shader: "type_check_type_instances_07_array_index_results"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_type_instances_validate_aggregate_access_pass(device),
    label: "type_check_type_instances_08_validate_aggregate_access",
    shader: "type_check_type_instances_08_validate_aggregate_access"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_conditions_hir_pass(device),
    label: "type_check_conditions_hir",
    shader: "type_check_conditions_hir"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_control_pass(device),
    label: "type_check_control",
    shader: "type_check_control"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_control_hir_pass(device),
    label: "type_check_control_hir",
    shader: "type_check_control_hir"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_scope_pass(device),
    label: "type_check_scope",
    shader: "type_check_scope"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_clear_pass(device),
    label: "type_check_calls_01_resolve",
    shader: "type_check_calls_01_resolve"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_language_names_clear_pass(device),
    label: "type_check_language_names_00_clear",
    shader: "type_check_language_names_00_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_language_names_mark_pass(device),
    label: "type_check_language_names_01_mark",
    shader: "type_check_language_names_01_mark"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_language_decls_materialize_pass(device),
    label: "type_check_language_decls_00_materialize",
    shader: "type_check_language_decls_00_materialize"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_return_refs_pass(device),
    label: "type_check_calls_02a_return_refs_from_hir",
    shader: "type_check_calls_02a_return_refs_from_hir"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_entrypoints_pass(device),
    label: "type_check_calls_02b_entrypoints",
    shader: "type_check_calls_02b_entrypoints"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_functions_pass(device),
    label: "type_check_calls_02_functions",
    shader: "type_check_calls_02_functions"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_param_types_pass(device),
    label: "type_check_calls_02f_params_from_hir",
    shader: "type_check_calls_02f_params_from_hir"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_intrinsics_pass(device),
    label: "type_check_calls_02c_intrinsics",
    shader: "type_check_calls_02c_intrinsics"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_clear_hir_call_args_pass(device),
    label: "type_check_calls_02d_clear_hir_call_args",
    shader: "type_check_calls_02d_clear_hir_call_args"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_pack_hir_call_args_pass(device),
    label: "type_check_calls_02e_pack_hir_call_args",
    shader: "type_check_calls_02e_pack_hir_call_args"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_resolve_pass(device),
    label: "type_check_calls_03_resolve",
    shader: "type_check_calls_03_resolve"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_calls_erase_generic_params_pass(device),
    label: "type_check_calls_04_erase_generic_params",
    shader: "type_check_calls_04_erase_generic_params"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_clear_pass(device),
    label: "type_check_methods_01_clear",
    shader: "type_check_methods_01_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_collect_pass(device),
    label: "type_check_methods_02_collect",
    shader: "type_check_methods_02_collect"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_attach_metadata_pass(device),
    label: "type_check_methods_02b_attach_metadata",
    shader: "type_check_methods_02b_attach_metadata"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_bind_self_receivers_pass(device),
    label: "type_check_methods_02c_bind_self_receivers",
    shader: "type_check_methods_02c_bind_self_receivers"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_seed_key_order_pass(device),
    label: "type_check_methods_03_seed_key_order",
    shader: "type_check_methods_03_seed_key_order"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_sort_keys_pass(device),
    label: "type_check_methods_04_sort_keys",
    shader: "type_check_methods_04_sort_keys"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_sort_keys_scatter_pass(device),
    label: "type_check_methods_04b_sort_keys_scatter",
    shader: "type_check_methods_04b_sort_keys_scatter"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_validate_keys_pass(device),
    label: "type_check_methods_05_validate_keys",
    shader: "type_check_methods_05_validate_keys"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_mark_call_keys_pass(device),
    label: "type_check_methods_06_mark_call_keys",
    shader: "type_check_methods_06_mark_call_keys"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_mark_call_return_keys_pass(device),
    label: "type_check_methods_06b_mark_call_return_keys",
    shader: "type_check_methods_06b_mark_call_return_keys"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_resolve_table_pass(device),
    label: "type_check_methods_07_resolve_table",
    shader: "type_check_methods_07_resolve_table"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_names_radix_bucket_prefix_pass(device),
    label: "type_check_names_radix_00b_bucket_prefix",
    shader: "type_check_names_radix_00b_bucket_prefix"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_names_radix_bucket_bases_pass(device),
    label: "type_check_names_radix_00c_bucket_bases",
    shader: "type_check_names_radix_00c_bucket_bases"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_methods_resolve_pass(device),
    label: "type_check_methods_03_resolve",
    shader: "type_check_methods_03_resolve"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_visible_clear_pass(device),
    label: "type_check_visible_01_clear",
    shader: "type_check_visible_01_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_visible_scope_blocks_pass(device),
    label: "type_check_visible_02_scope_blocks",
    shader: "type_check_visible_02_scope_blocks"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_visible_scatter_pass(device),
    label: "type_check_visible_02_scatter",
    shader: "type_check_visible_02_scatter"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_visible_decode_pass(device),
    label: "type_check_visible_03_decode",
    shader: "type_check_visible_03_decode"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_fn_context_clear_pass(device),
    label: "type_check_fn_context_01_clear",
    shader: "type_check_fn_context_01_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_fn_context_mark_pass(device),
    label: "type_check_fn_context_02_mark",
    shader: "type_check_fn_context_02_mark"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_fn_context_local_pass(device),
    label: "type_check_fn_context_03_local",
    shader: "type_check_fn_context_03_local"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_fn_context_scan_pass(device),
    label: "type_check_fn_context_04_scan_blocks",
    shader: "type_check_fn_context_04_scan_blocks"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn type_check_fn_context_apply_pass(device),
    label: "type_check_fn_context_05_apply",
    shader: "type_check_fn_context_05_apply"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn loop_depth_01_clear_pass(device),
    label: "type_check_loop_depth_01_clear",
    shader: "type_check_loop_depth_01_clear"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn loop_depth_02_mark_pass(device),
    label: "type_check_loop_depth_02_mark",
    shader: "type_check_loop_depth_02_mark"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn loop_depth_03_local_pass(device),
    label: "type_check_loop_depth_03_local",
    shader: "type_check_loop_depth_03_local"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn loop_depth_04_scan_pass(device),
    label: "type_check_loop_depth_04_scan_blocks",
    shader: "type_check_loop_depth_04_scan_blocks"
);

crate::gpu::passes_core::impl_cached_main_pass_getter!(
    pub(super) fn loop_depth_05_apply_pass(device),
    label: "type_check_loop_depth_05_apply",
    shader: "type_check_loop_depth_05_apply"
);
