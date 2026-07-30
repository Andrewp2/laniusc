use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

pub(in crate::type_checker) const TYPE_INSTANCES_CLEAR: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_instance_arg_rows.clear",
    Tokens,
    "type_checker/type/instances/00_clear"
)
.initializer();

const MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_semantic.mark",
    HirNodes,
    "type_checker/type/instances/01i_mark_semantic_type_rows"
);

const SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_semantic.scatter",
    HirNodes,
    "type_checker/type/instances/01j_scatter_semantic_type_rows"
)
.with_modes(&[("type_semantic_row_by_ordinal", AccessMode::Write)]);

pub(in crate::type_checker) const TYPE_SEMANTIC_COMPACTION: CompactionSpec = CompactionSpec {
    mark: MARK,
    scan: super::super::compiler_graph::TYPE_SEMANTIC_SCAN,
    scatter: SCATTER,
};
