use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

macro_rules! call_pass {
    ($suffix:literal, $domain:ident, $kernel:literal) => {
        typecheck_pass!(concat!("type_check.calls.", $suffix), $domain, $kernel)
    };
}

const RETURN_OUTPUTS: &[(&str, AccessMode)] = &[
    ("fn_return_ref_tag", AccessMode::Write),
    ("fn_return_ref_payload", AccessMode::Write),
];
const PARAM_TYPE_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_param_row_flag", AccessMode::Write),
    ("call_param_row_node_type", AccessMode::Write),
    ("call_param_row_node_ref_tag", AccessMode::Write),
    ("call_param_row_node_ref_payload", AccessMode::Write),
];
const PARAM_SCATTER_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_param_row_node", AccessMode::Write),
    ("call_param_row_fn_token", AccessMode::Write),
    ("call_param_row_ordinal", AccessMode::Write),
    ("call_param_row_type", AccessMode::Write),
    ("call_param_row_ref_tag", AccessMode::Write),
    ("call_param_row_ref_payload", AccessMode::Write),
    ("call_param_row_count", AccessMode::Write),
];
const ARGUMENT_MATCH_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_generic_claim_scan_input", AccessMode::Write),
    ("call_generic_claim_pattern_mask", AccessMode::Write),
    ("call_const_claim_scan_input", AccessMode::Write),
    ("call_const_claim_pattern_mask", AccessMode::Write),
];
const GENERIC_CLAIM_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_arg_row_literal_context_mask", AccessMode::Write),
    ("call_generic_claim_callee", AccessMode::Write),
    ("call_generic_claim_slot", AccessMode::Write),
    ("call_generic_claim_type", AccessMode::Write),
    ("call_generic_claim_ref_tag", AccessMode::Write),
    ("call_generic_claim_ref_payload", AccessMode::Write),
    ("call_generic_claim_arg_row", AccessMode::Write),
    ("call_const_claim_callee", AccessMode::Write),
    ("call_const_claim_slot", AccessMode::Write),
    ("call_const_claim_ref_kind", AccessMode::Write),
    ("call_const_claim_ref_payload", AccessMode::Write),
    ("call_const_claim_identity_mode", AccessMode::Write),
    ("call_const_claim_selected", AccessMode::Write),
    ("call_const_claim_arg_row", AccessMode::Write),
];

pub(in crate::type_checker) const CALLS_CLEAR: ReflectedComputeSpec =
    call_pass!("clear", Calls, "type_checker/calls/01_resolve").initializer();
