use super::*;

/// Capacity and tree-shape summary for visible-declaration passes.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct VisibleShape {
    pub(in crate::type_checker) tokens: u32,
    pub(in crate::type_checker) hir_nodes: u32,
    pub(in crate::type_checker) record_capacity: u32,
    pub(in crate::type_checker) record_blocks: u32,
    pub(in crate::type_checker) leaf_base: u32,
}

/// Bind groups for the enclosing-`if` depth clear/mark/scan/apply pipeline.
pub(in crate::type_checker) struct IfDepthBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) mark: ComputeOperation,
    pub(in crate::type_checker) local: ComputeOperation,
    pub(in crate::type_checker) hierarchy_up: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) hierarchy_down: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) apply: ComputeOperation,
}

/// Bind groups for the enclosing-function clear/mark/scan/apply pipeline.
pub(in crate::type_checker) struct FnContextBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) mark: ComputeOperation,
    pub(in crate::type_checker) local: ComputeOperation,
    pub(in crate::type_checker) hierarchy_up: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) hierarchy_down: Vec<ScanHierarchyStep>,
    pub(in crate::type_checker) apply: ComputeOperation,
}

/// Bind groups for HIR-visible declaration collection and lexical lookup.
pub(in crate::type_checker) struct VisibleBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) mark_hir_declarations: ComputeOperation,
    pub(in crate::type_checker) match_payload_dispatch: ComputeOperation,
    pub(in crate::type_checker) mark_match_payload_declarations: ComputeOperation,
    pub(in crate::type_checker) declaration_scan: PrefixScanOperation,
    pub(in crate::type_checker) scatter_declarations: ComputeOperation,
    pub(in crate::type_checker) declarations: VisibleDeclSort,
    pub(in crate::type_checker) _match_payload_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) _hir_decl_scope_leaf_params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) build_hir_decl_scope_leaves: ComputeOperation,
    pub(in crate::type_checker) hir_decl_scope_tree_levels: Vec<VisibleDeclScopeTreeLevel>,
    pub(in crate::type_checker) hir_names: ComputeOperation,
}

/// One internal level in the visible-declaration scope tree.
pub(in crate::type_checker) struct VisibleDeclScopeTreeLevel {
    pub(in crate::type_checker) _params: LaniusBuffer<VisibleDeclTreeParams>,
    pub(in crate::type_checker) operation: ComputeOperation,
}

/// Bind groups and retained parameters for source-name compaction and sorting.
pub(in crate::type_checker) struct NameBindGroups {
    pub(in crate::type_checker) compaction: CompactionOperation,
    pub(in crate::type_checker) _hash_params: LaniusBuffer<NameHashParams>,
    pub(in crate::type_checker) hash_prepare: ComputeOperation,
    pub(in crate::type_checker) hash_insert: ComputeOperation,
    pub(in crate::type_checker) hash_assign_ids: ComputeOperation,
}

/// Bind groups for clearing and materializing builtin language symbols.
pub(in crate::type_checker) struct LanguageNameBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) type_codes_clear: ComputeOperation,
    pub(in crate::type_checker) decls_materialize: ComputeOperation,
}

/// One hierarchy level used by the fixed-size control-flow scans.
pub(in crate::type_checker) struct ScanHierarchyStep {
    pub(in crate::type_checker) operation: ComputeOperation,
}

