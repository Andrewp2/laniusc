use super::*;

pub(in crate::type_checker) struct ScanStep<T> {
    pub(in crate::type_checker) params: LaniusBuffer<T>,
    pub(in crate::type_checker) read_from_a: bool,
    pub(in crate::type_checker) write_to_a: bool,
}

pub(in crate::type_checker) type LoopDepthScanStep = ScanStep<LoopDepthParams>;
pub(in crate::type_checker) type FnContextScanStep = ScanStep<FnContextParams>;
pub(in crate::type_checker) type NameScanStep = ScanStep<NameScanParams>;

pub(in crate::type_checker) struct NameRadixStep {
    pub(in crate::type_checker) _params: LaniusBuffer<NameRadixParams>,
}

pub(in crate::type_checker) struct ModuleKeyRadixStep {
    pub(in crate::type_checker) _params: LaniusBuffer<ModuleKeyRadixParams>,
}

pub(in crate::type_checker) struct PredicateKeyStep {
    pub(in crate::type_checker) _params: LaniusBuffer<PredicateKeyParams>,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct ScanRows<'a> {
    pub(in crate::type_checker) local_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) block_sum: &'a wgpu::Buffer,
    pub(in crate::type_checker) prefix_a: &'a wgpu::Buffer,
    pub(in crate::type_checker) prefix_b: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixRows<'a> {
    pub(in crate::type_checker) histogram: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_total: &'a wgpu::Buffer,
    pub(in crate::type_checker) bucket_base: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameLexemeRows<'a> {
    pub(in crate::type_checker) flag: &'a wgpu::Buffer,
    pub(in crate::type_checker) kind: &'a wgpu::Buffer,
    pub(in crate::type_checker) prefix: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct SymbolRows<'a> {
    pub(in crate::type_checker) bytes: &'a wgpu::Buffer,
    pub(in crate::type_checker) start: &'a wgpu::Buffer,
    pub(in crate::type_checker) len: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameIdRows<'a> {
    pub(in crate::type_checker) by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) language: &'a wgpu::Buffer,
    pub(in crate::type_checker) sorted: &'a wgpu::Buffer,
    pub(in crate::type_checker) by_input: &'a wgpu::Buffer,
    pub(in crate::type_checker) unique_count: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct NameInput<'a> {
    pub(in crate::type_checker) params: &'a LaniusBuffer<TypeCheckParams>,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) cap: u32,
    pub(in crate::type_checker) token_blocks: u32,
    pub(in crate::type_checker) name_blocks: u32,
    pub(in crate::type_checker) steps: &'a [NameScanStep],
    pub(in crate::type_checker) token_words: &'a wgpu::Buffer,
    pub(in crate::type_checker) token_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) source_bytes: &'a wgpu::Buffer,
    pub(in crate::type_checker) status: &'a wgpu::Buffer,
    pub(in crate::type_checker) lexemes: NameLexemeRows<'a>,
    pub(in crate::type_checker) scan: ScanRows<'a>,
    pub(in crate::type_checker) total: &'a wgpu::Buffer,
    pub(in crate::type_checker) max_len: &'a wgpu::Buffer,
    pub(in crate::type_checker) spans: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_in: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) symbols: SymbolRows<'a>,
    pub(in crate::type_checker) ids: NameIdRows<'a>,
    pub(in crate::type_checker) radix: RadixRows<'a>,
    pub(in crate::type_checker) radix_args: &'a wgpu::Buffer,
    pub(in crate::type_checker) run_head: &'a wgpu::Buffer,
    pub(in crate::type_checker) adjacent_equal: &'a wgpu::Buffer,
    pub(in crate::type_checker) run_prefix: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleShape {
    pub(in crate::type_checker) hir_nodes: u32,
    pub(in crate::type_checker) scan_blocks: u32,
    pub(in crate::type_checker) record_capacity: u32,
    pub(in crate::type_checker) record_blocks: u32,
    pub(in crate::type_checker) leaf_base: u32,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleRows<'a> {
    pub(in crate::type_checker) active_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) semantic_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) flag: &'a wgpu::Buffer,
    pub(in crate::type_checker) prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan: ScanRows<'a>,
    pub(in crate::type_checker) count_out: &'a wgpu::Buffer,
    pub(in crate::type_checker) owner_fn: &'a wgpu::Buffer,
    pub(in crate::type_checker) name_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) token: &'a wgpu::Buffer,
    pub(in crate::type_checker) scope_end: &'a wgpu::Buffer,
    pub(in crate::type_checker) order: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) key_args: &'a wgpu::Buffer,
    pub(in crate::type_checker) key_radix: RadixRows<'a>,
    pub(in crate::type_checker) scope_tree: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct MethodDeclRows<'a> {
    pub(in crate::type_checker) impl_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) recv_tag: &'a wgpu::Buffer,
    pub(in crate::type_checker) recv_payload: &'a wgpu::Buffer,
    pub(in crate::type_checker) module_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) name_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) name_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) visibility: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct MethodKeyRows<'a> {
    pub(in crate::type_checker) to_fn_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) order_tmp: &'a wgpu::Buffer,
    pub(in crate::type_checker) status: &'a wgpu::Buffer,
    pub(in crate::type_checker) duplicate_of: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct MethodKeyInput<'a> {
    pub(in crate::type_checker) label: &'static str,
    pub(in crate::type_checker) cap: u32,
    pub(in crate::type_checker) blocks: u32,
    pub(in crate::type_checker) token_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) module_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) decl: MethodDeclRows<'a>,
    pub(in crate::type_checker) module_type_path_type: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_instance_decl_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_instance_arg_start: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_instance_arg_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_instance_arg_ref_tag: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_instance_arg_ref_payload: &'a wgpu::Buffer,
    pub(in crate::type_checker) keys: MethodKeyRows<'a>,
    pub(in crate::type_checker) radix: RadixRows<'a>,
    pub(in crate::type_checker) status: &'a wgpu::Buffer,
}

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
    pub(in crate::type_checker) radix: RadixRows<'a>,
    pub(in crate::type_checker) method_contract_owner_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_name_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_name_id: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_param_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_first_param_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_return_type_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_visibility: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_status: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_param_next_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_param_type_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_owner_range_first: &'a wgpu::Buffer,
    pub(in crate::type_checker) method_contract_owner_range_count: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct PredicateInput<'a> {
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) predicate_capacity: u32,
    pub(in crate::type_checker) predicate_blocks: u32,
    pub(in crate::type_checker) params: &'a LaniusBuffer<TypeCheckParams>,
    pub(in crate::type_checker) hir_status: &'a wgpu::Buffer,
    pub(in crate::type_checker) hir_token_pos: &'a wgpu::Buffer,
    pub(in crate::type_checker) hir_items: GpuTypeCheckHirItemBuffers<'a>,
    pub(in crate::type_checker) module_path: &'a ModulePathState,
    pub(in crate::type_checker) name_id_by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) generic_param_count_by_node: &'a wgpu::Buffer,
    pub(in crate::type_checker) generic_param_slot_by_token: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_expr_ref_tag: &'a wgpu::Buffer,
    pub(in crate::type_checker) type_code_by_name: &'a wgpu::Buffer,
    pub(in crate::type_checker) rows: PredicateRows<'a>,
}