pub(in crate::type_checker) const CALLS_ENTRYPOINT_CLEAR: ReflectedComputeSpec = call_pass!(
    "entrypoints.clear",
    Tokens,
    "type_checker/calls/01a_clear_entrypoints"
)
.initializer();
pub(in crate::type_checker) const CALLS_RETURN_REFS: ReflectedComputeSpec = call_pass!(
    "return_refs",
    HirNodes,
    "type_checker/calls/02a_return_refs_from_hir"
)
.with_modes(RETURN_OUTPUTS)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ENTRYPOINT_PROJECT: ReflectedComputeSpec = call_pass!(
    "entrypoints.project",
    HirNodes,
    "type_checker/calls/02b_entrypoints"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_FUNCTIONS: ReflectedComputeSpec =
    call_pass!("functions", HirNodes, "type_checker/calls/02_functions")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_PARAM_TYPES: ReflectedComputeSpec = call_pass!(
    "param_types",
    Declarations,
    "type_checker/calls/02f_params_from_hir"
)
.with_modes(PARAM_TYPE_OUTPUTS);
pub(in crate::type_checker) const CALLS_PARAM_SCATTER: ReflectedComputeSpec = call_pass!(
    "params.scatter",
    Declarations,
    "type_checker/calls/02i_scatter_compact_hir_params"
)
.with_modes(PARAM_SCATTER_OUTPUTS);
pub(in crate::type_checker) const CALLS_INTRINSICS: ReflectedComputeSpec =
    call_pass!("intrinsics", HirNodes, "type_checker/calls/02c_intrinsics")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_CLEAR: ReflectedComputeSpec = call_pass!(
    "arguments.clear",
    CallArguments,
    "type_checker/calls/02d_clear_hir_call_args"
)
.initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_PACK: ReflectedComputeSpec = call_pass!(
    "arguments.pack",
    CallArguments,
    "type_checker/calls/02e_pack_hir_call_args"
)
.initializer();
const CALLS_ARGUMENT_MARK: ReflectedComputeSpec = call_pass!(
    "arg_rows.mark",
    HirNodes,
    "type_checker/calls/02g_mark_compact_hir_call_args"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
const CALLS_ARGUMENT_SCATTER: ReflectedComputeSpec = call_pass!(
    "arg_rows.scatter",
    HirNodes,
    "type_checker/calls/02h_scatter_compact_hir_call_args"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALL_ARGUMENT_COMPACTION: CompactionSpec = CompactionSpec {
    mark: CALLS_ARGUMENT_MARK,
    scan: super::super::compiler_graph::CALL_ARG_ROW_SCAN,
    scatter: CALLS_ARGUMENT_SCATTER,
};
pub(in crate::type_checker) const CALLS_RESOLVE: ReflectedComputeSpec =
    call_pass!("resolve", HirNodes, "type_checker/calls/03_resolve")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_INITIALIZE: ReflectedComputeSpec =
    call_pass!(
        "arg_match.init",
        CallArguments,
        "type_checker/calls/03a0_match_arg_params_init"
    )
    .initializer()
    .with_name("type_check.calls.arg_match.direct.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_CONSUME: ReflectedComputeSpec = call_pass!(
    "arg_match.consume",
    CallArguments,
    "type_checker/calls/03a_collect_row_args"
)
.with_modes(ARGUMENT_MATCH_OUTPUTS)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_name("type_check.calls.arg_match.direct.consume");
pub(in crate::type_checker) const CALLS_APPLY_ARGUMENTS: ReflectedComputeSpec = call_pass!(
    "arguments.apply",
    HirNodes,
    "type_checker/calls/03a_apply_row_args"
)
.with_name("type_check.calls.arguments.apply.direct")
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_MODULE_INITIALIZE: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_INITIALIZE.with_name("type_check.calls.arg_match.module_values.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_MODULE_CONSUME: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_CONSUME.with_name("type_check.calls.arg_match.module_values.consume");
pub(in crate::type_checker) const CALLS_APPLY_MODULE_ARGUMENTS: ReflectedComputeSpec =
    CALLS_APPLY_ARGUMENTS.with_name("type_check.calls.arguments.apply.module_values");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_METHOD_RESULT_INITIALIZE:
    ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_INITIALIZE.with_name("type_check.calls.arg_match.method_results.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_METHOD_RESULT_CONSUME: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_CONSUME.with_name("type_check.calls.arg_match.method_results.consume");
pub(in crate::type_checker) const CALLS_APPLY_METHOD_RESULT_ARGUMENTS: ReflectedComputeSpec =
    CALLS_APPLY_ARGUMENTS.with_name("type_check.calls.arguments.apply.method_results");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_METHOD_MODULE_INITIALIZE:
    ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_INITIALIZE.with_name("type_check.calls.arg_match.method_modules.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_METHOD_MODULE_CONSUME: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_CONSUME.with_name("type_check.calls.arg_match.method_modules.consume");
pub(in crate::type_checker) const CALLS_APPLY_METHOD_MODULE_ARGUMENTS: ReflectedComputeSpec =
    CALLS_APPLY_ARGUMENTS.with_name("type_check.calls.arguments.apply.method_modules");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_FINAL_INITIALIZE: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_INITIALIZE.with_name("type_check.calls.arg_match.final.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_FINAL_CONSUME: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_CONSUME.with_name("type_check.calls.arg_match.final.consume");
pub(in crate::type_checker) const CALLS_APPLY_FINAL_ARGUMENTS: ReflectedComputeSpec =
    CALLS_APPLY_ARGUMENTS.with_name("type_check.calls.arguments.apply.final");
pub(in crate::type_checker) const CALLS_RESULT_INSTANCE_PROJECT: ReflectedComputeSpec = call_pass!(
    "result_instances.project",
    HirNodes,
    "type_checker/calls/03e_project_result_instances"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARRAY_STATE_PUBLISH: ReflectedComputeSpec = call_pass!(
    "array_state.publish",
    CallArguments,
    "type_checker/calls/03d_mark_array_args"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_CLEAR: ReflectedComputeSpec = call_pass!(
    "generic_claims.aggregate_clear",
    HirNodes,
    "type_checker/calls/03a4a_clear_generic_claim_type_args"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_EMIT: ReflectedComputeSpec = call_pass!(
    "generic_claims.emit",
    CallArguments,
    "type_checker/calls/03a1_emit_generic_claims"
)
.with_modes(GENERIC_CLAIM_OUTPUTS)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_INDEX_CLEAR: ReflectedComputeSpec =
    call_pass!(
        "generic_claims.index.clear",
        CallArguments,
        "type_checker/calls/03a2_clear_claim_lookup"
    )
    .with_aliases(&[
        typecheck_resource!("claim_count_in" => "call_generic_claim_count_out", Read),
        typecheck_resource!("claim_lookup_head" => "call_generic_claim_lookup_head", Write),
    ])
    .with_indirect_dispatch("call_generic_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_INDEX_BUILD: ReflectedComputeSpec =
    call_pass!(
        "generic_claims.index.build",
        CallArguments,
        "type_checker/calls/03a3_build_claim_lookup"
    )
    .with_aliases(&[
        typecheck_resource!("claim_count_in" => "call_generic_claim_count_out", Read),
        typecheck_resource!("claim_callee" => "call_generic_claim_callee", Read),
        typecheck_resource!("claim_slot" => "call_generic_claim_slot", Read),
        typecheck_resource!("claim_lookup_head" => "call_generic_claim_lookup_head", ReadWrite),
        typecheck_resource!("claim_lookup_next" => "call_generic_claim_lookup_next", Write),
    ])
    .with_indirect_dispatch("call_generic_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_VALIDATE: ReflectedComputeSpec = call_pass!(
    "generic_claims.validate",
    CallArguments,
    "type_checker/calls/03a4_validate_generic_claims"
)
.with_indirect_dispatch("call_generic_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONTEXTUAL_RESULT_REQUESTS: ReflectedComputeSpec =
    call_pass!(
        "contextual_result_requests",
        HirNodes,
        "type_checker/calls/03a4b_contextual_result_requests"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_CONTEXTUAL_RESULTS_FINAL: ReflectedComputeSpec =
    CALLS_CONTEXTUAL_RESULT_REQUESTS.with_name("type_check.calls.contextual_results.final");
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_MARK: ReflectedComputeSpec = call_pass!(
    "required_generics.mark",
    HirNodes,
    "type_checker/calls/03a6_mark_required_generics"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_VALIDATE: ReflectedComputeSpec =
    call_pass!(
        "required_generics.validate",
        CallArguments,
        "type_checker/calls/03a7_validate_required_generics"
    )
    .with_indirect_dispatch("call_required_generic_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_VALIDATE: ReflectedComputeSpec = call_pass!(
    "const_claims.validate",
    CallArguments,
    "type_checker/calls/03a5_validate_const_claims"
)
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_INDEX_CLEAR: ReflectedComputeSpec = call_pass!(
    "const_claims.index.clear",
    CallArguments,
    "type_checker/calls/03a2_clear_claim_lookup"
)
.with_aliases(&[
    typecheck_resource!("claim_count_in" => "call_const_claim_count_out", Read),
    typecheck_resource!("claim_lookup_head" => "call_const_claim_lookup_head", Write),
])
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_INDEX_BUILD: ReflectedComputeSpec = call_pass!(
    "const_claims.index.build",
    CallArguments,
    "type_checker/calls/03a3_build_claim_lookup"
)
.with_aliases(&[
    typecheck_resource!("claim_count_in" => "call_const_claim_count_out", Read),
    typecheck_resource!("claim_callee" => "call_const_claim_callee", Read),
    typecheck_resource!("claim_slot" => "call_const_claim_slot", Read),
    typecheck_resource!("claim_lookup_head" => "call_const_claim_lookup_head", ReadWrite),
    typecheck_resource!("claim_lookup_next" => "call_const_claim_lookup_next", Write),
])
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_ARRAY_STATE_CONSUME: ReflectedComputeSpec = call_pass!(
    "array_state.consume",
    HirNodes,
    "type_checker/calls/03c_validate_array_results"
);

pub(in crate::type_checker) const CALLS_GENERIC_PARAMS_ERASE: ReflectedComputeSpec = call_pass!(
    "erase_generic_params",
    Tokens,
    "type_checker/calls/04_erase_generic_params"
);

// Own-header bindings precede call inference; the final boundary validates
// their agreement with accepted values and receiving contexts.
pub(in crate::type_checker) const CALLS_EXPLICIT_APPLICATIONS_BIND: ReflectedComputeSpec =
    call_pass!("explicit_applications.bind", HirNodes,
        "type_checker/calls/03a0_bind_explicit_applications")
        // Rows are write-only here. The initialized descriptor publishes the
        // valid subset; unpublished arena cells are never read by consumers.
        .with_modes(&[
            ("call_explicit_binding_tag", AccessMode::Write),
            ("call_explicit_binding_payload", AccessMode::Write),
        ])
        .with_indirect_dispatch("explicit_application_dispatch_args");
pub(in crate::type_checker) const CALLS_EXPLICIT_APPLICATIONS_BIND_INFERENCE: ReflectedComputeSpec =
    CALLS_EXPLICIT_APPLICATIONS_BIND.with_name("type_check.calls.explicit_applications.bind.inference");
pub(in crate::type_checker) const CALLS_EXPLICIT_APPLICATIONS_VALIDATE: ReflectedComputeSpec =
    call_pass!("explicit_applications.validate", HirNodes,
        "type_checker/calls/03a8_validate_explicit_applications")
        .with_indirect_dispatch("explicit_application_dispatch_args");

// Bound-directed generic call inference (calls/03l*), recorded in each
// inference round after the dependency result passes.
pub(in crate::type_checker) const CALLS_BOUND_TABLES_CLEAR: ReflectedComputeSpec = call_pass!(
    "bound_inference.clear",
    Calls,
    "type_checker/calls/03l0_clear_bound_tables"
)
.initializer();
pub(in crate::type_checker) const CALLS_BOUND_DEPENDENCY_COLLECT: ReflectedComputeSpec = call_pass!(
    "bound_inference.collect_dependency",
    Calls,
    "type_checker/calls/03l1_collect_dependency_bounds"
)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
]);
pub(in crate::type_checker) const CALLS_BOUND_LOCAL_COLLECT: ReflectedComputeSpec = call_pass!(
    "bound_inference.collect_local",
    HirNodes,
    "type_checker/calls/03l2_collect_local_implementations"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_BOUND_INFER: ReflectedComputeSpec = call_pass!(
    "bound_inference.infer",
    HirNodes,
    "type_checker/calls/03l3_infer_bound_generics"
)
.with_modes(&[
    ("type_native_word_count", AccessMode::Write),
    ("type_native_scalar_identity", AccessMode::Write),
])
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_indirect_dispatch("hir_active_dispatch_args");
