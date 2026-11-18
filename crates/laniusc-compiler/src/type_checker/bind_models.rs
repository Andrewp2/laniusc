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
        Option<super::substitution::FieldClosureOperations>,
    pub(in crate::type_checker) index_generated_applications: Option<ComputeOperation>,
    pub(in crate::type_checker) project_imported_fields: Option<ComputeOperation>,
    pub(in crate::type_checker) member_receivers: ComputeOperation,
    pub(in crate::type_checker) member_receivers_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_receivers_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_receivers_inference: ComputeOperation,
    pub(in crate::type_checker) member_results: ComputeOperation,
    pub(in crate::type_checker) member_results_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_results_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_results_inference: ComputeOperation,
    pub(in crate::type_checker) member_substitute: ComputeOperation,
    pub(in crate::type_checker) member_substitute_after_match: ComputeInvocation,
    pub(in crate::type_checker) member_substitute_after_array: ComputeInvocation,
    pub(in crate::type_checker) member_substitute_inference: ComputeOperation,
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
    /// Field expectations and struct-literal references, one dispatch.
    pub(in crate::type_checker) fields_and_references: ComputeOperation,
    /// Lists the rows of the struct-literal passes once per job.
    pub(in crate::type_checker) rows_clear: crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) rows_list: ComputeOperation,
    pub(in crate::type_checker) rows_args: ComputeOperation,
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
    pub(in crate::type_checker) contextual_results_final: ComputeOperation,
    pub(in crate::type_checker) clear_generic_claim_type_args: ComputeOperation,
    pub(in crate::type_checker) apply_row_args: ComputeOperation,
    /// The rounds' application (listed active blocks).
    pub(in crate::type_checker) apply_final_row_args: ComputeOperation,
    /// Bound-directed inference: clear, the resident page's
    /// implementations and bounds, this unit's implementations, inference.
    pub(in crate::type_checker) bound_inference: Option<BoundInferenceOperations>,
    pub(in crate::type_checker) bind_method_receiver_environment: Option<ComputeOperation>,
    pub(in crate::type_checker) materialize_return_types: Option<ComputeOperation>,
    /// The field closure of the call results and argument contexts.
    pub(in crate::type_checker) call_field_closure: super::substitution::FieldClosureOperations,
    pub(in crate::type_checker) project_argument_contexts:
        Option<super::substitution::ArgumentContextOperations>,
    pub(in crate::type_checker) substitution: super::substitution::SubstitutionOperations,
    pub(in crate::type_checker) project_literal_contexts: Option<ComputeOperation>,
    pub(in crate::type_checker) record_literal_inference: Option<RecordLiteralInferenceOperations>,
    pub(in crate::type_checker) field_expected_ids: super::struct_literal_field_types::FieldExpectedIdOperations,
    pub(in crate::type_checker) validation_call_envs: super::struct_literal_field_types::ValidationCallEnvOperation,
    pub(in crate::type_checker) materialize_match_payloads: Option<ComputeOperation>,
    pub(in crate::type_checker) return_type_source_index: Option<ComputeOperation>,
    pub(in crate::type_checker) return_type_index_clear: Option<ComputeOperation>,
    /// Lists the live type rows the rounds' row passes visit, before the
    /// rounds (live_type_row_list.slang).
    pub(in crate::type_checker) type_row_list: Option<TypeRowListOperations>,
    /// Each function's rows once per job, and the list of the round's active
    /// blocks at the start of each round's passes
    /// (calls/inference_blocks.slang).
    pub(in crate::type_checker) inference_blocks: InferenceBlockOperations,
    pub(in crate::type_checker) call_roots: CallRootListOperations,
    pub(in crate::type_checker) return_type_index: Option<ComputeOperation>,
    pub(in crate::type_checker) return_imported_fields: Option<ComputeOperation>,
    pub(in crate::type_checker) project_expression_types: Option<ComputeOperation>,
    pub(in crate::type_checker) project_array_literal_elements: Option<ComputeOperation>,
    pub(in crate::type_checker) materialize_array_literals: Option<ComputeOperation>,
    pub(in crate::type_checker) validate_array_literals: Option<ComputeOperation>,
    pub(in crate::type_checker) infer_return_bindings: Option<ComputeOperation>,
    /// Zeroes the round's change count (state word 1) before each round and
    /// counts the round.
    pub(in crate::type_checker) inference_round_reset: crate::gpu::operations::ClearBufferOperation,
    /// Copies a round's number (`record_round`) into the round word.
    pub(in crate::type_checker) inference_round_number: crate::gpu::operations::CopyBufferOperation,
    /// Zeroes the per-function change rounds before the first round.
    pub(in crate::type_checker) inference_activity_clear: crate::gpu::operations::ClearBufferOperation,
    /// Per batch slot, the copy of the state words into the slot.
    pub(in crate::type_checker) inference_readback:
        Vec<crate::gpu::operations::CopyBufferOperation>,
    /// Per batch slot, the copy of the status words after the state words.
    pub(in crate::type_checker) inference_status_readback:
        Vec<crate::gpu::operations::CopyBufferOperation>,
    /// Status words for the follow-on checks; recorded before each 03a4b
    /// invocation and before the final validation passes.
    pub(in crate::type_checker) status_prior: crate::gpu::operations::CopyBufferOperation,
    pub(in crate::type_checker) infer_array_generics: ComputeOperation,
    pub(in crate::type_checker) validate_array_results: ComputeOperation,
    pub(in crate::type_checker) mark_array_args: ComputeOperation,
    pub(in crate::type_checker) project_result_instances: ComputeOperation,
    pub(in crate::type_checker) erase_generic_params: ComputeOperation,
}

