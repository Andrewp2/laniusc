use super::*;

/// Capacity and tree-shape summary for visible-declaration passes.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleShape {
    pub(in crate::type_checker) hir_nodes: u32,
    pub(in crate::type_checker) record_capacity: u32,
    pub(in crate::type_checker) record_blocks: u32,
    pub(in crate::type_checker) leaf_base: u32,
}

/// Bind groups for the enclosing-`if` depth clear/mark/scan/apply pipeline.
pub(in crate::type_checker) struct IfDepthBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) local: wgpu::BindGroup,
    pub(in crate::type_checker) hierarchy_up: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) hierarchy_down: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) apply: wgpu::BindGroup,
}

/// Bind groups for the enclosing-function clear/mark/scan/apply pipeline.
pub(in crate::type_checker) struct FnContextBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) local: wgpu::BindGroup,
    pub(in crate::type_checker) hierarchy_up: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) hierarchy_down: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) apply: wgpu::BindGroup,
}

/// Bind groups for HIR-visible declaration collection and lexical lookup.
pub(in crate::type_checker) struct VisibleBindGroups {
    pub(in crate::type_checker) compact_hir_dispatch_args: LaniusBuffer<u32>,
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) compact_hir_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) mark_hir_declarations: ComputeOperation,
    pub(in crate::type_checker) match_payload_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) mark_match_payload_declarations: ComputeOperation,
    pub(in crate::type_checker) declaration_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_declarations: ComputeOperation,
    pub(in crate::type_checker) declarations: VisibleDeclSort,
    pub(in crate::type_checker) _compact_hir_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _hir_decl_scope_leaf_params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) build_hir_decl_scope_leaves: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_scope_leaf_work_items: u32,
    pub(in crate::type_checker) hir_decl_scope_tree_levels: Vec<VisibleDeclScopeTreeLevel>,
    pub(in crate::type_checker) hir_names: wgpu::BindGroup,
}

/// One internal level in the visible-declaration scope tree.
pub(in crate::type_checker) struct VisibleDeclScopeTreeLevel {
    pub(in crate::type_checker) _params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) bind_group: wgpu::BindGroup,
    pub(in crate::type_checker) work_items: u32,
}

/// Bind groups and retained parameters for source-name compaction and sorting.
pub(in crate::type_checker) struct NameBindGroups {
    pub(in crate::type_checker) compaction: CompactionOperation,
    pub(in crate::type_checker) hash_work_items: u32,
    pub(in crate::type_checker) _hash_params: LaniusBuffer<NameHashParams>,
    pub(in crate::type_checker) hash_prepare: wgpu::BindGroup,
    pub(in crate::type_checker) hash_insert: wgpu::BindGroup,
    pub(in crate::type_checker) hash_assign_ids: wgpu::BindGroup,
}

/// Bind groups for clearing and materializing builtin language symbols.
pub(in crate::type_checker) struct LanguageNameBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) type_codes_clear: wgpu::BindGroup,
    pub(in crate::type_checker) decls_materialize: wgpu::BindGroup,
}

/// One hierarchy level used by the fixed-size control-flow scans.
pub(in crate::type_checker) struct ScanHierarchyStep {
    pub(in crate::type_checker) bind_group: wgpu::BindGroup,
    pub(in crate::type_checker) work_items: u32,
}

/// Bind groups for generic parameter, type-instance, aggregate, and member refs.
pub(in crate::type_checker) struct TypeInstanceBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark_generic_param_records: wgpu::BindGroup,
    pub(in crate::type_checker) type_instance_arg_row_scan: PrefixScanOperation,
    pub(in crate::type_checker) decl_generic_params: wgpu::BindGroup,
    pub(in crate::type_checker) generic_parameter_index: GenericParameterIndex,
    pub(in crate::type_checker) generic_param_use_slots: wgpu::BindGroup,
    pub(in crate::type_checker) struct_field_index: StructFieldIndex,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_refs: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_details: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named_arg_refs: wgpu::BindGroup,
    pub(in crate::type_checker) hash_arg_rows: wgpu::BindGroup,
    pub(in crate::type_checker) clear_semantic_type_rows: Box<wgpu::BindGroup>,
    pub(in crate::type_checker) semantic_type_rows: Box<CompactionOperation>,
    pub(in crate::type_checker) decl_refs: wgpu::BindGroup,
    pub(in crate::type_checker) member_receivers: wgpu::BindGroup,
    pub(in crate::type_checker) member_results: wgpu::BindGroup,
    pub(in crate::type_checker) member_substitute: wgpu::BindGroup,
    pub(in crate::type_checker) struct_init_clear: wgpu::BindGroup,
    pub(in crate::type_checker) struct_init_contexts: wgpu::BindGroup,
    pub(in crate::type_checker) struct_init_fields: wgpu::BindGroup,
    pub(in crate::type_checker) struct_init_substitute: wgpu::BindGroup,
    pub(in crate::type_checker) array_return_refs: wgpu::BindGroup,
    pub(in crate::type_checker) array_literal_return_refs: wgpu::BindGroup,
    pub(in crate::type_checker) validate_aggregate_access: wgpu::BindGroup,
}

