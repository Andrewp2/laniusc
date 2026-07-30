use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

const MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.names.mark_lexemes",
    Tokens,
    "type_checker/names/00_mark_lexemes"
)
.initializer();

const SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.names.scatter_lexemes",
    Tokens,
    "type_checker/names/01_scatter_lexemes"
)
.with_modes(&[
    ("name_spans", AccessMode::Write),
    ("name_id_by_token", AccessMode::Write),
])
.with_aliases(&[
    typecheck_resource!("name_order_in" => "name_hash_lo", Write),
    typecheck_resource!("name_order_tmp" => "name_hash_hi", Write),
    typecheck_resource!("name_count_out" => "name_scan_total", ReadWrite),
    typecheck_resource!("name_max_len_out" => "name_max_len", ReadWrite),
]);

pub(in crate::type_checker) const NAME_COMPACTION: CompactionSpec = CompactionSpec {
    mark: MARK,
    scan: super::super::compiler_graph::NAMES_SCAN,
    scatter: SCATTER,
};