/// Bind groups for generic parameter, type-instance, aggregate, and member refs.
pub(in crate::type_checker) struct TypeInstanceBindGroups {
    pub(in crate::type_checker) clear: ComputeOperation,
    pub(in crate::type_checker) clear_constants: ComputeOperation,
    pub(in crate::type_checker) type_instance_arg_row_scan: PrefixScanOperation,
    pub(in crate::type_checker) generic_parameters: GenericParameterRecordOperation,
    pub(in crate::type_checker) struct_field_index: StructFieldIndex,
    pub(in crate::type_checker) collection: TypeInstanceCollectionOperations,
    pub(in crate::type_checker) collect_named_arg_refs: ComputeOperation,
    pub(in crate::type_checker) clear_semantic_type_rows: Box<ComputeOperation>,
    pub(in crate::type_checker) semantic_type_rows: Box<CompactionOperation>,
    pub(in crate::type_checker) decl_refs: ComputeOperation,
    pub(in crate::type_checker) decl_refs_for_bindings: ComputeInvocation,
    pub(in crate::type_checker) infer_imported_decl_refs: ComputeOperation,
    pub(in crate::type_checker) index_closed_applications: Option<ComputeOperation>,
    /// The field closure of the closed source applications.
    pub(in crate::type_checker) source_field_closure:
        Option<super::substitution_passes::FieldClosureOperations>,
    pub(in crate::type_checker) index_generated_applications: Option<ComputeOperation>,
    pub(in crate::type_checker) project_imported_fields: Option<ComputeOperation>,
    pub(in crate::type_checker) member_receivers: ComputeOperation,
    pub(in crate::type_checker) member_receivers_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_receivers_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_receivers_inference: ComputeInvocation,
    pub(in crate::type_checker) member_results: ComputeOperation,
    pub(in crate::type_checker) member_results_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_results_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_results_inference: ComputeInvocation,
    pub(in crate::type_checker) member_substitute: ComputeOperation,
    pub(in crate::type_checker) member_substitute_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_substitute_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_substitute_inference: ComputeInvocation,
    pub(in crate::type_checker) struct_init_clear: ComputeOperation,
    pub(in crate::type_checker) struct_init_contexts: ComputeOperation,
    pub(in crate::type_checker) nested_struct_init_contexts: ComputeOperation,
    pub(in crate::type_checker) struct_init_fields: ComputeOperation,
    pub(in crate::type_checker) struct_init_substitute: ComputeOperation,
    pub(in crate::type_checker) array_return_refs: ComputeOperation,
    pub(in crate::type_checker) array_literal_return_refs: ComputeOperation,
    pub(in crate::type_checker) validate_aggregate_access: ComputeOperation,
}

pub(in crate::type_checker) struct RecordLiteralInferenceOperations {
    pub(in crate::type_checker) contexts: ComputeOperation,
    pub(in crate::type_checker) nested_contexts: ComputeOperation,
    pub(in crate::type_checker) fields: ComputeOperation,
    pub(in crate::type_checker) references: ComputeOperation,
}

pub(in crate::type_checker) struct TypeInstanceCollectionOperations {
    pub(in crate::type_checker) constant_scalars: ComputeOperation,
    pub(in crate::type_checker) projected_constant_scalars: ComputeInvocation,
    pub(in crate::type_checker) alias_constant_scalars: ComputeInvocation,
    pub(in crate::type_checker) scalar: ComputeOperation,
    pub(in crate::type_checker) named: ComputeOperation,
    pub(in crate::type_checker) aggregate_refs: ComputeOperation,
    pub(in crate::type_checker) aggregate_details: ComputeOperation,
    pub(in crate::type_checker) projected_scalar: ComputeInvocation,
    pub(in crate::type_checker) projected_named: ComputeInvocation,
    pub(in crate::type_checker) projected_aggregate_refs: ComputeInvocation,
    pub(in crate::type_checker) projected_aggregate_details: ComputeInvocation,
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
    pub(in crate::type_checker) explicit_application_binding: ComputeOperation,
    pub(in crate::type_checker) explicit_application_validation: ComputeOperation,
    pub(in crate::type_checker) backend_targets: ComputeOperation,
    pub(in crate::type_checker) argument_matching: CallArgumentMatchingOperation,
    pub(in crate::type_checker) generic_claim_validation: CallGenericClaimValidationOperation,
    pub(in crate::type_checker) environment_admission: CallEnvironmentAdmission,
    pub(in crate::type_checker) contextual_result_requests: ComputeOperation,
    pub(in crate::type_checker) clear_generic_claim_type_args: ComputeOperation,
    pub(in crate::type_checker) apply_row_args: ComputeOperation,
    pub(in crate::type_checker) bind_method_receiver_environment: Option<ComputeOperation>,
    pub(in crate::type_checker) materialize_return_types: Option<ComputeOperation>,
    /// The field closure of the call results and argument contexts.
    pub(in crate::type_checker) call_field_closure: super::substitution_passes::FieldClosureOperations,
    pub(in crate::type_checker) project_argument_contexts:
        Option<super::substitution_passes::ArgumentContextOperations>,
    pub(in crate::type_checker) substitution: super::substitution_passes::SubstitutionOperations,
    pub(in crate::type_checker) project_literal_contexts: Option<ComputeOperation>,
    pub(in crate::type_checker) record_literal_inference: Option<RecordLiteralInferenceOperations>,
    pub(in crate::type_checker) field_expected_ids: super::match_passes::FieldExpectedIdOperations,
    pub(in crate::type_checker) validation_call_envs: super::match_passes::ValidationCallEnvOperation,
    pub(in crate::type_checker) materialize_match_payloads: Option<ComputeOperation>,
    pub(in crate::type_checker) return_type_source_index: Option<ComputeOperation>,
    pub(in crate::type_checker) return_type_index_clear: Option<ComputeOperation>,
    pub(in crate::type_checker) return_type_index: Option<ComputeOperation>,
    pub(in crate::type_checker) return_imported_fields: Option<ComputeOperation>,
    pub(in crate::type_checker) project_expression_types: Option<ComputeOperation>,
    pub(in crate::type_checker) project_array_literal_elements: Option<ComputeOperation>,
    pub(in crate::type_checker) materialize_array_literals: Option<ComputeOperation>,
    pub(in crate::type_checker) validate_array_literals: Option<ComputeOperation>,
    pub(in crate::type_checker) infer_return_bindings: Option<ComputeOperation>,
    pub(in crate::type_checker) inference_readback: crate::gpu::operations::CopyBufferOperation,
    pub(in crate::type_checker) inference_status_readback:
        crate::gpu::operations::CopyBufferOperation,
    /// Status words for the follow-on checks; recorded before each 03a4b
    /// invocation and before the final validation passes.
    pub(in crate::type_checker) status_prior: crate::gpu::operations::CopyBufferOperation,
    pub(in crate::type_checker) infer_array_generics: ComputeOperation,
    pub(in crate::type_checker) validate_array_results: ComputeOperation,
    pub(in crate::type_checker) mark_array_args: ComputeOperation,
    pub(in crate::type_checker) project_result_instances: ComputeOperation,
    pub(in crate::type_checker) erase_generic_params: ComputeOperation,
}

