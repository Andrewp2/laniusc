use crate::gpu::compiler_graph::{AccessMode, CompactionSpec, ReflectedComputeSpec};

/// Discovers the compact-HIR rows which participate in module/path relations.
///
/// The shader calls its output `record_family_bits`; the compiler graph uses a
/// phase-qualified name because the allocation is shared with the complete
/// module-record scan operation.
pub(in crate::type_checker) const MODULE_RECORDS_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.records.mark",
    HirNodes,
    "type_checker/modules/00_mark_records"
    ; resources [typecheck_resource!("record_family_bits" => "module_record_family_bits", Write)]
);

pub(in crate::type_checker) const PATH_STATE_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.paths.clear",
    HirNodes,
    "type_checker/modules/01a_clear_path_state";
    writes ["path_id_by_owner_hir", "path_max_segment_count"]
);

pub(in crate::type_checker) const PATHS_SCATTER: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.paths.scatter",
    HirNodes,
    "type_checker/modules/01_scatter_paths";
    writes [
        "path_owner_hir",
        "path_len",
        "path_call_hir",
        "path_owner_token",
        "path_id_by_owner_hir",
        "path_id_by_owner_token",
        "path_kind",
        "path_count_out",
    ]
);

pub(in crate::type_checker) const PATH_SEGMENTS_COUNT: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.path_segments.count",
    HirNodes,
    "type_checker/modules/01b/count_path_segments";
    writes [
        "path_segment_base",
        "path_segment_count",
        "path_segment_count_out",
        "path_max_segment_count",
    ]
);

pub(in crate::type_checker) const PATH_SEGMENTS_SCATTER: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.path_segments.scatter",
    Tokens,
    "type_checker/modules/01b/scatter_path_segments";
    writes [
        "path_segment_name_id",
        "path_segment_token",
        "path_prefix_base",
        "path_prefix_id_a",
        "predicate_syntax_token",
    ]
);

pub(in crate::type_checker) const DECL_NAMESPACE_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_namespace.mark",
    Declarations,
    "type_checker/modules/08_mark_decl_namespace_keys"
    ; resources [
        typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
        typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Write),
    ]
);

pub(in crate::type_checker) const DECL_NAMESPACE_SCATTER: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_namespace.scatter",
    Declarations,
    "type_checker/modules/08b_scatter_decl_namespace_keys"
    ; writes ["decl_type_key_to_decl_id", "decl_value_key_to_decl_id"]
    ; resources [
        typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
        typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Read),
        typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Read),
    ]
);

pub(in crate::type_checker) const DECL_PUBLIC_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_public.mark",
    Declarations,
    "type_checker/modules/08c_mark_public_decl_keys"
    ; resources [
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Write),
    ]
);

pub(in crate::type_checker) const FILE_MODULE_MAP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.file_module_map.clear",
    Declarations,
    "type_checker/modules/05b_clear_file_module_map"
    ; writes ["module_id_by_file_id", "decl_module_id", "import_module_id", "path_owner_module_id"]
    ; resources [typecheck_resource!("import_count_out" => "import_record_count_out", Read)]
);

pub(in crate::type_checker) const FILE_MODULE_MAP_BUILD: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.file_module_map.build",
    Declarations,
    "type_checker/modules/05c_build_file_module_map"
    ; writes ["module_id_by_file_id"]
);

pub(in crate::type_checker) const ATTACH_RECORD_MODULES: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.records.attach_modules",
    Declarations,
    "type_checker/modules/05d_attach_record_modules"
    ; writes ["decl_module_id", "import_module_id", "path_owner_module_id"]
    ; resources [
        typecheck_resource!("import_count_out" => "import_record_count_out", Read),
        typecheck_resource!("module_count_out" => "module_record_count_out", Read),
    ]
);

pub(in crate::type_checker) const RESOLVE_IMPORTS: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.imports.resolve",
    Declarations,
    "type_checker/modules/05_resolve_imports"
    ; writes ["import_target_module_id", "import_status"]
    ; resources [
        typecheck_resource!("status" => "status", ReadWrite),
        typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    ]
);

pub(in crate::type_checker) const IMPORT_VISIBILITY_COUNT: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visibility.count",
    Declarations,
    "type_checker/modules/09_count_import_visibility"
    ; writes ["import_visible_type_count", "import_visible_value_count"]
    ; resources [
        typecheck_resource!("import_count_out" => "import_record_count_out", Read),
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Read),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Read),
        typecheck_resource!("decl_type_public_prefix" => "decl_status", Read),
        typecheck_resource!(
            "decl_value_public_prefix" => "type_decl_generic_param_count_by_owner_token", Read
        ),
    ]
);

