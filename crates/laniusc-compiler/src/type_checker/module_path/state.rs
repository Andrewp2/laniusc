use super::{
    super::*,
    buffers::Buffers,
    dependency_visibility::DependencyVisibilityState,
    path_sequences::PathPrefixRound,
    projection::TypeAliasProjection,
};

/// All bind groups recorded by the module/path pass family.
///
/// This carrier preserves creation-time ordering and keeps the resident state
/// independent from individual constructor helpers.
pub(in crate::type_checker) struct BindGroups {
    pub(in crate::type_checker) mark_records: ComputeOperation,
    pub(in crate::type_checker) scatter_paths: ComputeOperation,
    pub(in crate::type_checker) count_path_segments: ComputeOperation,
    pub(in crate::type_checker) scatter_path_segments: ComputeOperation,
    pub(in crate::type_checker) clear_path_state: ComputeOperation,
    pub(in crate::type_checker) path_prefix_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) path_prefix_initial_table_clear: ComputeOperation,
    pub(in crate::type_checker) path_prefix_rounds: Vec<PathPrefixRound>,
    pub(in crate::type_checker) path_prefix_finalize: ComputeOperation,
    pub(in crate::type_checker) module_records: CompactionOperation,
    pub(in crate::type_checker) import_records: CompactionOperation,
    pub(in crate::type_checker) decl_records: CompactionOperation,
    pub(in crate::type_checker) append_variant_decl_count: ComputeOperation,
    pub(in crate::type_checker) scatter_variant_decl_records: ComputeOperation,
    pub(in crate::type_checker) clear_decl_lookup: ComputeOperation,
    pub(in crate::type_checker) scatter_decl_span_records: ComputeOperation,
    pub(in crate::type_checker) clear_module_lookup: ComputeOperation,
    pub(in crate::type_checker) build_module_keys: ComputeOperation,
    pub(in crate::type_checker) module_dispatch: ComputeOperation,
    pub(in crate::type_checker) validate_modules: ComputeOperation,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<ComputeOperation>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<ComputeOperation>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<ComputeOperation>,
    pub(in crate::type_checker) clear_dependency_module_lookup_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) build_dependency_module_lookup_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) resolve_dependency_imports_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) resolve_imports: ComputeOperation,
    pub(in crate::type_checker) clear_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) build_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) validate_import_cycles: ComputeOperation,
    pub(in crate::type_checker) clear_file_module_map: ComputeOperation,
    pub(in crate::type_checker) build_file_module_map: ComputeOperation,
    pub(in crate::type_checker) attach_record_modules: ComputeOperation,
    pub(in crate::type_checker) import_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) decl_key_radix_dispatch: ComputeOperation,
    pub(in crate::type_checker) sort_decl_keys: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_decls: ComputeOperation,
    pub(in crate::type_checker) mark_decl_namespace_keys: ComputeOperation,
    pub(in crate::type_checker) decl_namespace_scan: PrefixScanPairOperation,
    pub(in crate::type_checker) scatter_decl_namespace_keys: ComputeOperation,
    pub(in crate::type_checker) decl_lookup: ExactLookupOperation,
    pub(in crate::type_checker) validate_decl_duplicates: ComputeOperation,
    pub(in crate::type_checker) mark_public_decl_keys: ComputeOperation,
    pub(in crate::type_checker) decl_public_scan: PrefixScanPairOperation,
    pub(in crate::type_checker) clear_interface_public_decls: ComputeOperation,
    pub(in crate::type_checker) map_interface_public_decls: ComputeOperation,
    pub(in crate::type_checker) count_import_visibility: ComputeOperation,
    pub(in crate::type_checker) import_visible_scan: PrefixScanPairOperation,
    pub(in crate::type_checker) scatter_import_visible_type: ComputeOperation,
    pub(in crate::type_checker) scatter_import_visible_value: ComputeOperation,
    pub(in crate::type_checker) clear_import_visible_type_lookup: ComputeOperation,
    pub(in crate::type_checker) clear_import_visible_value_lookup: ComputeOperation,
    pub(in crate::type_checker) build_import_visible_type_key_table: ComputeOperation,
    pub(in crate::type_checker) build_import_visible_value_key_table: ComputeOperation,
    pub(in crate::type_checker) import_visible_validate_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) initialize_import_visible_keys: ComputeOperation,
    pub(in crate::type_checker) validate_import_visible_keys: ComputeOperation,
    pub(in crate::type_checker) path_dispatch_args: ComputeOperation,
    pub(in crate::type_checker) resolve_local_type_paths: ComputeOperation,
    pub(in crate::type_checker) resolve_local_value_paths: ComputeOperation,
    pub(in crate::type_checker) resolve_imported_type_paths: ComputeOperation,
    pub(in crate::type_checker) resolve_imported_value_paths: ComputeOperation,
    pub(in crate::type_checker) resolve_qualified_type_paths: ComputeOperation,
    pub(in crate::type_checker) resolve_qualified_value_paths: ComputeOperation,
    pub(in crate::type_checker) clear_type_path_types: ComputeOperation,
    pub(in crate::type_checker) project_type_paths: ComputeOperation,
    pub(in crate::type_checker) project_type_paths_after_aliases: ComputeInvocation,
    pub(in crate::type_checker) project_type_paths_after_projected_aliases: ComputeInvocation,
    pub(in crate::type_checker) project_type_paths_after_alias_equivalence: ComputeInvocation,
    pub(in crate::type_checker) validate_type_paths: ComputeOperation,
    pub(in crate::type_checker) type_aliases: Option<Box<TypeAliasProjection>>,
    pub(in crate::type_checker) project_type_instances: ComputeOperation,
    pub(in crate::type_checker) mark_value_call_paths: ComputeOperation,
    pub(in crate::type_checker) project_value_paths: ComputeOperation,
    pub(in crate::type_checker) consume_value_calls: ComputeOperation,
    pub(in crate::type_checker) consume_value_calls_after_methods: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf: ComputeOperation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_row_args: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_methods: ComputeInvocation,
    pub(in crate::type_checker) mirror_value_call_leaf_after_method_row_args: ComputeInvocation,
    pub(in crate::type_checker) consume_value_consts: ComputeOperation,
    pub(in crate::type_checker) consume_value_enum_units: ComputeOperation,
    pub(in crate::type_checker) consume_value_enum_calls: ComputeOperation,
    pub(in crate::type_checker) validate_value_enum_call_payloads: ComputeOperation,
    pub(in crate::type_checker) finalize_value_enum_calls: ComputeOperation,
    pub(in crate::type_checker) bind_match_patterns: ComputeOperation,
    pub(in crate::type_checker) type_match_payloads: ComputeOperation,
    pub(in crate::type_checker) type_match_exprs: ComputeOperation,
}

