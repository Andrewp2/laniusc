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
    pub(in crate::type_checker) scatter_paths: wgpu::BindGroup,
    pub(in crate::type_checker) count_path_segments: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_path_segments: wgpu::BindGroup,
    pub(in crate::type_checker) clear_path_state: wgpu::BindGroup,
    pub(in crate::type_checker) path_prefix_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) path_prefix_rounds: Vec<PathPrefixRound>,
    pub(in crate::type_checker) path_prefix_finalize: wgpu::BindGroup,
    pub(in crate::type_checker) module_records: CompactionOperation,
    pub(in crate::type_checker) import_records: CompactionOperation,
    pub(in crate::type_checker) decl_records: CompactionOperation,
    pub(in crate::type_checker) append_variant_decl_count: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_variant_decl_records: wgpu::BindGroup,
    pub(in crate::type_checker) clear_decl_lookup: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_decl_span_records: wgpu::BindGroup,
    pub(in crate::type_checker) build_module_keys: wgpu::BindGroup,
    pub(in crate::type_checker) module_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_module_keys: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_modules: wgpu::BindGroup,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) resolve_imports: ComputeOperation,
    pub(in crate::type_checker) seed_import_edge_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) import_edge_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_import_edges: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_import_cycles: wgpu::BindGroup,
    pub(in crate::type_checker) clear_file_module_map: ComputeOperation,
    pub(in crate::type_checker) build_file_module_map: ComputeOperation,
    pub(in crate::type_checker) attach_record_modules: ComputeOperation,
    pub(in crate::type_checker) import_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) seed_decl_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) decl_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_decl_keys: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_decls: wgpu::BindGroup,
    pub(in crate::type_checker) mark_decl_namespace_keys: ComputeOperation,
    pub(in crate::type_checker) decl_type_key_scan: PrefixScanOperation,
    pub(in crate::type_checker) decl_value_key_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_decl_namespace_keys: ComputeOperation,
    pub(in crate::type_checker) mark_public_decl_keys: ComputeOperation,
    pub(in crate::type_checker) decl_type_public_scan: PrefixScanOperation,
    pub(in crate::type_checker) decl_value_public_scan: PrefixScanOperation,
    pub(in crate::type_checker) clear_interface_public_decls: wgpu::BindGroup,
    pub(in crate::type_checker) map_interface_public_decls: wgpu::BindGroup,
    pub(in crate::type_checker) count_import_visibility: ComputeOperation,
    pub(in crate::type_checker) import_visible_type_scan: PrefixScanOperation,
    pub(in crate::type_checker) import_visible_value_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_import_visible_type: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_import_visible_value: wgpu::BindGroup,
    pub(in crate::type_checker) import_visible_type_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_import_visible_type_keys:
        RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) import_visible_value_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_import_visible_value_keys:
        RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) build_import_visible_type_key_table: wgpu::BindGroup,
    pub(in crate::type_checker) build_import_visible_value_key_table: wgpu::BindGroup,
    pub(in crate::type_checker) import_visible_validate_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) initialize_import_visible_keys: wgpu::BindGroup,
    pub(in crate::type_checker) validate_import_visible_keys: wgpu::BindGroup,
    pub(in crate::type_checker) path_dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_local_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_local_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_imported_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_imported_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_qualified_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_qualified_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) clear_type_path_types: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) validate_type_paths: wgpu::BindGroup,
    pub(in crate::type_checker) type_aliases: Box<TypeAliasProjection>,
    pub(in crate::type_checker) project_type_instances: wgpu::BindGroup,
    pub(in crate::type_checker) mark_value_call_paths: wgpu::BindGroup,
    pub(in crate::type_checker) project_value_paths: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_calls: wgpu::BindGroup,
    pub(in crate::type_checker) mirror_value_call_leaf: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_consts: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_units: wgpu::BindGroup,
    pub(in crate::type_checker) consume_value_enum_calls: wgpu::BindGroup,
    pub(in crate::type_checker) validate_value_enum_call_payloads: wgpu::BindGroup,
    pub(in crate::type_checker) finalize_value_enum_calls: wgpu::BindGroup,
    pub(in crate::type_checker) bind_match_patterns: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_payloads: wgpu::BindGroup,
    pub(in crate::type_checker) type_match_exprs: wgpu::BindGroup,
}

/// Resident module/path relation state.
///
/// The state owns module/import/declaration/path tables, lookup scratch, radix
/// scratch, projection outputs, retained uniforms, and the bind groups that
/// keep those buffers alive across recorded checks.
pub(in crate::type_checker) struct State {
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) parser_hir_n_blocks: u32,
    pub(in crate::type_checker) module_n_blocks: u32,
    pub(in crate::type_checker) token_capacity: u32,
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
    pub(in crate::type_checker) _module_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _decl_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _import_visible_type_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _import_visible_value_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _retained_params: Vec<LaniusBuffer<ModuleKeyRadixParams>>,
    pub(in crate::type_checker) bind_groups: BindGroups,
}

impl std::ops::Deref for State {
    type Target = Buffers;

    fn deref(&self) -> &Self::Target {
        &self.resources
    }
}
