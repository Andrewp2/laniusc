use crate::gpu::compiler_graph::{AccessMode, ReflectedComputeSpec};

pub(in crate::type_checker) const VISIBLE_HIR_DECL_MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.visible.mark_hir_decl_names",
    HirNodes,
    "type_checker/visible/03b_mark_hir_decl_names"
)
.with_modes(&[
    ("hir_value_decl_name_present", AccessMode::ReadWrite),
    ("hir_visible_decl_flag", AccessMode::ReadWrite),
    ("hir_visible_decl_source_by_token", AccessMode::ReadWrite),
]);

pub(in crate::type_checker) const VISIBLE_MATCH_DECL_MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.visible.mark_match_payload_decls",
    HirNodes,
    "type_checker/visible/03c2_scatter_match_payload_decls"
)
.with_modes(&[
    ("hir_value_decl_name_present", AccessMode::ReadWrite),
    ("hir_visible_decl_flag", AccessMode::ReadWrite),
    ("hir_visible_decl_source_by_token", AccessMode::ReadWrite),
]);

pub(in crate::type_checker) const VISIBLE_DECL_SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.visible.scatter_hir_decl_records",
    Tokens,
    "type_checker/visible/03c_scatter_hir_decls"
)
.with_modes(&[
    ("hir_visible_decl_source_by_token", AccessMode::ReadWrite),
    ("hir_visible_decl_owner_fn", AccessMode::Write),
    ("hir_visible_decl_name_id", AccessMode::Write),
    ("hir_visible_decl_token", AccessMode::Write),
    ("hir_visible_decl_scope_end", AccessMode::Write),
    ("hir_visible_decl_node", AccessMode::Write),
]);