/// Resident module/path relation state.
///
/// The state owns module/import/declaration/path tables, lookup scratch, radix
/// scratch, projection outputs, retained uniforms, and the bind groups that
/// keep those buffers alive across recorded checks.
pub(in crate::type_checker) struct State {
    pub(in crate::type_checker) resources: Buffers,
    pub(in crate::type_checker) dependency_interfaces: Option<GpuDependencyInterfaceState>,
    pub(in crate::type_checker) dependency_visibility: Option<Box<DependencyVisibilityState>>,
    pub(in crate::type_checker) _extract_module_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) _extract_import_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) _extract_decl_record_flag_params:
        LaniusBuffer<RecordFamilyFlagParams>,
    pub(in crate::type_checker) _path_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _path_prefix_dispatch_params:
        LaniusBuffer<PathPrefixDispatchParams>,
    pub(in crate::type_checker) _import_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _import_visible_validate_dispatch_params:
        LaniusBuffer<CountPairMaxDispatchParams>,
    pub(in crate::type_checker) _module_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _module_lookup_params: LaniusBuffer<ModuleLookupParams>,
    pub(in crate::type_checker) _import_resolve_params: LaniusBuffer<ImportResolveParams>,
    pub(in crate::type_checker) _qualified_path_resolve_params:
        [LaniusBuffer<QualifiedPathResolveParams>; 2],
    pub(in crate::type_checker) _decl_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _retained_params: Vec<LaniusBuffer<ModuleKeyRadixParams>>,
    pub(in crate::type_checker) bind_groups: BindGroups,
}

impl std::ops::Deref for State {
    type Target = Buffers;

    fn deref(&self) -> &Self::Target {
        &self.resources
    }
}
