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
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.lookup");
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_AGGREGATE_VALIDATION:
    ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.aggregate_validation");
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS_CONDITION_FINALIZATION:
    ReflectedComputeSpec =
    METHODS_MARK_CALL_KEYS.with_name("type_check.methods.mark_call_keys.condition_finalization");
pub(in crate::type_checker) const METHODS_MARK_CALL_RETURN_KEYS: ReflectedComputeSpec =
    method_pass!(
        "mark_call_return_keys",
        HirNodes,
        "type_checker/methods/06b_mark_call_return_keys"
    )
    .with_indirect_dispatch("method_hir_dispatch_args");
pub(in crate::type_checker) const METHODS_RESOLVE_TABLE: ReflectedComputeSpec = method_pass!(
    "resolve_table",
    Calls,
    "type_checker/methods/07_resolve_table"
)
.with_indirect_dispatch("method_token_dispatch_args");
pub(in crate::type_checker) const METHODS_RESOLVE: ReflectedComputeSpec =
    method_pass!("resolve", HirNodes, "type_checker/methods/03/resolve")
        .with_indirect_dispatch("method_token_hir_dispatch_args");
