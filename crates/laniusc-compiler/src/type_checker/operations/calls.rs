use crate::gpu::compiler_graph::{AccessMode, CompilerPhase, ReflectedComputeSpec, ResourceDomain};

macro_rules! call_pass {
    ($suffix:literal, $domain:ident) => {
        ReflectedComputeSpec::new(
            concat!("type_check.calls.", $suffix),
            CompilerPhase::TypeCheck,
            ResourceDomain::$domain,
        )
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
    ("call_generic_claim_order", AccessMode::Write),
    ("call_const_claim_callee", AccessMode::Write),
    ("call_const_claim_slot", AccessMode::Write),
    ("call_const_claim_len", AccessMode::Write),
    ("call_const_claim_order", AccessMode::Write),
];
const GENERIC_CLAIM_OUTPUTS: &[(&str, AccessMode)] = &[
    ("call_generic_claim_callee", AccessMode::Write),
    ("call_generic_claim_slot", AccessMode::Write),
    ("call_generic_claim_type", AccessMode::Write),
    ("call_generic_claim_ref_tag", AccessMode::Write),
    ("call_generic_claim_ref_payload", AccessMode::Write),
    ("call_generic_claim_arg_row", AccessMode::Write),
    ("call_generic_claim_order", AccessMode::Write),
];

pub(in crate::type_checker) const CALLS_CLEAR: ReflectedComputeSpec =
    call_pass!("clear", Calls).initializer();
pub(in crate::type_checker) const CALLS_ENTRYPOINT_CLEAR: ReflectedComputeSpec =
    call_pass!("entrypoints.clear", Tokens).initializer();
pub(in crate::type_checker) const CALLS_RETURN_REFS: ReflectedComputeSpec =
    call_pass!("return_refs", HirNodes).with_modes(RETURN_OUTPUTS);
pub(in crate::type_checker) const CALLS_ENTRYPOINT_PROJECT: ReflectedComputeSpec =
    call_pass!("entrypoints.project", HirNodes);
pub(in crate::type_checker) const CALLS_FUNCTIONS: ReflectedComputeSpec =
    call_pass!("functions", HirNodes);
pub(in crate::type_checker) const CALLS_PARAM_TYPES: ReflectedComputeSpec =
    call_pass!("param_types", Declarations).with_modes(PARAM_TYPE_OUTPUTS);
pub(in crate::type_checker) const CALLS_PARAM_SCATTER: ReflectedComputeSpec =
    call_pass!("params.scatter", Declarations).with_modes(PARAM_SCATTER_OUTPUTS);
pub(in crate::type_checker) const CALLS_INTRINSICS: ReflectedComputeSpec =
    call_pass!("intrinsics", HirNodes);
pub(in crate::type_checker) const CALLS_ARGUMENT_CLEAR: ReflectedComputeSpec =
    call_pass!("arguments.clear", CallArguments).initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_PACK: ReflectedComputeSpec =
    call_pass!("arguments.pack", CallArguments).initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_MARK: ReflectedComputeSpec =
    call_pass!("arg_rows.mark", HirNodes).initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_SCATTER: ReflectedComputeSpec =
    call_pass!("arg_rows.scatter", HirNodes).initializer();
pub(in crate::type_checker) const CALLS_RESOLVE: ReflectedComputeSpec =
    call_pass!("resolve", HirNodes);
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_INITIALIZE: ReflectedComputeSpec =
    call_pass!("arg_match.init", CallArguments).initializer();
pub(in crate::type_checker) const CALLS_ARGUMENT_MATCH_CONSUME: ReflectedComputeSpec =
    call_pass!("arg_match.consume", CallArguments).with_modes(ARGUMENT_MATCH_OUTPUTS);
pub(in crate::type_checker) const CALLS_APPLY_ARGUMENTS: ReflectedComputeSpec =
    call_pass!("arguments.apply", HirNodes);
pub(in crate::type_checker) const CALLS_RESULT_INSTANCE_PROJECT: ReflectedComputeSpec =
    call_pass!("result_instances.project", HirNodes);
pub(in crate::type_checker) const CALLS_ARRAY_STATE_PUBLISH: ReflectedComputeSpec =
    call_pass!("array_state.publish", CallArguments);
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_CLEAR: ReflectedComputeSpec =
    call_pass!("generic_claims.aggregate_clear", HirNodes).initializer();
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_EMIT: ReflectedComputeSpec =
    call_pass!("generic_claims.emit", CallArguments).with_modes(GENERIC_CLAIM_OUTPUTS);
pub(in crate::type_checker) const CALLS_GENERIC_CLAIM_VALIDATE: ReflectedComputeSpec =
    call_pass!("generic_claims.validate", CallArguments);
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_MARK: ReflectedComputeSpec =
    call_pass!("required_generics.mark", HirNodes).initializer();
pub(in crate::type_checker) const CALLS_REQUIRED_GENERIC_VALIDATE: ReflectedComputeSpec =
    call_pass!("required_generics.validate", CallArguments);
pub(in crate::type_checker) const CALLS_CONST_CLAIM_VALIDATE: ReflectedComputeSpec =
    call_pass!("const_claims.validate", CallArguments);
pub(in crate::type_checker) const CALLS_ARRAY_STATE_CONSUME: ReflectedComputeSpec =
    call_pass!("array_state.consume", HirNodes);