/// Bind groups for function call collection, argument matching, and generics.
pub(in crate::type_checker) struct CallBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) clear_entrypoints: ComputeOperation,
    pub(in crate::type_checker) return_refs: ComputeOperation,
    pub(in crate::type_checker) entrypoints: ComputeOperation,
    pub(in crate::type_checker) functions: ComputeOperation,
    pub(in crate::type_checker) param_types: ComputeOperation,
    pub(in crate::type_checker) intrinsics: ComputeOperation,
    pub(in crate::type_checker) clear_hir_call_args: ComputeOperation,
    pub(in crate::type_checker) pack_hir_call_args: ComputeOperation,
    pub(in crate::type_checker) compact_hir_call_args: CompactionOperation,
    pub(in crate::type_checker) call_param_segment_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_compact_hir_params: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
    pub(in crate::type_checker) backend_targets: ComputeOperation,
    pub(in crate::type_checker) argument_matching: CallArgumentMatchingOperation,
    pub(in crate::type_checker) generic_claim_validation: CallGenericClaimValidationOperation,
    pub(in crate::type_checker) contextual_result_requests: ComputeOperation,
    pub(in crate::type_checker) clear_generic_claim_type_args: ComputeOperation,
    pub(in crate::type_checker) apply_row_args: ComputeOperation,
    pub(in crate::type_checker) infer_array_generics: wgpu::BindGroup,
    pub(in crate::type_checker) validate_array_results: ComputeOperation,
    pub(in crate::type_checker) mark_array_args: ComputeOperation,
    pub(in crate::type_checker) project_result_instances: ComputeOperation,
    pub(in crate::type_checker) erase_generic_params: wgpu::BindGroup,
}

/// Bind groups for method declaration collection and call resolution.
pub(in crate::type_checker) struct MethodBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) collect: ComputeOperation,
    pub(in crate::type_checker) attach_metadata: ComputeOperation,
    pub(in crate::type_checker) bind_self_receivers: ComputeOperation,
    pub(in crate::type_checker) keys: MethodIndex,
    pub(in crate::type_checker) mark_call_keys: ComputeOperation,
    pub(in crate::type_checker) mark_call_return_keys: ComputeOperation,
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
}

/// Bind groups for trait/predicate collection, indexing, and obligation checks.
pub(in crate::type_checker) struct PredicateBindGroups {
    pub(in crate::type_checker) clear_syntax_tokens: wgpu::BindGroup,
    pub(in crate::type_checker) clear_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_method_contracts: wgpu::BindGroup,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) validate_bound_args: wgpu::BindGroup,
    pub(in crate::type_checker) collect_impls: wgpu::BindGroup,
    pub(in crate::type_checker) emit_method_validation_rows: wgpu::BindGroup,
    pub(in crate::type_checker) emit_method_param_validation_rows: wgpu::BindGroup,
    pub(in crate::type_checker) validate_method_type_arg_rows: wgpu::BindGroup,
    pub(in crate::type_checker) reduce_method_validation_errors: wgpu::BindGroup,
    pub(in crate::type_checker) _obligation_pair_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) count_obligation_pairs: wgpu::BindGroup,
    pub(in crate::type_checker) obligation_pair_scan: PrefixScanOperation,
    pub(in crate::type_checker) obligation_pair_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) obligation_pair_dispatch_args: LaniusBuffer<u32>,
    pub(in crate::type_checker) validate_obligation_pairs: wgpu::BindGroup,
}
