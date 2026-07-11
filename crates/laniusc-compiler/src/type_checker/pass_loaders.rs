use super::*;

impl TypeCheckPasses {
    /// Loads every compute pass used by the resident type-check pipeline.
    pub(super) fn new(device: &wgpu::Device) -> Result<Self> {
        macro_rules! pass {
            ($label:literal, $file:literal) => {{
                crate::gpu::passes_core::make_main_pass!(device, $label, shader: $file)?
            }};
        }

        let predicates_sort_keys_small =
            if device.limits().max_compute_workgroup_storage_size >= 32 * 1024 {
                Some(pass!(
                    "type_check_predicates_01b2_sort_keys_small",
                    "type_checker/predicates/01b2_sort_keys_small"
                ))
            } else {
                None
            };
        Ok(Self {
            hir_active_dispatch_args: pass!(
                "type_check_hir_active_dispatch_args",
                "type_checker/hir_active_dispatch_args"
            ),
            semantic_features_collect: pass!(
                "type_check_semantic_features_00_collect",
                "type_checker/semantic/features/00_collect"
            ),
            semantic_features_dispatch_args: pass!(
                "type_check_semantic_features_01_dispatch_args",
                "type_checker/semantic/features/01_dispatch_args"
            ),
            names_mark_lexemes: pass!(
                "type_check_names_00_mark_lexemes",
                "type_checker/names/00_mark_lexemes"
            ),
            counted_scan_local: pass!(
                "type_check_counted_scan_00_local",
                "type_checker/counted/scan/00_local"
            ),
            counted_scan_blocks: pass!(
                "type_check_counted_scan_01_blocks",
                "type_checker/counted/scan/01_blocks"
            ),
            counted_scan_apply: pass!(
                "type_check_counted_scan_02_apply",
                "type_checker/counted/scan/02_apply"
            ),
            count_dispatch_args: pass!(
                "type_check_count_dispatch_args",
                "type_checker/count/dispatch_args"
            ),
            count_pair_max_dispatch_args: pass!(
                "type_check_count_pair_max_dispatch_args",
                "type_checker/count/pair_max_dispatch_args"
            ),
            names_scatter_lexemes: pass!(
                "type_check_names_01_scatter_lexemes",
                "type_checker/names/01_scatter_lexemes"
            ),
            names_hash_prepare: pass!(
                "type_check_names_hash_00_prepare",
                "type_checker/names/hash/00_prepare"
            ),
            names_hash_insert: pass!(
                "type_check_names_hash_01_insert",
                "type_checker/names/hash/01_insert"
            ),
            names_hash_assign_ids: pass!(
                "type_check_names_hash_02_assign_ids",
                "type_checker/names/hash/02_assign_ids"
            ),
            names_radix_dispatch_args: pass!(
                "type_check_names_radix_dispatch_args",
                "type_checker/names/radix/dispatch_args"
            ),
            names_radix_bucket_prefix: pass!(
                "type_check_names_radix_00b_bucket_prefix",
                "type_checker/names/radix/00b/bucket/prefix"
            ),
            names_radix_bucket_bases: pass!(
                "type_check_names_radix_00c_bucket_bases",
                "type_checker/names/radix/00c/bucket/bases"
            ),
            language_names_clear: pass!(
                "type_check_language_names_00_clear",
                "type_checker/language/names/00_clear"
            ),
            language_type_codes_clear: pass!(
                "type_check_language_decls_00a_clear_type_codes",
                "type_checker/language/decls/00a_clear_type_codes"
            ),
            language_decls_materialize: pass!(
                "type_check_language_decls_00_materialize",
                "type_checker/language/decls/00_materialize"
            ),
            modules_mark_records: pass!(
                "type_check_modules_00_mark_records",
                "type_checker/modules/00_mark_records"
            ),
            modules_count_record_candidates: pass!(
                "type_check_modules_00a_count_record_candidates",
                "type_checker/modules/00a_count_record_candidates"
            ),
            modules_extract_record_flag: pass!(
                "type_check_modules_00b_extract_record_flag",
                "type_checker/modules/00b_extract_record_flag"
            ),
            modules_scatter_paths: pass!(
                "type_check_modules_01_scatter_paths",
                "type_checker/modules/01_scatter_paths"
            ),
            modules_count_path_segments: pass!(
                "type_check_modules_01b_count_path_segments",
                "type_checker/modules/01b/count_path_segments"
            ),
            modules_scatter_path_segments: pass!(
                "type_check_modules_01b_scatter_path_segments",
                "type_checker/modules/01b/scatter_path_segments"
            ),
            modules_scatter_module_records: pass!(
                "type_check_modules_02_scatter_module_records",
                "type_checker/modules/02_scatter_module_records"
            ),
            modules_scatter_import_records: pass!(
                "type_check_modules_02b_scatter_import_records",
                "type_checker/modules/02b_scatter_import_records"
            ),
            modules_scatter_decl_core_records: pass!(
                "type_check_modules_02c_scatter_decl_core_records",
                "type_checker/modules/02c_scatter_decl_core_records"
            ),
            modules_clear_decl_lookup: pass!(
                "type_check_modules_02d_clear_decl_lookup",
                "type_checker/modules/02d/clear_decl_lookup"
            ),
            modules_scatter_decl_span_records: pass!(
                "type_check_modules_02d_scatter_decl_span_records",
                "type_checker/modules/02d/scatter_decl_span_records"
            ),
            modules_build_module_keys: pass!(
                "type_check_modules_02e_build_module_keys",
                "type_checker/modules/02e_build_module_keys"
            ),
            modules_sort_module_keys_small: pass!(
                "type_check_modules_02f_sort_module_keys_small",
                "type_checker/modules/02f_sort_module_keys_small"
            ),
            modules_sort_module_keys_histogram: pass!(
                "type_check_modules_03_sort_module_keys_histogram",
                "type_checker/modules/03_sort_module_keys_histogram"
            ),
            modules_sort_module_keys_scatter: pass!(
                "type_check_modules_03b_sort_module_keys_scatter",
                "type_checker/modules/03b_sort_module_keys_scatter"
            ),
            modules_validate_modules: pass!(
                "type_check_modules_04_validate_modules",
                "type_checker/modules/04_validate_modules"
            ),
            modules_resolve_imports: pass!(
                "type_check_modules_05_resolve_imports",
                "type_checker/modules/05_resolve_imports"
            ),
            modules_seed_import_edge_key_order: pass!(
                "type_check_modules_05e_seed_import_edge_key_order",
                "type_checker/modules/05e_seed_import_edge_key_order"
            ),
            modules_sort_import_edges_small: pass!(
                "type_check_modules_05e2_sort_import_edges_small",
                "type_checker/modules/05e2_sort_import_edges_small"
            ),
            modules_sort_import_edges: pass!(
                "type_check_modules_05f_sort_import_edges",
                "type_checker/modules/05f_sort_import_edges"
            ),
            modules_sort_import_edges_scatter: pass!(
                "type_check_modules_05g_sort_import_edges_scatter",
                "type_checker/modules/05g_sort_import_edges_scatter"
            ),
            modules_validate_import_cycles: pass!(
                "type_check_modules_05h_validate_import_cycles",
                "type_checker/modules/05h_validate_import_cycles"
            ),
            modules_clear_file_module_map: pass!(
                "type_check_modules_05b_clear_file_module_map",
                "type_checker/modules/05b_clear_file_module_map"
            ),
            modules_build_file_module_map: pass!(
                "type_check_modules_05c_build_file_module_map",
                "type_checker/modules/05c_build_file_module_map"
            ),
            modules_attach_record_modules: pass!(
                "type_check_modules_05d_attach_record_modules",
                "type_checker/modules/05d_attach_record_modules"
            ),
            modules_seed_decl_key_order: pass!(
                "type_check_modules_06a_seed_decl_key_order",
                "type_checker/modules/06a_seed_decl_key_order"
            ),
            modules_sort_decl_keys_small: pass!(
                "type_check_modules_06a2_sort_decl_keys_small",
                "type_checker/modules/06a2_sort_decl_keys_small"
            ),
            modules_sort_decl_keys: pass!(
                "type_check_modules_06_sort_decl_keys",
                "type_checker/modules/06_sort_decl_keys"
            ),
            modules_sort_decl_keys_scatter: pass!(
                "type_check_modules_06b_sort_decl_keys_scatter",
                "type_checker/modules/06b_sort_decl_keys_scatter"
            ),
            modules_validate_decls: pass!(
                "type_check_modules_07_validate_decls",
                "type_checker/modules/07_validate_decls"
            ),
            modules_mark_decl_namespace_keys: pass!(
                "type_check_modules_08_mark_decl_namespace_keys",
                "type_checker/modules/08_mark_decl_namespace_keys"
            ),
            modules_scatter_decl_namespace_keys: pass!(
                "type_check_modules_08b_scatter_decl_namespace_keys",
                "type_checker/modules/08b_scatter_decl_namespace_keys"
            ),
            modules_mark_public_decl_keys: pass!(
                "type_check_modules_08c_mark_public_decl_keys",
                "type_checker/modules/08c_mark_public_decl_keys"
            ),
            modules_count_import_visibility: pass!(
                "type_check_modules_09_count_import_visibility",
                "type_checker/modules/09_count_import_visibility"
            ),
            modules_scatter_import_visibility: pass!(
                "type_check_modules_09b_scatter_import_visibility",
                "type_checker/modules/09b_scatter_import_visibility"
            ),
            modules_sort_import_visible_keys_small: pass!(
                "type_check_modules_09b2_sort_import_visible_keys_small",
                "type_checker/modules/09b2_sort_import_visible_keys_small"
            ),
            modules_sort_import_visible_keys: pass!(
                "type_check_modules_09c_sort_import_visible_keys",
                "type_checker/modules/09c_sort_import_visible_keys"
            ),
            modules_sort_import_visible_keys_scatter: pass!(
                "type_check_modules_09d_sort_import_visible_keys_scatter",
                "type_checker/modules/09d_sort_import_visible_keys_scatter"
            ),
            modules_build_import_visible_key_tables: pass!(
                "type_check_modules_09e_build_import_visible_key_tables",
                "type_checker/modules/09e_build_import_visible_key_tables"
            ),
            modules_validate_import_visible_keys: pass!(
                "type_check_modules_09f_validate_import_visible_keys",
                "type_checker/modules/09f_validate_import_visible_keys"
            ),
            modules_resolve_local_paths: pass!(
                "type_check_modules_10_resolve_local_paths",
                "type_checker/modules/10_resolve_local_paths"
            ),
            modules_resolve_imported_paths: pass!(
                "type_check_modules_10b_resolve_imported_paths",
                "type_checker/modules/10b_resolve_imported_paths"
            ),
            modules_resolve_qualified_paths: pass!(
                "type_check_modules_10c_resolve_qualified_paths",
                "type_checker/modules/10c_resolve_qualified_paths"
            ),
            modules_clear_type_path_types: pass!(
                "type_check_modules_10d_clear_type_path_types",
                "type_checker/modules/10d_clear_type_path_types"
            ),
            modules_project_type_paths: pass!(
                "type_check_modules_10e_project_type_paths",
                "type_checker/modules/10e_project_type_paths"
            ),
            modules_validate_type_paths: pass!(
                "type_check_modules_10e3_validate_type_paths",
                "type_checker/modules/10e3_validate_type_paths"
            ),
            modules_project_type_aliases: pass!(
                "type_check_modules_10e2_project_type_aliases",
                "type_checker/modules/10e2_project_type_aliases"
            ),
            modules_project_type_instances: pass!(
                "type_check_modules_10k_project_type_instances",
                "type_checker/modules/10k_project_type_instances"
            ),
            modules_mark_value_call_paths: pass!(
                "type_check_modules_10f_mark_value_call_paths",
                "type_checker/modules/10f_mark_value_call_paths"
            ),
            modules_project_value_paths: pass!(
                "type_check_modules_10g_project_value_paths",
                "type_checker/modules/10g_project_value_paths"
            ),
            modules_consume_value_calls: pass!(
                "type_check_modules_10h_consume_value_calls",
                "type_checker/modules/10h_consume_value_calls"
            ),
            modules_mirror_value_call_leaf: pass!(
                "type_check_modules_10h2_mirror_value_call_leaf",
                "type_checker/modules/10h2_mirror_value_call_leaf"
            ),
            modules_consume_value_consts: pass!(
                "type_check_modules_10i_consume_value_consts",
                "type_checker/modules/10i_consume_value_consts"
            ),
            modules_consume_value_enum_units: pass!(
                "type_check_modules_10j_consume_value_enum_units",
                "type_checker/modules/10j_consume_value_enum_units"
            ),
            modules_consume_value_enum_calls: pass!(
                "type_check_modules_10l_consume_value_enum_calls",
                "type_checker/modules/10l_consume_value_enum_calls"
            ),
            modules_validate_value_enum_call_payloads: pass!(
                "type_check_modules_10l2_validate_value_enum_call_payloads",
                "type_checker/modules/10l2_validate_value_enum_call_payloads"
            ),
            modules_finalize_value_enum_calls: pass!(
                "type_check_modules_10l3_finalize_value_enum_calls",
                "type_checker/modules/10l3_finalize_value_enum_calls"
            ),
            modules_bind_match_patterns: pass!(
                "type_check_modules_10m_bind_match_patterns",
                "type_checker/modules/10m_bind_match_patterns"
            ),
            modules_type_match_payloads: pass!(
                "type_check_modules_10m2_type_match_payloads",
                "type_checker/modules/10m2_type_match_payloads"
            ),
            modules_type_match_exprs: pass!(
                "type_check_modules_10n_type_match_exprs",
                "type_checker/modules/10n_type_match_exprs"
            ),
            type_instances_clear: pass!(
                "type_check_type_instances_00_clear",
                "type_checker/type/instances/00_clear"
            ),
            type_instances_mark_generic_param_records: pass!(
                "type_check_type_instances_00a_mark_generic_param_records",
                "type_checker/type/instances/00a_mark_generic_param_records"
            ),
            type_instances_propagate_generic_decl_owner: pass!(
                "type_check_type_instances_00a1_propagate_generic_decl_owner",
                "type_checker/type/instances/00a1_propagate_generic_decl_owner"
            ),
            type_instances_decl_generic_params: pass!(
                "type_check_type_instances_00b_decl_generic_params",
                "type_checker/type/instances/00b_decl_generic_params"
            ),
            type_instances_sort_generic_params_small: pass!(
                "type_check_type_instances_00b2_sort_generic_params_small",
                "type_checker/type/instances/00b2_sort_generic_params_small"
            ),
            type_instances_sort_generic_param_keys: pass!(
                "type_check_type_instances_00c_sort_generic_param_keys",
                "type_checker/type/instances/00c_sort_generic_param_keys"
            ),
            type_instances_sort_generic_param_keys_scatter: pass!(
                "type_check_type_instances_00d_sort_generic_param_keys_scatter",
                "type_checker/type/instances/00d_sort_generic_param_keys_scatter"
            ),
            type_instances_sort_generic_param_slots: pass!(
                "type_check_type_instances_00c2_sort_generic_param_slots",
                "type_checker/type/instances/00c2_sort_generic_param_slots"
            ),
            type_instances_sort_generic_param_slots_scatter: pass!(
                "type_check_type_instances_00d2_sort_generic_param_slots_scatter",
                "type_checker/type/instances/00d2_sort_generic_param_slots_scatter"
            ),
            type_instances_generic_param_use_slots: pass!(
                "type_check_type_instances_00e_generic_param_use_slots",
                "type_checker/type/instances/00e_generic_param_use_slots"
            ),
            type_instances_seed_struct_field_keys: pass!(
                "type_check_type_instances_02_seed_struct_field_keys",
                "type_checker/type/instances/02_seed_struct_field_keys"
            ),
            type_instances_sort_struct_field_keys: pass!(
                "type_check_type_instances_02b_sort_struct_field_keys",
                "type_checker/type/instances/02b_sort_struct_field_keys"
            ),
            type_instances_sort_struct_field_keys_scatter: pass!(
                "type_check_type_instances_02c_sort_struct_field_keys_scatter",
                "type_checker/type/instances/02c_sort_struct_field_keys_scatter"
            ),
            type_instances_collect: pass!(
                "type_check_type_instances_01_collect",
                "type_checker/type/instances/01_collect"
            ),
            type_instances_collect_named: pass!(
                "type_check_type_instances_01b_collect_named_instances",
                "type_checker/type/instances/01b_collect_named_instances"
            ),
            type_instances_collect_aggregate_refs: pass!(
                "type_check_type_instances_01c_collect_aggregate_refs",
                "type_checker/type/instances/01c_collect_aggregate_refs"
            ),
            type_instances_collect_aggregate_details: pass!(
                "type_check_type_instances_01d_collect_aggregate_details",
                "type_checker/type/instances/01d_collect_aggregate_details"
            ),
            type_instances_collect_named_arg_refs: pass!(
                "type_check_type_instances_01e_collect_named_arg_refs",
                "type_checker/type/instances/01e_collect_named_arg_refs"
            ),
            type_instances_hash_arg_rows: pass!(
                "type_check_type_instances_01g_hash_arg_rows",
                "type_checker/type/instances/01g_hash_arg_rows"
            ),
            type_instances_decl_refs: pass!(
                "type_check_type_instances_01f_decl_refs",
                "type_checker/type/instances/01f_decl_refs"
            ),
            type_instances_member_receivers: pass!(
                "type_check_type_instances_03a_member_receivers",
                "type_checker/type/instances/03a_member_receivers"
            ),
            type_instances_member_results: pass!(
                "type_check_type_instances_03_member_results",
                "type_checker/type/instances/03_member_results"
            ),
            type_instances_member_substitute: pass!(
                "type_check_type_instances_03b_member_substitute",
                "type_checker/type/instances/03b_member_substitute"
            ),
            type_instances_struct_init_clear: pass!(
                "type_check_type_instances_04a_struct_init_clear",
                "type_checker/type/instances/04a_struct_init_clear"
            ),
            type_instances_struct_init_contexts: pass!(
                "type_check_type_instances_04a2_struct_init_contexts",
                "type_checker/type/instances/04a2_struct_init_contexts"
            ),
            type_instances_struct_init_fields: pass!(
                "type_check_type_instances_04_struct_init_fields",
                "type_checker/type/instances/04_struct_init_fields"
            ),
            type_instances_struct_init_substitute: pass!(
                "type_check_type_instances_04b_struct_init_substitute",
                "type_checker/type/instances/04b_struct_init_substitute"
            ),
            type_instances_array_return_refs: pass!(
                "type_check_type_instances_05_array_return_refs",
                "type_checker/type/instances/05_array_return_refs"
            ),
            type_instances_array_literal_return_refs: pass!(
                "type_check_type_instances_05b_array_literal_return_refs",
                "type_checker/type/instances/05b_array_literal_return_refs"
            ),
            type_instances_array_index_results: pass!(
                "type_check_type_instances_07_array_index_results",
                "type_checker/type/instances/07_array_index_results"
            ),
            type_instances_validate_aggregate_access: pass!(
                "type_check_type_instances_08_validate_aggregate_access",
                "type_checker/type/instances/08_validate_aggregate_access"
            ),
            predicates_clear_syntax_tokens: pass!(
                "type_check_predicates_00a_clear_syntax_tokens",
                "type_checker/predicates/00a_clear_syntax_tokens"
            ),
            predicates_clear_bound_arg_facts: pass!(
                "type_check_predicates_00_clear_bound_arg_facts",
                "type_checker/predicates/00_clear_bound_arg_facts"
            ),
            predicates_collect_bound_arg_facts: pass!(
                "type_check_predicates_00b_collect_bound_arg_facts",
                "type_checker/predicates/00b_collect_bound_arg_facts"
            ),
            predicates_collect_method_contracts: pass!(
                "type_check_predicates_00c_collect_method_contracts",
                "type_checker/predicates/00c_collect_method_contracts"
            ),
            predicates_collect: pass!(
                "type_check_predicates_01_collect",
                "type_checker/predicates/01_collect"
            ),
            predicates_collect_impls: pass!(
                "type_check_predicates_01_collect_impls",
                "type_checker/predicates/01_collect_impls"
            ),
            predicates_collect_methods: pass!(
                "type_check_predicates_01_collect_methods",
                "type_checker/predicates/01_collect_methods"
            ),
            predicates_seed_key_order: pass!(
                "type_check_predicates_01b_seed_key_order",
                "type_checker/predicates/01b_seed_key_order"
            ),
            predicates_sort_keys_small,
            predicates_sort_keys: pass!(
                "type_check_predicates_01c_sort_keys",
                "type_checker/predicates/01c_sort_keys"
            ),
            predicates_sort_keys_scatter: pass!(
                "type_check_predicates_01d_sort_keys_scatter",
                "type_checker/predicates/01d_sort_keys_scatter"
            ),
            predicates_build_method_owner_ranges: pass!(
                "type_check_predicates_01e_build_method_owner_ranges",
                "type_checker/predicates/01e_build_method_owner_ranges"
            ),
            predicates_emit_method_validation_rows: pass!(
                "type_check_predicates_01f_emit_method_validation_rows",
                "type_checker/predicates/01f_emit_method_validation_rows"
            ),
            predicates_reduce_method_validation_errors: pass!(
                "type_check_predicates_01g_reduce_method_validation_errors",
                "type_checker/predicates/01g_reduce_method_validation_errors"
            ),
            predicates_apply_method_validation_errors: pass!(
                "type_check_predicates_01h_apply_method_validation_errors",
                "type_checker/predicates/01h_apply_method_validation_errors"
            ),
            predicates_obligations: pass!(
                "type_check_predicates_02_obligations",
                "type_checker/predicates/02_obligations"
            ),
            returns_clear: pass!(
                "type_check_returns_00_clear",
                "type_checker/returns/00_clear"
            ),
            returns_mark: pass!("type_check_returns_01_mark", "type_checker/returns/01_mark"),
            returns_mark_if: pass!(
                "type_check_returns_02_mark_if",
                "type_checker/returns/02_mark_if"
            ),
            returns_validate: pass!(
                "type_check_returns_03_validate",
                "type_checker/returns/03_validate"
            ),
            conditions_hir: pass!("type_check_conditions_hir", "type_checker/conditions_hir"),
            conditions_aggregate_args: pass!(
                "type_check_conditions_aggregate_args",
                "type_checker/conditions/aggregate_args"
            ),
            control_hir: pass!("type_check_control_hir", "type_checker/control/hir"),
            scope_hir: pass!("type_check_scope_hir", "type_checker/scope/hir"),
            calls_clear: pass!(
                "type_check_calls_01_resolve",
                "type_checker/calls/01_resolve"
            ),
            calls_return_refs: pass!(
                "type_check_calls_02a_return_refs_from_hir",
                "type_checker/calls/02a_return_refs_from_hir"
            ),
            calls_entrypoints: pass!(
                "type_check_calls_02b_entrypoints",
                "type_checker/calls/02b_entrypoints"
            ),
            calls_functions: pass!(
                "type_check_calls_02_functions",
                "type_checker/calls/02_functions"
            ),
            calls_param_types: pass!(
                "type_check_calls_02f_params_from_hir",
                "type_checker/calls/02f_params_from_hir"
            ),
            calls_intrinsics: pass!(
                "type_check_calls_02c_intrinsics",
                "type_checker/calls/02c_intrinsics"
            ),
            calls_clear_hir_call_args: pass!(
                "type_check_calls_02d_clear_hir_call_args",
                "type_checker/calls/02d_clear_hir_call_args"
            ),
            calls_pack_hir_call_args: pass!(
                "type_check_calls_02e_pack_hir_call_args",
                "type_checker/calls/02e_pack_hir_call_args"
            ),
            calls_mark_compact_hir_call_args: pass!(
                "type_check_calls_02g_mark_compact_hir_call_args",
                "type_checker/calls/02g_mark_compact_hir_call_args"
            ),
            calls_scatter_compact_hir_call_args: pass!(
                "type_check_calls_02h_scatter_compact_hir_call_args",
                "type_checker/calls/02h_scatter_compact_hir_call_args"
            ),
            calls_scatter_compact_hir_params: pass!(
                "type_check_calls_02i_scatter_compact_hir_params",
                "type_checker/calls/02i_scatter_compact_hir_params"
            ),
            calls_resolve: pass!(
                "type_check_calls_03_resolve",
                "type_checker/calls/03_resolve"
            ),
            calls_match_arg_params_init: pass!(
                "type_check_calls_03a0_match_arg_params_init",
                "type_checker/calls/03a0_match_arg_params_init"
            ),
            calls_match_arg_params_copy: pass!(
                "type_check_calls_03a0_match_arg_params_copy",
                "type_checker/calls/03a0_match_arg_params_copy"
            ),
            calls_match_arg_params_step: pass!(
                "type_check_calls_03a0_match_arg_params_step",
                "type_checker/calls/03a0_match_arg_params_step"
            ),
            calls_collect_row_args: pass!(
                "type_check_calls_03a_collect_row_args",
                "type_checker/calls/03a_collect_row_args"
            ),
            calls_emit_generic_claims: pass!(
                "type_check_calls_03a1_emit_generic_claims",
                "type_checker/calls/03a1_emit_generic_claims"
            ),
            calls_sort_generic_claims: pass!(
                "type_check_calls_03a2_sort_generic_claims",
                "type_checker/calls/03a2_sort_generic_claims"
            ),
            calls_sort_generic_claims_scatter: pass!(
                "type_check_calls_03a3_sort_generic_claims_scatter",
                "type_checker/calls/03a3_sort_generic_claims_scatter"
            ),
            calls_validate_generic_claims: pass!(
                "type_check_calls_03a4_validate_generic_claims",
                "type_checker/calls/03a4_validate_generic_claims"
            ),
            calls_mark_required_generics: pass!(
                "type_check_calls_03a6_mark_required_generics",
                "type_checker/calls/03a6_mark_required_generics"
            ),
            calls_validate_required_generics: pass!(
                "type_check_calls_03a7_validate_required_generics",
                "type_checker/calls/03a7_validate_required_generics"
            ),
            calls_validate_const_claims: pass!(
                "type_check_calls_03a5_validate_const_claims",
                "type_checker/calls/03a5_validate_const_claims"
            ),
            calls_apply_row_args: pass!(
                "type_check_calls_03a_apply_row_args",
                "type_checker/calls/03a_apply_row_args"
            ),
            calls_infer_array_generics: pass!(
                "type_check_calls_03b_infer_array_generics",
                "type_checker/calls/03b_infer_array_generics"
            ),
            calls_validate_array_results: pass!(
                "type_check_calls_03c_validate_array_results",
                "type_checker/calls/03c_validate_array_results"
            ),
            calls_mark_array_args: pass!(
                "type_check_calls_03d_mark_array_args",
                "type_checker/calls/03d_mark_array_args"
            ),
            calls_erase_generic_params: pass!(
                "type_check_calls_04_erase_generic_params",
                "type_checker/calls/04_erase_generic_params"
            ),
            methods_clear: pass!(
                "type_check_methods_01_clear",
                "type_checker/methods/01_clear"
            ),
            methods_collect: pass!(
                "type_check_methods_02_collect",
                "type_checker/methods/02_collect"
            ),
            methods_attach_metadata: pass!(
                "type_check_methods_02b_attach_metadata",
                "type_checker/methods/02b_attach_metadata"
            ),
            methods_bind_self_receivers: pass!(
                "type_check_methods_02c_bind_self_receivers",
                "type_checker/methods/02c_bind_self_receivers"
            ),
            methods_seed_key_order: pass!(
                "type_check_methods_03_seed_key_order",
                "type_checker/methods/03/seed_key_order"
            ),
            methods_sort_keys_small: pass!(
                "type_check_methods_03b_sort_key_order_small",
                "type_checker/methods/03b_sort_key_order_small"
            ),
            methods_sort_keys: pass!(
                "type_check_methods_04_sort_keys",
                "type_checker/methods/04_sort_keys"
            ),
            methods_sort_keys_scatter: pass!(
                "type_check_methods_04b_sort_keys_scatter",
                "type_checker/methods/04b_sort_keys_scatter"
            ),
            methods_validate_keys: pass!(
                "type_check_methods_05_validate_keys",
                "type_checker/methods/05_validate_keys"
            ),
            methods_mark_call_keys: pass!(
                "type_check_methods_06_mark_call_keys",
                "type_checker/methods/06_mark_call_keys"
            ),
            methods_mark_call_return_keys: pass!(
                "type_check_methods_06b_mark_call_return_keys",
                "type_checker/methods/06b_mark_call_return_keys"
            ),
            methods_resolve_table: pass!(
                "type_check_methods_07_resolve_table",
                "type_checker/methods/07_resolve_table"
            ),
            methods_resolve: pass!(
                "type_check_methods_03_resolve",
                "type_checker/methods/03/resolve"
            ),
            visible_clear_resident: pass!(
                "type_check_visible_01_clear_resident",
                "type_checker/visible/01/clear/resident"
            ),
            visible_mark_hir_decl_names: pass!(
                "type_check_visible_03b_mark_hir_decl_names",
                "type_checker/visible/03b_mark_hir_decl_names"
            ),
            visible_scatter_hir_decl_records: pass!(
                "type_check_visible_03c_scatter_hir_decls",
                "type_checker/visible/03c_scatter_hir_decls"
            ),
            visible_seed_hir_decl_order: pass!(
                "type_check_visible_03d_seed_hir_decl_order",
                "type_checker/visible/03d_seed_hir_decl_order"
            ),
            visible_sort_hir_decl_keys_small: pass!(
                "type_check_visible_03d2_sort_hir_decl_keys_small",
                "type_checker/visible/03d2_sort_hir_decl_keys_small"
            ),
            visible_sort_hir_decl_keys: pass!(
                "type_check_visible_03e_sort_hir_decl_keys",
                "type_checker/visible/03e_sort_hir_decl_keys"
            ),
            visible_sort_hir_decl_keys_scatter: pass!(
                "type_check_visible_03f_sort_hir_decl_keys_scatter",
                "type_checker/visible/03f_sort_hir_decl_keys_scatter"
            ),
            visible_build_hir_decl_scope_leaves: pass!(
                "type_check_visible_03g_build_hir_decl_scope_leaves",
                "type_checker/visible/03g_build_hir_decl_scope_leaves"
            ),
            visible_build_hir_decl_scope_tree: pass!(
                "type_check_visible_03h_build_hir_decl_scope_tree",
                "type_checker/visible/03h_build_hir_decl_scope_tree"
            ),
            visible_hir_names: pass!(
                "type_check_visible_04_hir_names",
                "type_checker/visible/04_hir_names"
            ),
            fn_context_clear: pass!(
                "type_check_fn_context_01_clear",
                "type_checker/fn/context/01_clear"
            ),
            fn_context_mark: pass!(
                "type_check_fn_context_02_mark",
                "type_checker/fn/context/02_mark"
            ),
            fn_context_local: pass!(
                "type_check_fn_context_03_local",
                "type_checker/fn/context/03_local"
            ),
            fn_context_scan: pass!(
                "type_check_fn_context_04_scan_blocks",
                "type_checker/fn/context/04_scan_blocks"
            ),
            fn_context_apply: pass!(
                "type_check_fn_context_05_apply",
                "type_checker/fn/context/05_apply"
            ),
            loop_depth_clear: pass!(
                "type_check_loop_depth_01_clear",
                "type_checker/loop/depth/01_clear"
            ),
            loop_depth_mark: pass!(
                "type_check_loop_depth_02_mark",
                "type_checker/loop/depth/02_mark"
            ),
            loop_depth_local: pass!(
                "type_check_loop_depth_03_local",
                "type_checker/loop/depth/03_local"
            ),
            loop_depth_scan: pass!(
                "type_check_loop_depth_04_scan_blocks",
                "type_checker/loop/depth/04_scan_blocks"
            ),
            loop_depth_apply: pass!(
                "type_check_loop_depth_05_apply",
                "type_checker/loop/depth/05_apply"
            ),
        })
    }
}
