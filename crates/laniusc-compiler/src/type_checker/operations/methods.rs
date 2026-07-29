use crate::gpu::compiler_graph::{
    AccessMode,
    CompilerPhase,
    ReflectedComputeSpec,
    ReflectedResourceAlias,
    ResourceDomain,
};

macro_rules! method_pass {
    ($suffix:literal, $domain:ident, $kernel:literal) => {
        ReflectedComputeSpec::new(
            concat!("type_check.methods.", $suffix),
            $kernel,
            CompilerPhase::TypeCheck,
            ResourceDomain::$domain,
        )
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
    method_pass!("clear", Tokens, "type_checker/methods/01_clear").with_modes(METHOD_CLEAR_OUTPUTS);
pub(in crate::type_checker) const METHODS_COLLECT: ReflectedComputeSpec =
    method_pass!("collect", Declarations, "type_checker/methods/02_collect");
pub(in crate::type_checker) const METHODS_ATTACH_METADATA: ReflectedComputeSpec = method_pass!(
    "attach_metadata",
    Declarations,
    "type_checker/methods/02b_attach_metadata"
);
pub(in crate::type_checker) const METHODS_BIND_SELF_RECEIVERS: ReflectedComputeSpec = method_pass!(
    "bind_self_receivers",
    HirNodes,
    "type_checker/methods/02c_bind_self_receivers"
);
pub(in crate::type_checker) const METHODS_MARK_CALL_KEYS: ReflectedComputeSpec = method_pass!(
    "mark_call_keys",
    HirNodes,
    "type_checker/methods/06_mark_call_keys"
);
pub(in crate::type_checker) const METHODS_MARK_CALL_RETURN_KEYS: ReflectedComputeSpec = method_pass!(
    "mark_call_return_keys",
    HirNodes,
    "type_checker/methods/06b_mark_call_return_keys"
);
pub(in crate::type_checker) const METHODS_RESOLVE_TABLE: ReflectedComputeSpec = method_pass!(
    "resolve_table",
    Calls,
    "type_checker/methods/07_resolve_table"
)
.with_aliases(&[ReflectedResourceAlias {
    binding: "sorted_method_key_order",
    resource: "method_key_to_fn_token",
    mode: Some(AccessMode::Read),
}]);
pub(in crate::type_checker) const METHODS_RESOLVE: ReflectedComputeSpec =
    method_pass!("resolve", HirNodes, "type_checker/methods/03/resolve");
