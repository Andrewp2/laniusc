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
    ("call_generic_claim_callee", AccessMode::Write),
    ("call_generic_claim_slot", AccessMode::Write),
    ("call_generic_claim_type", AccessMode::Write),
    ("call_generic_claim_ref_tag", AccessMode::Write),
    ("call_generic_claim_ref_payload", AccessMode::Write),
    ("call_const_claim_callee", AccessMode::Write),
    ("call_const_claim_slot", AccessMode::Write),
    ("call_const_claim_len", AccessMode::Write),
];
const GENERIC_CLAIM_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_generic_claim_callee", AccessMode::Write),
    ("call_generic_claim_slot", AccessMode::Write),
    ("call_generic_claim_type", AccessMode::Write),
    ("call_generic_claim_ref_tag", AccessMode::Write),
    ("call_generic_claim_ref_payload", AccessMode::Write),
    ("call_generic_claim_arg_row", AccessMode::Write),
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
.with_modes(GENERIC_CLAIM_OUTPUTS);
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
    typecheck_resource!("claim_count_in" => "call_arg_row_count_out", Read),
    typecheck_resource!("claim_lookup_head" => "call_const_claim_lookup_head", Write),
])
.with_indirect_dispatch("call_const_claim_index_dispatch_args");
pub(in crate::type_checker) const CALLS_CONST_CLAIM_INDEX_BUILD: ReflectedComputeSpec = call_pass!(
    "const_claims.index.build",
    CallArguments,
    "type_checker/calls/03a3_build_claim_lookup"
)
.with_aliases(&[
    typecheck_resource!("claim_count_in" => "call_arg_row_count_out", Read),
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
