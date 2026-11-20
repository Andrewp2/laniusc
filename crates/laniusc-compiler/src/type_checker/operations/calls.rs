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
    call_pass!("clear", Calls, "type_checker/calls/signatures/clear_call_resolution_state").initializer();
pub(in crate::type_checker) const CALLS_ENTRYPOINT_CLEAR: ReflectedComputeSpec = call_pass!(
    "entrypoints.clear",
    Tokens,
    "type_checker/calls/signatures/clear_function_entrypoints"
)
.initializer();
pub(in crate::type_checker) const CALLS_RETURN_REFS: ReflectedComputeSpec = call_pass!(
    "return_refs",
    HirNodes,
    "type_checker/calls/signatures/project_hir_return_references"
)
.with_modes(RETURN_OUTPUTS)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ENTRYPOINT_PROJECT: ReflectedComputeSpec = call_pass!(
    "entrypoints.project",
    HirNodes,
    "type_checker/calls/signatures/mark_function_entrypoints"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_FUNCTIONS: ReflectedComputeSpec =
    call_pass!("functions", HirNodes, "type_checker/calls/signatures/project_hir_functions")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_PARAM_TYPES: ReflectedComputeSpec = call_pass!(
    "param_types",
    Declarations,
    "type_checker/calls/signatures/project_hir_function_parameters"
)
.with_modes(PARAM_TYPE_OUTPUTS);
pub(in crate::type_checker) const CALLS_PARAM_SCATTER: ReflectedComputeSpec = call_pass!(
    "params.scatter",
    Declarations,
    "type_checker/calls/signatures/scatter_compact_hir_params"
)
.with_modes(PARAM_SCATTER_OUTPUTS);
pub(in crate::type_checker) const CALLS_INTRINSICS: ReflectedComputeSpec =
    call_pass!("intrinsics", HirNodes, "type_checker/calls/signatures/bind_intrinsic_declarations")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_CLEAR: ReflectedComputeSpec = call_pass!(
    "arguments.clear",
    CallArguments,
    "type_checker/calls/arguments/clear_hir_call_args"
)
.initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_PACK: ReflectedComputeSpec = call_pass!(
    "arguments.pack",
    CallArguments,
    "type_checker/calls/arguments/pack_hir_call_args"
)
.initializer();
const CALLS_ARGUMENT_MARK: ReflectedComputeSpec = call_pass!(
    "arg_rows.mark",
    HirNodes,
    "type_checker/calls/arguments/mark_compact_hir_call_args"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
const CALLS_ARGUMENT_SCATTER: ReflectedComputeSpec = call_pass!(
    "arg_rows.scatter",
    HirNodes,
    "type_checker/calls/arguments/scatter_compact_hir_call_args"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALL_ARGUMENT_COMPACTION: CompactionSpec = CompactionSpec {
    mark: CALLS_ARGUMENT_MARK,
    scan: super::super::compiler_graph::CALL_ARG_ROW_SCAN,
    scatter: CALLS_ARGUMENT_SCATTER,
};
pub(in crate::type_checker) const CALLS_RESOLVE: ReflectedComputeSpec =
    call_pass!("resolve", HirNodes, "type_checker/calls/resolve_direct_calls")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_INITIALIZE: ReflectedComputeSpec =
    call_pass!(
        "arg_match.init",
        CallArguments,
        "type_checker/calls/arguments/match_call_arguments_to_parameters"
    )
    .initializer()
    .with_name("type_check.calls.arg_match.direct.init");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_CONSUME: ReflectedComputeSpec = call_pass!(
    "arg_match.consume",
    CallArguments,
    "type_checker/calls/inference/collect_call_argument_constraints"
)
.with_modes(ARGUMENT_MATCH_OUTPUTS)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_name("type_check.calls.arg_match.direct.consume");
pub(in crate::type_checker) const CALLS_APPLY_ARGUMENTS: ReflectedComputeSpec = call_pass!(
    "arguments.apply",
    HirNodes,
    "type_checker/calls/inference/apply_call_argument_inference"
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
    CALLS_ARGUMENT_MATCH_INITIALIZE.with_name("type_check.calls.arg_match.final.init")
        .with_indirect_dispatch("inference_arg_list_args");
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_FINAL_CONSUME: ReflectedComputeSpec =
    CALLS_ARGUMENT_MATCH_CONSUME.with_name("type_check.calls.arg_match.final.consume")
        .with_indirect_dispatch("inference_arg_list_args");
/// The rounds' application visits the listed active blocks
/// (calls/inference_blocks.slang).
pub(in crate::type_checker) const CALLS_APPLY_FINAL_ARGUMENTS: ReflectedComputeSpec =
    CALLS_APPLY_ARGUMENTS
        .with_name("type_check.calls.arguments.apply.final")
        .with_indirect_dispatch("inference_hir_list_args");
pub(in crate::type_checker) const CALLS_RESULT_INSTANCE_PROJECT: ReflectedComputeSpec = call_pass!(
    "result_instances.project",
    HirNodes,
    "type_checker/calls/results/project_result_instances"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_ARRAY_STATE_PUBLISH: ReflectedComputeSpec = call_pass!(
    "array_state.publish",
    CallArguments,
    "type_checker/calls/arguments/mark_call_array_arguments"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_CLEAR: ReflectedComputeSpec = call_pass!(
    "generic_claims.aggregate_clear",
    HirNodes,
    "type_checker/calls/claims/clear_generic_claim_type_args"
)
.initializer()
.with_indirect_dispatch("inference_hir_list_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_EMIT: ReflectedComputeSpec = call_pass!(
    "generic_claims.emit",
    CallArguments,
    "type_checker/calls/claims/emit_generic_claims"
)
.with_modes(GENERIC_CLAIM_OUTPUTS)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_indirect_dispatch("inference_full_arg_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_INDEX_BUILD: ReflectedComputeSpec =
    call_pass!(
        "generic_claims.index.build",
        CallArguments,
        "type_checker/calls/claims/build_claim_lookup"
    )
    .with_aliases(&[
        typecheck_resource!("claim_count_in" => "call_generic_claim_count_out", Read),
        typecheck_resource!("claim_callee" => "call_generic_claim_callee", Read),
        typecheck_resource!("claim_slot" => "call_generic_claim_slot", Read),
        typecheck_resource!("claim_lookup_head" => "call_generic_claim_lookup_head", ReadWrite),
        typecheck_resource!("claim_lookup_next" => "call_generic_claim_lookup_next", Write),
        typecheck_resource!("claim_slot_mask" => "call_generic_claim_slot_mask", ReadWrite),
    ])
    .with_indirect_dispatch("call_generic_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_VALIDATE: ReflectedComputeSpec = call_pass!(
    "generic_claims.validate",
    CallArguments,
    "type_checker/calls/claims/validate_generic_claims"
)
.with_indirect_dispatch("call_generic_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONTEXTUAL_RESULT_REQUESTS: ReflectedComputeSpec =
    call_pass!(
        "contextual_result_requests",
        HirNodes,
        "type_checker/calls/claims/request_contextual_call_result_comparisons"
    )
    .with_indirect_dispatch("inference_hir_list_args");
pub(in crate::type_checker) const CALLS_CONTEXTUAL_RESULTS_FINAL: ReflectedComputeSpec =
    CALLS_CONTEXTUAL_RESULT_REQUESTS
        .with_name("type_check.calls.contextual_results.final")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_MARK: ReflectedComputeSpec = call_pass!(
    "required_generics.mark",
    HirNodes,
    "type_checker/calls/claims/mark_required_generics"
)
.initializer()
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_VALIDATE: ReflectedComputeSpec =
    call_pass!(
        "required_generics.validate",
        CallArguments,
        "type_checker/calls/claims/validate_required_generics"
    )
    .with_indirect_dispatch("call_required_generic_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_VALIDATE: ReflectedComputeSpec = call_pass!(
    "const_claims.validate",
    CallArguments,
    "type_checker/calls/claims/validate_const_claims"
)
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_INDEX_BUILD: ReflectedComputeSpec = call_pass!(
    "const_claims.index.build",
    CallArguments,
    "type_checker/calls/claims/build_claim_lookup"
)
.with_aliases(&[
    typecheck_resource!("claim_count_in" => "call_const_claim_count_out", Read),
    typecheck_resource!("claim_callee" => "call_const_claim_callee", Read),
    typecheck_resource!("claim_slot" => "call_const_claim_slot", Read),
    typecheck_resource!("claim_lookup_head" => "call_const_claim_lookup_head", ReadWrite),
    typecheck_resource!("claim_lookup_next" => "call_const_claim_lookup_next", Write),
    typecheck_resource!("claim_slot_mask" => "call_const_claim_slot_mask", ReadWrite),
])
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_ARRAY_STATE_CONSUME: ReflectedComputeSpec = call_pass!(
    "array_state.consume",
    HirNodes,
    "type_checker/calls/results/validate_array_results"
);

pub(in crate::type_checker) const CALLS_GENERIC_PARAMS_ERASE: ReflectedComputeSpec = call_pass!(
    "erase_generic_params",
    Tokens,
    "type_checker/calls/signatures/erase_generic_params"
);

// Own-header bindings precede call inference; the final boundary validates
// their agreement with accepted values and receiving contexts.
pub(in crate::type_checker) const CALLS_EXPLICIT_APPLICATIONS_BIND: ReflectedComputeSpec =
    call_pass!("explicit_applications.bind", HirNodes,
        "type_checker/calls/claims/bind_explicit_applications")
        // Rows are write-only here. The initialized descriptor publishes the
        // valid subset; unpublished arena cells are never read by consumers.
        .with_modes(&[
            ("call_explicit_binding_tag", AccessMode::Write),
            ("call_explicit_binding_payload", AccessMode::Write),
            // validate_explicit_constants reads entries below the listed count.
            ("call_explicit_application_list", AccessMode::Write),
        ])
        .with_indirect_dispatch("inference_explicit_args");
pub(in crate::type_checker) const CALLS_EXPLICIT_APPLICATIONS_VALIDATE: ReflectedComputeSpec =
    call_pass!("explicit_applications.validate", HirNodes,
        "type_checker/calls/claims/validate_explicit_applications")
        .with_indirect_dispatch("explicit_application_dispatch_args");

// Bound-directed generic call inference, recorded in each
// inference round after the dependency result passes.
pub(in crate::type_checker) const CALLS_BOUND_DEPENDENCY_COLLECT: ReflectedComputeSpec = call_pass!(
    "bound_inference.collect_dependency",
    Calls,
    "type_checker/calls/inference/collect_dependency_bounds"
)
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
]);
pub(in crate::type_checker) const CALLS_BOUND_LOCAL_COLLECT: ReflectedComputeSpec = call_pass!(
    "bound_inference.collect_local",
    HirNodes,
    "type_checker/calls/inference/collect_local_implementations"
)
.with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_BOUND_INFER: ReflectedComputeSpec = call_pass!(
    "bound_inference.infer",
    HirNodes,
    "type_checker/calls/inference/infer_bound_generics"
)
.with_modes(&[
    ("type_native_word_count", AccessMode::Write),
    ("type_native_scalar_identity", AccessMode::Write),
])
.with_aliases(&[
    typecheck_resource!("canonical_type_roots" => "call_parameter_canonical_type_roots", Read),
])
.with_indirect_dispatch("inference_hir_list_args");
