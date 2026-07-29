use super::*;

/// Common histogram/prefix/base layout used by byte-wise radix sorts.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixRows<'a> {
    pub(in crate::type_checker) histogram: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_total: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_base: &'a wgpu::Buffer,
}

/// Token-indexed rows that identify source lexemes participating in naming.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameLexemeRows<'a> {
    pub(in crate::type_checker) flag: &'a wgpu::Buffer,
    pub(in crate::type_checker) kind: &'a wgpu::Buffer,
    pub(in crate::type_checker) prefix: &'a wgpu::Buffer,
}

/// Borrowed spelling table used for language and source symbols.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct SymbolRows<'a> {
    pub(in crate::type_checker) bytes: &'a wgpu::Buffer,
    pub(in crate::type_checker) start: &'a wgpu::Buffer,
    pub(in crate::type_checker) len: &'a wgpu::Buffer,
}

/// Borrowed rows that map names between token, language, sorted, and unique ids.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameIdRows<'a> {
    pub(in crate::type_checker) by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) language: &'a wgpu::Buffer,
    pub(in crate::type_checker) sorted: &'a wgpu::Buffer,
    pub(in crate::type_checker) by_input: &'a wgpu::Buffer,
    pub(in crate::type_checker) unique_count: &'a wgpu::Buffer,
}

/// Two-table storage used by the exact-name hash set.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameHashRows<'a> {
    pub(in crate::type_checker) table_a: &'a wgpu::Buffer,
    pub(in crate::type_checker) table_b: &'a wgpu::Buffer,
}

/// Complete input set for constructing name bind groups.
///
/// This keeps the name pipeline constructor typed by relation role rather than
/// by a long positional list of buffers.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameInput<'a> {
    pub(in crate::type_checker) params: &'a LaniusBuffer<TypeCheckParams>,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) cap: u32,
    pub(in crate::type_checker) name_blocks: u32,
    pub(in crate::type_checker) token_words: &'a wgpu::Buffer,
    pub(in crate::type_checker) token_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) source_bytes: &'a wgpu::Buffer,
    pub(in crate::type_checker) status: &'a wgpu::Buffer,
    pub(in crate::type_checker) lexemes: NameLexemeRows<'a>,
    pub(in crate::type_checker) total: &'a wgpu::Buffer,
    pub(in crate::type_checker) max_len: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) spans: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_in: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) symbols: SymbolRows<'a>,
    pub(in crate::type_checker) ids: NameIdRows<'a>,
    pub(in crate::type_checker) hash: NameHashRows<'a>,
}

/// Capacity and tree-shape summary for visible-declaration passes.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleShape {
    pub(in crate::type_checker) hir_nodes: u32,
    pub(in crate::type_checker) record_capacity: u32,
    pub(in crate::type_checker) record_blocks: u32,
    pub(in crate::type_checker) leaf_base: u32,
}

/// Borrowed rows used to compact and sort HIR-visible declarations.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleRows<'a> {
    pub(in crate::type_checker) semantic_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) semantic_dispatch_args: &'a LaniusBuffer<u32>,
    pub(in crate::type_checker) count_out: &'a wgpu::Buffer,
    pub(in crate::type_checker) scope_end: &'a wgpu::Buffer,
    pub(in crate::type_checker) order: &'a wgpu::Buffer,
    pub(in crate::type_checker) key_args: &'a wgpu::Buffer,
    pub(in crate::type_checker) scope_tree: &'a wgpu::Buffer,
}

/// Borrowed predicate and method-contract rows used by predicate passes.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct PredicateRows<'a> {
    pub(in crate::type_checker) owner_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) subject_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) bound_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) bound_decl_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) bound_arg_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) first_arg_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) second_arg_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) status: &'a wgpu::Buffer,
    pub(in crate::type_checker) owner_order: &'a wgpu::Buffer,
    pub(in crate::type_checker) owner_order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) impl_order: &'a wgpu::Buffer,
    pub(in crate::type_checker) impl_order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_order: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_param_order: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_param_order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) radix: RadixRows<'a>,
    pub(in crate::type_checker) method_contract_owner_hir: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_name_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_name_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_param_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_return_type_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_visibility: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_status: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_param_type_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_owner_range_first: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_owner_range_count: &'a wgpu::Buffer,
}

/// Borrowed rows for counted predicate-obligation pair emission.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct PredicateObligationRows<'a> {
    pub(in crate::type_checker) pair_total: &'a wgpu::Buffer,
    pub(in crate::type_checker) pair_dispatch_args: &'a wgpu::Buffer,
}

