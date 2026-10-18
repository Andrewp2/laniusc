use crate::gpu::compiler_graph::{AccessMode, ReflectedComputeSpec};

macro_rules! method_pass {
    ($suffix:literal, $domain:ident, $kernel:literal) => {
        typecheck_pass!(concat!("type_check.methods.", $suffix), $domain, $kernel)
    };
}

const METHOD_CLEAR_OUTPUTS: &[(&str, AccessMode)] = &[
    ("method_decl_receiver_ref_tag", AccessMode::Write),
    ("method_decl_receiver_ref_payload", AccessMode::Write),
    ("method_decl_module_id", AccessMode::Write),
    ("method_decl_method_row", AccessMode::Write),
    ("method_decl_name_token", AccessMode::Write),
    ("method_decl_name_id", AccessMode::Write),
    ("method_decl_param_offset", AccessMode::Write),
    ("method_decl_receiver_mode", AccessMode::Write),
    ("method_decl_visibility", AccessMode::Write),
    ("method_decl_signature_flags", AccessMode::Write),
    ("method_candidate", AccessMode::Write),
    ("method_call_source_ref_tag", AccessMode::Write),
    ("method_call_source_ref_payload", AccessMode::Write),
    ("method_call_selection_owned", AccessMode::Write),
    ("method_call_parameter_ref_tag", AccessMode::Write),
    ("method_call_parameter_ref_payload", AccessMode::Write),
    ("method_call_receiver_hir", AccessMode::Write),
    ("method_call_receiver_ref_tag", AccessMode::Write),
    ("method_call_receiver_ref_payload", AccessMode::Write),
    ("method_call_name_id", AccessMode::Write),
    ("method_call_site_module_id", AccessMode::Write),
];

pub(in crate::type_checker) const METHODS_CLEAR: ReflectedComputeSpec =
    method_pass!("clear", Tokens, "type_checker/methods/01_clear")
        .with_modes(METHOD_CLEAR_OUTPUTS)
        .with_indirect_dispatch("token_active_dispatch_args");
pub(in crate::type_checker) const METHODS_COLLECT: ReflectedComputeSpec =
    method_pass!("collect", Declarations, "type_checker/methods/02_collect")
        .with_indirect_dispatch("method_compact_dispatch_args");
pub(in crate::type_checker) const METHODS_ATTACH_METADATA: ReflectedComputeSpec = method_pass!(
    "attach_metadata",
    Declarations,
    "type_checker/methods/02b_attach_metadata"
)
.with_indirect_dispatch("method_compact_dispatch_args");
pub(in crate::type_checker) const METHODS_BIND_SELF_RECEIVERS: ReflectedComputeSpec = method_pass!(
    "bind_self_receivers",
    HirNodes,
    "type_checker/methods/02c_bind_self_receivers"
)
.with_indirect_dispatch("method_hir_dispatch_args");
pub(in crate::type_checker) const METHODS_LOOKUP_CLEAR: ReflectedComputeSpec = method_pass!(
    "lookup.clear",
    Declarations,
    "type_checker/methods/03_clear_lookup"
)
.initializer()
.with_indirect_dispatch("method_compact_dispatch_args");
pub(in crate::type_checker) const METHODS_LOOKUP_BUILD: ReflectedComputeSpec = method_pass!(
    "lookup.build",
    Declarations,
    "type_checker/methods/03_build_lookup"
)
.with_modes(&[
    ("method_lookup_head", AccessMode::ReadWrite),
    ("method_lookup_next", AccessMode::Write),
])
.with_indirect_dispatch("method_compact_dispatch_args");
pub(in crate::type_checker) const METHODS_VALIDATE_KEYS: ReflectedComputeSpec = method_pass!(
    "lookup.validate",
    Declarations,
    "type_checker/methods/05_validate_keys"
)
.with_modes(&[
    ("method_key_status", AccessMode::Write),
    ("method_key_duplicate_of", AccessMode::Write),
    ("status", AccessMode::ReadWrite),
])
.with_indirect_dispatch("method_compact_dispatch_args");
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS: ReflectedComputeSpec = method_pass!(
    "mark_call_keys",
    HirNodes,
    "type_checker/methods/06_mark_call_keys"
)
.with_name("type_check.methods.mark_call_keys.direct")
.with_indirect_dispatch("method_token_hir_dispatch_args");
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_LOOKUP: ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS
        .with_name("type_check.methods.mark_call_keys.lookup")
        .with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_AGGREGATE_VALIDATION:
    ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.aggregate_validation");
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_CONDITION_FINALIZATION:
    ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.condition_finalization");
const MARK_CALL_RETURN_KEYS: ReflectedComputeSpec = method_pass!(
    "mark_call_return_keys",
    HirNodes,
    "type_checker/methods/06b_mark_call_return_keys"
)
.with_indirect_dispatch("method_hir_dispatch_args");
// Reset is per transaction, after source producers; it preserves the accepted
// result and selection ownership. Only the per-job clear initializes ownership.
const RESET_CANDIDATES: ReflectedComputeSpec =
    method_pass!("reset_candidates", Calls, "type_checker/methods/06c_reset_candidates")
        .with_indirect_dispatch("method_token_dispatch_args");
const FINALIZE_CANDIDATES: ReflectedComputeSpec =
    method_pass!("finalize_candidates", Calls, "type_checker/methods/08_finalize_candidates")
        .with_indirect_dispatch("method_token_dispatch_args");
// This operation only contributes local candidates; finalization publishes.
const RESOLVE_TABLE: ReflectedComputeSpec =
    method_pass!("resolve_table", Calls, "type_checker/methods/07_resolve_table")
        .with_indirect_dispatch("method_token_dispatch_args");