/// A complete method selection transaction over one frozen receiver snapshot.
#[derive(Clone, Copy)]
pub(in crate::type_checker) enum MethodSelectionStage {
    Direct,
    Lookup,
    Inference,
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
    pub(in crate::type_checker) reset_candidates: ComputeOperation,
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) offer_bound_members: ComputeOperation,
    pub(in crate::type_checker) finalize_candidates: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
    pub(in crate::type_checker) lookup: MethodLookupSweeps,
}

/// The preliminary lookup sweeps' own operations. They dispatch from the gated
/// copy of the method grids, so a sweep after one that changed no target
/// launches no workgroups.
pub(in crate::type_checker) struct MethodLookupSweeps {
    pub(in crate::type_checker) arm: ComputeOperation,
    pub(in crate::type_checker) mark_call_keys: ComputeOperation,
    pub(in crate::type_checker) mark_call_return_keys: ComputeOperation,
    pub(in crate::type_checker) reset_candidates: ComputeOperation,
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) offer_bound_members: ComputeOperation,
    pub(in crate::type_checker) finalize_candidates: ComputeOperation,
    pub(in crate::type_checker) gate: ComputeOperation,
}

/// Bind groups for trait/predicate collection, indexing, and obligation checks.
pub(in crate::type_checker) struct PredicateBindGroups {
    pub(in crate::type_checker) clear_syntax_tokens: ComputeOperation,
    pub(in crate::type_checker) clear_bound_arg_facts: ComputeOperation,
    pub(in crate::type_checker) collect_bound_arg_facts: ComputeOperation,
    pub(in crate::type_checker) collect_method_contracts: ComputeOperation,
    pub(in crate::type_checker) collect: ComputeOperation,
    pub(in crate::type_checker) validate_bound_args: ComputeOperation,
    pub(in crate::type_checker) collect_impls: ComputeOperation,
    pub(in crate::type_checker) emit_method_validation_rows: ComputeOperation,
    pub(in crate::type_checker) emit_method_param_validation_rows: ComputeOperation,
    pub(in crate::type_checker) validate_imported_methods: ComputeOperation,
    pub(in crate::type_checker) reduce_method_validation_errors: ComputeOperation,
    pub(in crate::type_checker) _obligation_pair_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) count_obligation_pairs: ComputeOperation,
    pub(in crate::type_checker) obligation_pair_scan: PrefixScanOperation,
    pub(in crate::type_checker) obligation_pair_dispatch_clear:
        crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) obligation_pair_dispatch: ComputeOperation,
    pub(in crate::type_checker) validate_obligation_pairs: ComputeOperation,
}