/// Complete input set for predicate collection, sorting, and validation.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct PredicateInput<'a> {
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) predicate_capacity: u32,
    pub(in crate::type_checker) predicate_blocks: u32,
    pub(in crate::type_checker) params: &'a LaniusBuffer<TypeCheckParams>,
    pub(in crate::type_checker) hir_active_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) hir_status: &'a wgpu::Buffer,
    pub(in crate::type_checker) hir_token_pos: &'a wgpu::Buffer,
    pub(in crate::type_checker) hir_items: GpuTypeCheckHirItemBuffers<'a>,
    pub(in crate::type_checker) module_path: &'a ModulePathState,
    pub(in crate::type_checker) name_id_by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) generic_param_count_by_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) generic_param_slot_by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_expr_ref_tag: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_expr_ref_payload: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_code_by_name: &'a wgpu::Buffer,
    pub(in crate::type_checker) rows: PredicateRows<'a>,
    pub(in crate::type_checker) obligation_rows: PredicateObligationRows<'a>,
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
    pub(in crate::type_checker) hir_semantic_dispatch_args: LaniusBuffer<u32>,
    pub(in crate::type_checker) match_payload_dispatch_args: LaniusBuffer<u32>,
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) hir_semantic_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) mark_hir_decl_names: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_hir_decl_records: wgpu::BindGroup,
    pub(in crate::type_checker) match_payload_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_match_payload_decls: wgpu::BindGroup,
    pub(in crate::type_checker) finalize_decl_count: wgpu::BindGroup,
    pub(in crate::type_checker) declarations: VisibleDeclSort,
    pub(in crate::type_checker) _hir_semantic_dispatch_params: LaniusBuffer<CountDispatchParams>,
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
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter: wgpu::BindGroup,
    pub(in crate::type_checker) hash_work_items: u32,
    pub(in crate::type_checker) _hash_params: LaniusBuffer<NameRadixParams>,
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
    pub(in crate::type_checker) propagate_generic_decl_owner: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) type_instance_arg_row_scan: PrefixScanOperation,
    pub(in crate::type_checker) decl_generic_params: wgpu::BindGroup,
    pub(in crate::type_checker) generic_parameter_sorts: GenericParameterSorts,
    pub(in crate::type_checker) generic_param_use_slots: wgpu::BindGroup,
    pub(in crate::type_checker) seed_struct_field_keys: wgpu::BindGroup,
    pub(in crate::type_checker) struct_field_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_struct_fields: RadixSortOperation<StructFieldKeyRadixParams>,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_refs: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_details: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named_arg_refs: wgpu::BindGroup,
    pub(in crate::type_checker) hash_arg_rows: wgpu::BindGroup,
    pub(in crate::type_checker) clear_semantic_type_rows: Box<wgpu::BindGroup>,
    pub(in crate::type_checker) mark_semantic_type_rows: Box<wgpu::BindGroup>,
    pub(in crate::type_checker) semantic_type_scan: Box<PrefixScanOperation>,
    pub(in crate::type_checker) scatter_semantic_type_rows: Box<wgpu::BindGroup>,
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
#[allow(dead_code)] // Legacy friend-vector resources retained until their pass definitions are removed.
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
    pub(in crate::type_checker) mark_compact_hir_call_args: ComputeOperation,
    pub(in crate::type_checker) compact_hir_call_arg_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_compact_hir_call_args: ComputeOperation,
    pub(in crate::type_checker) call_param_segment_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_compact_hir_params: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
    pub(in crate::type_checker) backend_targets: ComputeOperation,
    pub(in crate::type_checker) argument_matching: CallArgumentMatchingOperation,
    pub(in crate::type_checker) generic_claim_validation: CallGenericClaimValidationOperation,
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
    pub(in crate::type_checker) keys: MethodKeyPipeline,
    pub(in crate::type_checker) mark_call_keys: ComputeOperation,
    pub(in crate::type_checker) mark_call_return_keys: ComputeOperation,
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
}

/// Bind groups for trait/predicate collection, sorting, and obligation checks.
pub(in crate::type_checker) struct PredicateBindGroups {
    pub(in crate::type_checker) method_contract_keys: PredicateKeyPipeline,
    pub(in crate::type_checker) method_param_keys: PredicateKeyPipeline,
    pub(in crate::type_checker) owner_keys: PredicateKeyPipeline,
    pub(in crate::type_checker) impl_keys: PredicateKeyPipeline,
    pub(in crate::type_checker) clear_syntax_tokens: wgpu::BindGroup,
    pub(in crate::type_checker) clear_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_method_contracts: wgpu::BindGroup,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) validate_bound_args: wgpu::BindGroup,
    pub(in crate::type_checker) collect_impls: wgpu::BindGroup,
    pub(in crate::type_checker) build_method_contract_owner_ranges: wgpu::BindGroup,
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