/// The passes of bound-directed generic call inference.
/// The call field closure's root locations, listed once per job.
pub(in crate::type_checker) struct CallRootListOperations {
    pub(in crate::type_checker) clear_count: crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) clear_args: crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) list: ComputeOperation,
}

impl CallRootListOperations {
    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear_count.record(encoder);
        self.clear_args.record(encoder);
        self.list.record(encoder)
    }
}

pub(in crate::type_checker) struct InferenceBlockOperations {
    /// Zeroes the function ranges, marks and always-active lists.
    pub(in crate::type_checker) clear: crate::gpu::operations::ClearBufferOperation,
    /// Records each function's HIR rows and tokens.
    pub(in crate::type_checker) ranges: ComputeOperation,
    /// Sizes the list's dispatch: a lane per function.
    pub(in crate::type_checker) args: ComputeOperation,
    /// Lists the round's active blocks and writes the listed passes' grids.
    pub(in crate::type_checker) list: ComputeOperation,
}

pub(in crate::type_checker) struct TypeRowListOperations {
    /// Zeroes the list's count.
    pub(in crate::type_checker) clear: crate::gpu::operations::ClearBufferOperation,
    /// Lists the source rows that hold a type.
    pub(in crate::type_checker) list: ComputeOperation,
    /// Sizes the listed passes' dispatch.
    pub(in crate::type_checker) args: ComputeOperation,
}

pub(in crate::type_checker) struct BoundInferenceOperations {
    /// Zeroes the bound tables' counts, before the local collection.
    pub(in crate::type_checker) clear: crate::gpu::operations::ClearBufferOperation,
    /// Saves the counts after the local collection.
    pub(in crate::type_checker) snapshot: crate::gpu::operations::CopyBufferOperation,
    /// Returns the counts to the local rows before a round's dependency
    /// collection.
    pub(in crate::type_checker) restore: crate::gpu::operations::CopyBufferOperation,
    /// Present when the unit has dependency interfaces.
    pub(in crate::type_checker) collect_dependency: Option<ComputeOperation>,
    pub(in crate::type_checker) collect_local: ComputeOperation,
    pub(in crate::type_checker) infer: ComputeOperation,
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
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) offer_bound_members: ComputeOperation,
    pub(in crate::type_checker) finalize_candidates: ComputeOperation,
    pub(in crate::type_checker) resolve: ComputeOperation,
    pub(in crate::type_checker) lookup: MethodLookupSweeps,
    pub(in crate::type_checker) inference: MethodInferenceOperations,
}

/// The inference rounds' own operations, which dispatch from the listed
/// active blocks (calls/inference_blocks.slang).
pub(in crate::type_checker) struct MethodInferenceOperations {
    pub(in crate::type_checker) mark_call_return_keys: ComputeOperation,
    pub(in crate::type_checker) resolve_table: ComputeOperation,
    pub(in crate::type_checker) offer_bound_members: ComputeOperation,
    pub(in crate::type_checker) finalize_candidates: ComputeOperation,
}

/// The preliminary lookup sweeps' own operations. They dispatch from the gated
/// copy of the method grids, so a sweep after one that changed no target
/// launches no workgroups.
pub(in crate::type_checker) struct MethodLookupSweeps {
    pub(in crate::type_checker) arm: ComputeOperation,
    pub(in crate::type_checker) mark_call_keys: ComputeOperation,
    pub(in crate::type_checker) mark_call_return_keys: ComputeOperation,
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
    /// Zeroes `solver_demand` ahead of the passes that count into it.
    pub(in crate::type_checker) solver_demand_clear: crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) count_obligation_pairs: ComputeOperation,
    pub(in crate::type_checker) obligation_pair_scan: PrefixScanOperation,
    pub(in crate::type_checker) obligation_pair_dispatch_clear:
        crate::gpu::operations::ClearBufferOperation,
    pub(in crate::type_checker) obligation_pair_dispatch: ComputeOperation,
    pub(in crate::type_checker) validate_obligation_pairs: ComputeOperation,
}
