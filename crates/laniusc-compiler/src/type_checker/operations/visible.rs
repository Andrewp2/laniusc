use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

const MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.visible.mark_hir_decl_names",
    HirNodes,
    "type_checker/visible/03b_mark_hir_decl_names"
)
.with_modes(&[
    ("hir_value_decl_name_present", AccessMode::ReadWrite),
    ("hir_visible_decl_flag", AccessMode::Write),
]);

const SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.visible.scatter_hir_decl_records",
    Declarations,
    "type_checker/visible/03c_scatter_hir_decls"
)
.initializer();

pub(in crate::type_checker) const VISIBLE_DECL_COMPACTION: CompactionSpec = CompactionSpec {
    mark: MARK,
    scan: super::super::compiler_graph::VISIBLE_SCAN,
    scatter: SCATTER,
};