pub(in crate::type_checker) struct LoopDepthBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) local: wgpu::BindGroup,
    pub(in crate::type_checker) scan: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) apply: wgpu::BindGroup,
}

pub(in crate::type_checker) struct FnContextBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) local: wgpu::BindGroup,
    pub(in crate::type_checker) scan: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) apply: wgpu::BindGroup,
}

pub(in crate::type_checker) struct VisibleBindGroups {
    pub(in crate::type_checker) hir_decl_scan_n_blocks: u32,
    pub(in crate::type_checker) hir_decl_record_n_blocks: u32,
    pub(in crate::type_checker) hir_semantic_dispatch_args: wgpu::Buffer,
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) legacy_token_visibility: Option<LegacyVisibleBindGroups>,
    pub(in crate::type_checker) hir_semantic_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) mark_hir_decl_names: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_scan: U32ScanBindGroups,
    pub(in crate::type_checker) scatter_hir_decl_records: wgpu::BindGroup,
    pub(in crate::type_checker) seed_hir_decl_order: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_key_radix_dispatch_args: wgpu::Buffer,
    pub(in crate::type_checker) _hir_semantic_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _hir_decl_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) _hir_decl_key_radix_steps: Vec<ModuleKeyRadixStep>,
    pub(in crate::type_checker) sort_hir_decl_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_hir_decl_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_hir_decl_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_hir_decl_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) _hir_decl_scope_leaf_params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) build_hir_decl_scope_leaves: wgpu::BindGroup,
    pub(in crate::type_checker) hir_decl_scope_leaf_work_items: u32,
    pub(in crate::type_checker) hir_decl_scope_tree_levels: Vec<VisibleDeclScopeTreeLevel>,
    pub(in crate::type_checker) hir_names: wgpu::BindGroup,
}

pub(in crate::type_checker) struct LegacyVisibleBindGroups {
    pub(in crate::type_checker) scope_blocks: wgpu::BindGroup,
    pub(in crate::type_checker) scatter: wgpu::BindGroup,
    pub(in crate::type_checker) decode: wgpu::BindGroup,
}

pub(in crate::type_checker) struct VisibleDeclScopeTreeLevel {
    pub(in crate::type_checker) _params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) bind_group: wgpu::BindGroup,
    pub(in crate::type_checker) work_items: u32,
}

pub(in crate::type_checker) struct NameBindGroups {
    pub(in crate::type_checker) token_scan_n_blocks: u32,
    pub(in crate::type_checker) radix_n_blocks: u32,
    pub(in crate::type_checker) radix_dispatch_args: wgpu::Buffer,
    pub(in crate::type_checker) name_max_len: wgpu::Buffer,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) scan_local: wgpu::BindGroup,
    pub(in crate::type_checker) scan_blocks: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) scan_apply: wgpu::BindGroup,
    pub(in crate::type_checker) scatter: wgpu::BindGroup,
    pub(in crate::type_checker) radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) _radix_steps: Vec<NameRadixStep>,
    pub(in crate::type_checker) radix_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) radix_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) radix_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) radix_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) dedup: wgpu::BindGroup,
    pub(in crate::type_checker) _run_head_scan_steps: Vec<NameScanStep>,
    pub(in crate::type_checker) run_head_scan_local: wgpu::BindGroup,
    pub(in crate::type_checker) run_head_scan_blocks: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) run_head_scan_apply: wgpu::BindGroup,
    pub(in crate::type_checker) assign_ids: wgpu::BindGroup,
}

