use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

pub(in crate::type_checker) const TYPE_INSTANCES_CLEAR: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_instance_arg_rows.clear",
    Tokens,
    "type_checker/type/instances/00_clear"
)
.initializer();

const fn type_instance_collection(
    name: &'static str,
    kernel: &'static str,
) -> ReflectedComputeSpec {
    typecheck_pass!(name, HirNodes, kernel).with_indirect_dispatch("hir_active_dispatch_args")
}

pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_INITIAL: ReflectedComputeSpec =
    type_instance_collection(
        "type_check.type_instances.collect.initial.scalar",
        "type_checker/type/instances/01_collect",
    );
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_INITIAL_NAMED: ReflectedComputeSpec =
    type_instance_collection(
        "type_check.type_instances.collect.initial.named",
        "type_checker/type/instances/01b_collect_named_instances",
    );
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_REFS:
    ReflectedComputeSpec = type_instance_collection(
    "type_check.type_instances.collect.initial.aggregate_refs",
    "type_checker/type/instances/01c_collect_aggregate_refs",
);
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_DETAILS:
    ReflectedComputeSpec = type_instance_collection(
    "type_check.type_instances.collect.initial.aggregate_details",
    "type_checker/type/instances/01d_collect_aggregate_details",
);
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_PROJECTED: ReflectedComputeSpec =
    type_instance_collection(
        "type_check.type_instances.collect.projected.scalar",
        "type_checker/type/instances/01_collect",
    );
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_PROJECTED_NAMED: ReflectedComputeSpec =
    type_instance_collection(
        "type_check.type_instances.collect.projected.named",
        "type_checker/type/instances/01b_collect_named_instances",
    );
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_REFS:
    ReflectedComputeSpec = type_instance_collection(
    "type_check.type_instances.collect.projected.aggregate_refs",
    "type_checker/type/instances/01c_collect_aggregate_refs",
);
pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_DETAILS:
    ReflectedComputeSpec = type_instance_collection(
    "type_check.type_instances.collect.projected.aggregate_details",
    "type_checker/type/instances/01d_collect_aggregate_details",
);

pub(in crate::type_checker) const TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.type_instances.collect_named_arg_refs",
        HirNodes,
        "type_checker/type/instances/01e_collect_named_arg_refs"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

const fn declaration_refs(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(name, HirNodes, "type_checker/type/instances/01f_decl_refs")
        .with_indirect_dispatch("hir_active_dispatch_args")
}

pub(in crate::type_checker) const TYPE_INSTANCES_DECL_REFS: ReflectedComputeSpec =
    declaration_refs("type_check.type_instances.decl_refs");
pub(in crate::type_checker) const TYPE_INSTANCES_DECL_REFS_FOR_BINDINGS: ReflectedComputeSpec =
    declaration_refs("type_check.type_instances.decl_refs.for_bindings");

pub(in crate::type_checker) const CALLS_INFER_ARRAY_GENERICS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.calls.infer_array_generics",
    HirNodes,
    "type_checker/calls/03b_infer_array_generics"
);

pub(in crate::type_checker) const TYPE_INSTANCES_ARRAY_RETURN_REFS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.type_instances.array_return_refs",
        HirNodes,
        "type_checker/type/instances/05_array_return_refs"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const TYPE_INSTANCES_ARRAY_LITERAL_RETURN_REFS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.type_instances.array_literal_return_refs",
        HirNodes,
        "type_checker/type/instances/05b_array_literal_return_refs"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

const MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_semantic.mark",
    HirNodes,
    "type_checker/type/instances/01i_mark_semantic_type_rows"
)
.with_indirect_dispatch("hir_active_dispatch_args");

const SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.type_semantic.scatter",
    HirNodes,
    "type_checker/type/instances/01j_scatter_semantic_type_rows"
)
.with_modes(&[("type_semantic_row_by_ordinal", AccessMode::Write)])
.with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const TYPE_SEMANTIC_COMPACTION: CompactionSpec = CompactionSpec {
    mark: MARK,
    scan: super::super::compiler_graph::TYPE_SEMANTIC_SCAN,
    scatter: SCATTER,
};