const RESOLVE_LOCAL_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("decl_key_count_out" => "decl_type_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_type_key_to_decl_id", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_LOCAL_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("decl_key_count_out" => "decl_value_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_value_key_to_decl_id", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_LOCAL_TYPE_PATHS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.paths.resolve_local_type",
    HirNodes,
    "type_checker/modules/10_resolve_local_paths"
)
.with_aliases(RESOLVE_LOCAL_TYPE_ALIASES);
pub(in crate::type_checker) const RESOLVE_LOCAL_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_local_value",
        HirNodes,
        "type_checker/modules/10_resolve_local_paths"
    )
    .with_aliases(RESOLVE_LOCAL_VALUE_ALIASES);

const RESOLVE_IMPORTED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_type_status", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_type_status", ReadWrite),
];
const RESOLVE_IMPORTED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_value_status", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_value_status", ReadWrite),
];

pub(in crate::type_checker) const RESOLVE_IMPORTED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_type",
        HirNodes,
        "type_checker/modules/10b_resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_TYPE_ALIASES);
pub(in crate::type_checker) const RESOLVE_IMPORTED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_value",
        HirNodes,
        "type_checker/modules/10b_resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_VALUE_ALIASES);

const RESOLVE_QUALIFIED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("decl_key_count_out" => "decl_type_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_type_key_to_decl_id", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_QUALIFIED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("decl_key_count_out" => "decl_value_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_value_key_to_decl_id", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_QUALIFIED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_type",
        HirNodes,
        "type_checker/modules/10c_resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_TYPE_ALIASES);
pub(in crate::type_checker) const RESOLVE_QUALIFIED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_value",
        HirNodes,
        "type_checker/modules/10c_resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_VALUE_ALIASES);

const RECORD_FLAG_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("record_family_bits" => "module_record_family_bits", Read),
    typecheck_resource!("record_family_flag" => "module_record_family_flag", Write),
];

const fn record_flag(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/00b_extract_record_flag"
    )
    .with_aliases(RECORD_FLAG_ALIASES)
}

pub(in crate::type_checker) const MODULE_RECORD_FLAG: ReflectedComputeSpec =
    record_flag("type_check.modules.records.module_flag");
pub(in crate::type_checker) const IMPORT_RECORD_FLAG: ReflectedComputeSpec =
    record_flag("type_check.modules.records.import_flag");
pub(in crate::type_checker) const DECL_RECORD_FLAG: ReflectedComputeSpec =
    record_flag("type_check.modules.records.decl_flag");

macro_rules! record_compaction {
    (
        $aliases:ident, $scatter:ident, $operation:ident,
        $flag:ident, $scan:expr,
        $record:literal, $kernel:literal,
        [$($output:literal),+ $(,)?]
    ) => {
        const $aliases: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
            typecheck_resource!(concat!($record, "_record_flag") => "module_record_family_flag", Read),
            typecheck_resource!(concat!($record, "_record_prefix") => "module_record_prefix", Read),
        ];
        pub(in crate::type_checker) const $scatter: ReflectedComputeSpec = typecheck_pass!(
            concat!("type_check.modules.records.", $record, "_scatter"),
            HirNodes,
            $kernel
        )
        .with_modes(&[$(($output, AccessMode::Write)),+])
        .with_aliases($aliases);
        pub(in crate::type_checker) const $operation: CompactionSpec = CompactionSpec {
            mark: $flag,
            scan: $scan,
            scatter: $scatter,
        };
    };
}

record_compaction!(
    MODULE_RECORD_ALIASES,
    MODULE_RECORDS_SCATTER,
    MODULE_RECORD_COMPACTION,
    MODULE_RECORD_FLAG,
    super::super::compiler_graph::MODULE_RECORD_SCAN,
    "module",
    "type_checker/modules/02_scatter_module_records",
    ["module_file_id", "module_path_id", "module_owner_hir"]
);
record_compaction!(
    IMPORT_RECORD_ALIASES,
    IMPORT_RECORDS_SCATTER,
    IMPORT_RECORD_COMPACTION,
    IMPORT_RECORD_FLAG,
    super::super::compiler_graph::IMPORT_RECORD_SCAN,
    "import",
    "type_checker/modules/02b_scatter_import_records",
    [
        "import_module_file_id",
        "import_path_id",
        "import_kind",
        "import_owner_hir",
    ]
);
record_compaction!(
    DECL_RECORD_ALIASES,
    DECL_RECORDS_SCATTER,
    DECL_RECORD_COMPACTION,
    DECL_RECORD_FLAG,
    super::super::compiler_graph::DECL_RECORD_SCAN,
    "decl",
    "type_checker/modules/02c_scatter_decl_core_records",
    [
        "decl_module_file_id",
        "decl_name_id",
        "decl_kind",
        "decl_namespace",
        "decl_visibility",
        "decl_hir_node",
        "decl_parent_type_decl",
    ]
);