pub(in crate::type_checker) struct LanguageNameBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark: wgpu::BindGroup,
    pub(in crate::type_checker) type_codes_clear: wgpu::BindGroup,
    pub(in crate::type_checker) decls_materialize: wgpu::BindGroup,
}

pub(in crate::type_checker) struct U32ScanBindGroups {
    pub(in crate::type_checker) local: wgpu::BindGroup,
    pub(in crate::type_checker) blocks: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) apply: wgpu::BindGroup,
}

pub(in crate::type_checker) struct TypeInstanceBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) mark_generic_param_records: wgpu::BindGroup,
    pub(in crate::type_checker) propagate_generic_decl_owner: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) generic_param_scan: U32ScanBindGroups,
    pub(in crate::type_checker) decl_generic_params: wgpu::BindGroup,
    pub(in crate::type_checker) generic_param_key_radix_dispatch_args: wgpu::Buffer,
    pub(in crate::type_checker) generic_param_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_generic_param_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_generic_param_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_generic_param_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_generic_param_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) generic_param_use_slots: wgpu::BindGroup,
    pub(in crate::type_checker) seed_struct_field_keys: wgpu::BindGroup,
    pub(in crate::type_checker) struct_field_key_radix_dispatch_args: wgpu::Buffer,
    pub(in crate::type_checker) struct_field_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_struct_field_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_struct_field_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_struct_field_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_struct_field_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_refs: wgpu::BindGroup,
    pub(in crate::type_checker) collect_aggregate_details: wgpu::BindGroup,
    pub(in crate::type_checker) collect_named_arg_refs: wgpu::BindGroup,
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
    pub(in crate::type_checker) array_index_results: wgpu::BindGroup,
    pub(in crate::type_checker) validate_aggregate_access: wgpu::BindGroup,
}

pub(in crate::type_checker) struct CallBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) return_refs: wgpu::BindGroup,
    pub(in crate::type_checker) entrypoints: wgpu::BindGroup,
    pub(in crate::type_checker) functions: wgpu::BindGroup,
    pub(in crate::type_checker) param_types: wgpu::BindGroup,
    pub(in crate::type_checker) intrinsics: wgpu::BindGroup,
    pub(in crate::type_checker) clear_hir_call_args: wgpu::BindGroup,
    pub(in crate::type_checker) pack_hir_call_args: wgpu::BindGroup,
    pub(in crate::type_checker) resolve: wgpu::BindGroup,
    pub(in crate::type_checker) infer_array_generics: wgpu::BindGroup,
    pub(in crate::type_checker) validate_array_results: wgpu::BindGroup,
    pub(in crate::type_checker) erase_generic_params: wgpu::BindGroup,
}

pub(in crate::type_checker) struct MethodBindGroups {
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) attach_metadata: wgpu::BindGroup,
    pub(in crate::type_checker) bind_self_receivers: wgpu::BindGroup,
    pub(in crate::type_checker) keys: MethodKeyBindGroups,
    pub(in crate::type_checker) mark_call_keys: wgpu::BindGroup,
    pub(in crate::type_checker) mark_call_return_keys: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_table: wgpu::BindGroup,
    pub(in crate::type_checker) resolve: wgpu::BindGroup,
}

pub(in crate::type_checker) struct MethodKeyBindGroups {
    pub(in crate::type_checker) _key_radix_steps: Vec<ModuleKeyRadixStep>,
    pub(in crate::type_checker) seed_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) sort_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) validate_keys: wgpu::BindGroup,
}

pub(in crate::type_checker) struct PredicateBindGroups {
    pub(in crate::type_checker) _owner_key_radix_steps: Vec<PredicateKeyStep>,
    pub(in crate::type_checker) _impl_key_radix_steps: Vec<PredicateKeyStep>,
    pub(in crate::type_checker) _method_contract_key_radix_steps: Vec<PredicateKeyStep>,
    pub(in crate::type_checker) clear_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_bound_arg_facts: wgpu::BindGroup,
    pub(in crate::type_checker) collect_method_contracts: wgpu::BindGroup,
    pub(in crate::type_checker) collect: wgpu::BindGroup,
    pub(in crate::type_checker) seed_method_contract_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) sort_method_contract_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_method_contract_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_method_contract_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_method_contract_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) build_method_contract_owner_ranges: wgpu::BindGroup,
    pub(in crate::type_checker) seed_owner_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) sort_owner_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_owner_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_owner_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_owner_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) seed_impl_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) sort_impl_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_impl_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_impl_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_impl_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) obligations: wgpu::BindGroup,
}