// Required members reached through a lexical `P: Trait` bound compete in the
// same transaction, after local table candidates and before dependency pages.
// One lane per call expression: the call owns the trait arguments' context.
const OFFER_BOUND_MEMBERS: ReflectedComputeSpec = method_pass!(
    "offer_bound_members",
    HirNodes,
    "type_checker/methods/07a_offer_bound_members"
)
.with_indirect_dispatch("method_hir_dispatch_args");

// The eight preliminary lookup sweeps dispatch from one gated copy of the
// method grids (see methods/08b_arm_lookup_sweeps): the method-token grid, the
// method-HIR grid, the token-or-HIR grid and the active-HIR grid, in that
// order, then the change count of the last sweep that changed a target.
pub(in crate::type_checker) const METHOD_LOOKUP_DISPATCH_ARGS: &str = "method_lookup_dispatch_args";
pub(in crate::type_checker) const METHOD_LOOKUP_TOKEN_ARGS_OFFSET: u64 = 0;
pub(in crate::type_checker) const METHOD_LOOKUP_HIR_ARGS_OFFSET: u64 = 12;
pub(in crate::type_checker) const METHOD_LOOKUP_TOKEN_HIR_ARGS_OFFSET: u64 = 24;
pub(in crate::type_checker) const METHOD_LOOKUP_ACTIVE_HIR_ARGS_OFFSET: u64 = 36;
pub(in crate::type_checker) const METHOD_LOOKUP_DISPATCH_ARGS_BYTES: u64 = 52;
pub(in crate::type_checker) const METHODS_ARM_LOOKUP_SWEEPS: ReflectedComputeSpec = method_pass!(
    "lookup_sweeps.arm",
    DispatchArguments,
    "type_checker/methods/08b_arm_lookup_sweeps"
)
.initializer();
pub(in crate::type_checker) const METHODS_GATE_LOOKUP_SWEEP: ReflectedComputeSpec = method_pass!(
    "lookup_sweeps.gate",
    DispatchArguments,
    "type_checker/methods/08c_gate_lookup_sweep"
);
pub(in crate::type_checker) const METHODS_MARK_CALL_RETURN_KEYS: ReflectedComputeSpec =
    MARK_CALL_RETURN_KEYS.with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_RESET_CANDIDATES: ReflectedComputeSpec =
    RESET_CANDIDATES.with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_FINALIZE_CANDIDATES: ReflectedComputeSpec =
    FINALIZE_CANDIDATES.with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_RESOLVE_TABLE: ReflectedComputeSpec =
    RESOLVE_TABLE.with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_OFFER_BOUND_MEMBERS: ReflectedComputeSpec =
    OFFER_BOUND_MEMBERS.with_indirect_dispatch(METHOD_LOOKUP_DISPATCH_ARGS);
pub(in crate::type_checker) const METHODS_RESOLVE: ReflectedComputeSpec =
    method_pass!("resolve", HirNodes, "type_checker/methods/03/resolve")
        .with_indirect_dispatch("method_token_hir_dispatch_args");

// Method targets depend on inferred call results and unannotated bindings.
// These invocations participate in the same convergence region as those facts.
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_INFERENCE: ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.inference");
pub(in crate::type_checker) const METHODS_MARK_CALL_RETURN_KEYS_INFERENCE: ReflectedComputeSpec =
    MARK_CALL_RETURN_KEYS.with_name("type_check.methods.mark_call_return_keys.inference");
pub(in crate::type_checker) const METHODS_RESOLVE_TABLE_INFERENCE: ReflectedComputeSpec =
    RESOLVE_TABLE.with_name("type_check.methods.resolve_table.inference");
pub(in crate::type_checker) const METHODS_OFFER_BOUND_MEMBERS_INFERENCE: ReflectedComputeSpec =
    OFFER_BOUND_MEMBERS.with_name("type_check.methods.offer_bound_members.inference");
pub(in crate::type_checker) const METHODS_RESOLVE_INFERENCE: ReflectedComputeSpec =
    METHODS_RESOLVE.with_name("type_check.methods.resolve.inference");

// Initial selection and inference are distinct graph invocations of the same
// transaction. The unqualified operations own the eight preliminary sweeps.
pub(in crate::type_checker) const METHODS_MARK_CALL_RETURN_KEYS_DIRECT: ReflectedComputeSpec =
    MARK_CALL_RETURN_KEYS.with_name("type_check.methods.mark_call_return_keys.direct");
pub(in crate::type_checker) const METHODS_RESET_CANDIDATES_DIRECT: ReflectedComputeSpec =
    RESET_CANDIDATES.with_name("type_check.methods.reset_candidates.direct");
pub(in crate::type_checker) const METHODS_RESOLVE_TABLE_DIRECT: ReflectedComputeSpec =
    RESOLVE_TABLE.with_name("type_check.methods.resolve_table.direct");
pub(in crate::type_checker) const METHODS_OFFER_BOUND_MEMBERS_DIRECT: ReflectedComputeSpec =
    OFFER_BOUND_MEMBERS.with_name("type_check.methods.offer_bound_members.direct");
pub(in crate::type_checker) const METHODS_FINALIZE_CANDIDATES_DIRECT: ReflectedComputeSpec =
    FINALIZE_CANDIDATES.with_name("type_check.methods.finalize_candidates.direct");
pub(in crate::type_checker) const METHODS_RESET_CANDIDATES_INFERENCE: ReflectedComputeSpec =
    RESET_CANDIDATES.with_name("type_check.methods.reset_candidates.inference");
pub(in crate::type_checker) const METHODS_FINALIZE_CANDIDATES_INFERENCE: ReflectedComputeSpec =
    FINALIZE_CANDIDATES.with_name("type_check.methods.finalize_candidates.inference");
