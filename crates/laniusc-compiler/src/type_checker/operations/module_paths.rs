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
)
.with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const PATH_STATE_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.paths.clear",
    HirNodes,
    "type_checker/modules/01a_clear_path_state";
    writes [
        "path_id_by_owner_hir",
        "path_id_by_owner_token",
        "path_max_segment_count",
    ]
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

pub(in crate::type_checker) const PATH_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.path_dispatch_args",
    DispatchArguments,
    "type_checker/modules/01a_path_dispatch_args";
    writes ["path_count_out", "path_dispatch_args"]
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
)
.with_indirect_dispatch("path_dispatch_args");

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

pub(in crate::type_checker) const PATH_PREFIX_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.path_prefix_dispatch_args",
    DispatchArguments,
    "type_checker/modules/01c_path_prefix_dispatch_args";
    writes ["path_prefix_row_dispatch_args", "path_prefix_round_dispatch_args"]
);
pub(in crate::type_checker) const PATH_PREFIX_TABLE_CLEAR: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.path_prefix_table_clear",
        Tokens,
        "type_checker/modules/01c_path_prefix_table_clear";
        writes ["path_prefix_table_state"]
    )
    .with_indirect_dispatch("path_prefix_row_dispatch_args");
pub(in crate::type_checker) const PATH_PREFIX_INTERN_A_TO_B: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.path_prefix_table_intern.a_to_b",
        Tokens,
        "type_checker/modules/01c_path_prefix_table_insert";
        resources [
            typecheck_resource!("path_prefix_id_in" => "path_prefix_id_a", Read),
            typecheck_resource!("path_prefix_id_out" => "path_prefix_id_b", Write),
            typecheck_resource!("path_prefix_table_state" => "path_prefix_table_state", ReadWrite),
        ]
    )
    .with_indirect_dispatch("path_prefix_round_dispatch_args");
pub(in crate::type_checker) const PATH_PREFIX_INTERN_B_TO_A: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.path_prefix_table_intern.b_to_a",
        Tokens,
        "type_checker/modules/01c_path_prefix_table_insert";
        resources [
            typecheck_resource!("path_prefix_id_in" => "path_prefix_id_b", Read),
            typecheck_resource!("path_prefix_id_out" => "path_prefix_id_a", Write),
            typecheck_resource!("path_prefix_table_state" => "path_prefix_table_state", ReadWrite),
        ]
    )
    .with_indirect_dispatch("path_prefix_round_dispatch_args");
pub(in crate::type_checker) const PATH_PREFIX_FINALIZE: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.path_prefix_finalize",
        Tokens,
        "type_checker/modules/01c_path_prefix_finalize";
        resources [typecheck_resource!("path_prefix_id_a" => "path_prefix_id_a", ReadWrite)]
    )
    .with_indirect_dispatch("path_prefix_row_dispatch_args");

pub(in crate::type_checker) const MODULE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_module_lookup",
    Declarations,
    "type_checker/modules/02d_clear_module_lookup";
    writes ["module_by_canonical_id"]
);

pub(in crate::type_checker) const MODULE_KEYS_BUILD: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.build_module_keys",
    Declarations,
    "type_checker/modules/02e_build_module_keys";
    writes [
        "module_status",
        "module_key_canonical_id",
        "module_key_segment_count",
        "module_key_segment_base",
    ]
);

pub(in crate::type_checker) const MODULE_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.module_dispatch_args",
    DispatchArguments,
    "type_checker/count/dispatch_args"
    ; resources [
        typecheck_resource!("count_in" => "module_count_out", Read),
        typecheck_resource!("dispatch_args" => "module_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const MODULES_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_modules",
    Declarations,
    "type_checker/modules/04_validate_modules"
)
.with_indirect_dispatch("module_dispatch_args");

pub(in crate::type_checker) const IMPORT_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_dispatch_args",
    DispatchArguments,
    "type_checker/count/dispatch_args"
    ; resources [
        typecheck_resource!("count_in" => "import_record_count_out", Read),
        typecheck_resource!("dispatch_args" => "import_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const VARIANT_DECL_COUNT_APPEND: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.append_variant_decl_count",
    Declarations,
    "type_checker/modules/02c1_append_variant_decl_count"
);

pub(in crate::type_checker) const DECL_RECORD_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_decl_lookup",
    Tokens,
    "type_checker/modules/02d/clear_decl_lookup";
    writes ["decl_id_by_name_token"]
);

pub(in crate::type_checker) const DECL_SPAN_RECORDS_SCATTER: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.scatter_decl_span_records",
        HirNodes,
        "type_checker/modules/02d/scatter_decl_span_records";
            writes [
                "decl_name_token",
                "decl_token_start",
                "decl_token_end",
                "decl_id_by_name_token",
            ]
            ; resources [
                typecheck_resource!("decl_record_flag" => "module_record_family_flag", Read),
                typecheck_resource!("decl_record_prefix" => "module_record_prefix", Read),
            ]
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const VARIANT_DECL_RECORDS_SCATTER: ReflectedComputeSpec = typecheck_operation!(
"type_check.modules.scatter_variant_decl_records",
Declarations,
"type_checker/modules/02c2_scatter_variant_decl_records";
writes [
    "decl_module_file_id",
    "decl_name_token",
    "decl_name_id",
    "decl_kind",
    "decl_namespace",
    "decl_visibility",
    "decl_hir_node",
    "decl_parent_type_decl",
    "decl_token_start",
        "decl_token_end",
        "decl_id_by_name_token",
    ]
    ; resources [
        typecheck_resource!("decl_record_flag" => "module_record_family_flag", Read),
        typecheck_resource!("decl_record_prefix" => "module_record_prefix", Read),
    ]
);

pub(in crate::type_checker) const DECL_KEY_RADIX_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_key_radix_dispatch_args",
    DispatchArguments,
    "radix/dispatch_args"
    ; resources [
        typecheck_resource!("name_count_in" => "decl_count_out", Read),
        typecheck_resource!("radix_dispatch_args" => "decl_key_radix_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const DECLS_VALIDATE: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.validate_decls",
    Declarations,
    "type_checker/modules/07_validate_decls"
    ; resources [
        typecheck_resource!("decl_status" => "decl_status", Write),
        typecheck_resource!(
            "decl_duplicate_of" => "type_decl_generic_param_count_by_owner_token",
            Write
        ),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_NAMESPACE_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_namespace.mark",
    Declarations,
    "type_checker/modules/08_mark_decl_namespace_keys"
    ; resources [
        typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
        typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Write),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_NAMESPACE_SCATTER: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.decl_namespace.scatter",
        Declarations,
        "type_checker/modules/08b_scatter_decl_namespace_keys"
        ; writes ["decl_type_key_to_decl_id", "decl_value_key_to_decl_id"]
        ; resources [
            typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
            typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Read),
            typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Read),
        ]
    )
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.declarations.clear_lookup",
    Declarations,
    "type_checker/modules/08c_clear_decl_lookup";
    writes ["decl_lookup_state"]
);
pub(in crate::type_checker) const DECL_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.declarations.build_lookup",
    Declarations,
    "type_checker/modules/08d_build_decl_lookup";
    resources [typecheck_resource!("decl_lookup_state" => "decl_lookup_state", ReadWrite)]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_DUPLICATES_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.decl_namespace.validate_duplicates",
    Declarations,
    "type_checker/modules/08e_validate_decl_duplicates"
)
.with_aliases(&[typecheck_resource!(
    "decl_duplicate_of" => "type_decl_generic_param_count_by_owner_token",
    Write
)])
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_PUBLIC_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_public.mark",
    Declarations,
    "type_checker/modules/08c_mark_public_decl_keys"
    ; resources [
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Write),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const INTERFACE_PUBLIC_DECLS_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.interface.public_decls.clear",
    Declarations,
    "type_checker/interface/public_decls/00_clear";
    writes [
        "interface_public_decl_count",
        "interface_public_decl_local_id",
        "interface_public_decl_index_by_local",
        "interface_public_decl_index_by_hir",
    ]
);

pub(in crate::type_checker) const INTERFACE_PUBLIC_DECLS_MAP: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.interface.public_decls.map",
        Declarations,
        "type_checker/interface/public_decls/01_map"
    )
    .with_aliases(&[
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Read),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Read),
        typecheck_resource!("decl_type_public_prefix" => "decl_status", Read),
        typecheck_resource!(
            "decl_value_public_prefix" => "type_decl_generic_param_count_by_owner_token",
            Read
        ),
    ])
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const FILE_MODULE_MAP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.file_module_map.clear",
    Declarations,
    "type_checker/modules/05b_clear_file_module_map"
    ; writes ["module_id_by_file_id", "decl_module_id", "import_module_id", "path_owner_module_id"]
    ; resources [typecheck_resource!("import_count_out" => "import_record_count_out", Read)]
);

pub(in crate::type_checker) const FILE_MODULE_MAP_BUILD: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.file_module_map.build",
        Declarations,
        "type_checker/modules/05c_build_file_module_map"
        ; writes ["module_id_by_file_id"]
    )
    .with_indirect_dispatch("module_dispatch_args");

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
)
.with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_EDGE_SET_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_edges.clear",
    Declarations,
    "type_checker/modules/05e_clear_import_edge_set";
    writes ["import_edge_set_state"]
);

pub(in crate::type_checker) const IMPORT_EDGE_SET_BUILD: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.import_edges.build",
        Declarations,
        "type_checker/modules/05f_build_import_edge_set";
        resources [
            typecheck_resource!("import_count_out" => "import_record_count_out", Read),
            typecheck_resource!("import_edge_set_state" => "import_edge_set_state", ReadWrite),
        ]
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_CYCLES_VALIDATE: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.import_cycles.validate",
        Declarations,
        "type_checker/modules/05h_validate_import_cycles";
        resources [
            typecheck_resource!("import_count_out" => "import_record_count_out", Read),
            typecheck_resource!("import_status" => "import_status", ReadWrite),
            typecheck_resource!("status" => "status", ReadWrite),
        ]
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_VISIBILITY_COUNT: ReflectedComputeSpec =
    typecheck_operation!(
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
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_VISIBLE_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visible_dispatch_args",
    DispatchArguments,
    "type_checker/count/pair_max_dispatch_args"
    ; resources [
        typecheck_resource!("left_count_in" => "import_visible_type_count_out", Read),
        typecheck_resource!("right_count_in" => "import_visible_value_count_out", Read),
        typecheck_resource!("dispatch_args" => "import_visible_validate_dispatch_args", Write),
    ]
);

const IMPORT_VISIBLE_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count" => "import_visible_type_count", Read),
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_prefix" => "import_visible_type_prefix", Read),
    typecheck_resource!("decl_key_count_out" => "decl_type_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_type_key_to_decl_id", Read),
    typecheck_resource!("decl_public_flag" => "type_instance_arg_ref_tag", Read),
    typecheck_resource!("decl_public_prefix" => "decl_status", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Write),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Write),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Write),
];
const IMPORT_VISIBLE_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count" => "import_visible_value_count", Read),
    typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
    typecheck_resource!("import_visible_prefix" => "import_visible_value_prefix", Read),
    typecheck_resource!("decl_key_count_out" => "decl_value_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_value_key_to_decl_id", Read),
    typecheck_resource!("decl_public_flag" => "type_instance_arg_ref_payload", Read),
    typecheck_resource!(
        "decl_public_prefix" => "type_decl_generic_param_count_by_owner_token", Read
    ),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Write),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Write),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Write),
];

pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.scatter_type",
        Declarations,
        "type_checker/modules/09b_scatter_import_visibility"
    )
    .with_aliases(IMPORT_VISIBLE_TYPE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.scatter_value",
        Declarations,
        "type_checker/modules/09b_scatter_import_visibility"
    )
    .with_aliases(IMPORT_VISIBLE_VALUE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");

const IMPORT_VISIBLE_TYPE_LOOKUP_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", ReadWrite),
];
const IMPORT_VISIBLE_VALUE_LOOKUP_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[
        typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
        typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Read),
        typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Read),
        typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Read),
        typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", ReadWrite),
    ];

pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visibility.clear_type_lookup",
    Declarations,
    "type_checker/modules/09c_clear_import_visible_lookup";
    resources [typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", Write)]
);
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visibility.clear_value_lookup",
    Declarations,
    "type_checker/modules/09c_clear_import_visible_lookup";
    resources [typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", Write)]
);
pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_LOOKUP_BUILD: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.build_type_lookup",
        Declarations,
        "type_checker/modules/09e_build_import_visible_key_tables"
    )
    .with_aliases(IMPORT_VISIBLE_TYPE_LOOKUP_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_LOOKUP_BUILD: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.build_value_lookup",
        Declarations,
        "type_checker/modules/09e_build_import_visible_key_tables"
    )
    .with_aliases(IMPORT_VISIBLE_VALUE_LOOKUP_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
const IMPORT_VISIBLE_STATUS_INITIALIZE_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_type_status" => "import_visible_type_status", Write),
    typecheck_resource!("import_visible_type_duplicate_of" => "import_visible_type_duplicate_of", Write),
    typecheck_resource!("import_visible_value_status" => "import_visible_value_status", Write),
    typecheck_resource!("import_visible_value_duplicate_of" => "import_visible_value_duplicate_of", Write),
];
const IMPORT_VISIBLE_STATUS_VALIDATE_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_type_status" => "import_visible_type_status", ReadWrite),
    typecheck_resource!("import_visible_type_duplicate_of" => "import_visible_type_duplicate_of", ReadWrite),
    typecheck_resource!("import_visible_value_status" => "import_visible_value_status", ReadWrite),
    typecheck_resource!("import_visible_value_duplicate_of" => "import_visible_value_duplicate_of", ReadWrite),
];
pub(in crate::type_checker) const IMPORT_VISIBLE_STATUS_INITIALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.initialize_status",
        Declarations,
        "type_checker/modules/09f_validate_import_visible_keys"
    )
    .with_aliases(IMPORT_VISIBLE_STATUS_INITIALIZE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_AMBIGUITY_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.validate_ambiguity",
        Declarations,
        "type_checker/modules/09f_validate_import_visible_keys"
    )
    .with_aliases(IMPORT_VISIBLE_STATUS_VALIDATE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");

const RESOLVE_LOCAL_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_LOCAL_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_LOCAL_TYPE_PATHS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.paths.resolve_local_type",
    HirNodes,
    "type_checker/modules/10_resolve_local_paths"
)
.with_aliases(RESOLVE_LOCAL_TYPE_ALIASES)
.with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_LOCAL_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_local_value",
        HirNodes,
        "type_checker/modules/10_resolve_local_paths"
    )
    .with_aliases(RESOLVE_LOCAL_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

const RESOLVE_IMPORTED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_type_status", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_type_status", ReadWrite),
];
const RESOLVE_IMPORTED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_value_status", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_value_status", ReadWrite),
];

pub(in crate::type_checker) const RESOLVE_IMPORTED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_type",
        HirNodes,
        "type_checker/modules/10b_resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_TYPE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_IMPORTED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_value",
        HirNodes,
        "type_checker/modules/10b_resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

const RESOLVE_QUALIFIED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_QUALIFIED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_QUALIFIED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_type",
        HirNodes,
        "type_checker/modules/10c_resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_TYPE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_QUALIFIED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_value",
        HirNodes,
        "type_checker/modules/10c_resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const TYPE_PATH_STATE_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_type_path_types",
    Tokens,
    "type_checker/modules/10d_clear_type_path_types";
    writes [
        "module_type_path_type",
        "module_type_path_status",
        "module_value_path_expr_head",
        "module_value_path_call_head",
        "module_value_path_call_open",
        "module_value_path_call_path_id",
        "module_value_path_call_leaf",
        "module_value_path_associated_method_token",
        "module_value_path_associated_receiver_token",
        "module_value_path_const_head",
        "module_value_path_const_end",
        "module_value_path_status",
    ]
);

const fn type_path_projection(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/10e_project_type_paths"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

pub(in crate::type_checker) const TYPE_PATHS_PROJECT: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths").with_modes(&[
        ("type_expr_ref_tag", AccessMode::Write),
        ("type_expr_ref_payload", AccessMode::Write),
    ]);
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_ALIASES: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_aliases");
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_PROJECTED_ALIASES: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_projected_aliases");
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_ALIAS_EQUIVALENCE: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_alias_equivalence");

pub(in crate::type_checker) const TYPE_ALIAS_FORWARDING_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_type_alias_forwarding",
    HirNodes,
    "type_checker/modules/10e0_clear_type_alias_forwarding";
    writes [
        "alias_forwarding",
        "alias_forwarding_target_decl",
        "alias_forwarding_valid_arg_count",
        "alias_decl_by_target_hir",
    ]
);
pub(in crate::type_checker) const TYPE_ALIAS_FORWARDING_INITIALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.init_type_alias_forwarding",
        Declarations,
        "type_checker/modules/10e0a_init_type_alias_forwarding"
    )
    .with_indirect_dispatch("decl_key_radix_dispatch_args");
pub(in crate::type_checker) const TYPE_ALIAS_FORWARDING_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_type_alias_forwarding_args",
    HirNodes,
    "type_checker/modules/10e0b_validate_type_alias_forwarding_args"
);

const TYPE_ALIAS_ROOT_INITIALIZE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[typecheck_resource!("alias_root_decl" => "alias_root_a", Write)];
pub(in crate::type_checker) const TYPE_ALIAS_ROOT_INITIALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.init_type_alias_roots",
        Declarations,
        "type_checker/modules/10e1_init_type_alias_roots"
    )
    .with_aliases(TYPE_ALIAS_ROOT_INITIALIZE_ALIASES)
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

const TYPE_ALIAS_ROOT_JUMP_A_TO_B_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[
        typecheck_resource!("alias_root_decl_in" => "alias_root_a", Read),
        typecheck_resource!("alias_root_decl_out" => "alias_root_b", Write),
    ];
const TYPE_ALIAS_ROOT_JUMP_B_TO_A_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[
        typecheck_resource!("alias_root_decl_in" => "alias_root_b", Read),
        typecheck_resource!("alias_root_decl_out" => "alias_root_a", Write),
    ];
pub(in crate::type_checker) const TYPE_ALIAS_ROOT_JUMP_A_TO_B: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_roots.a_to_b",
        Declarations,
        "type_checker/modules/10e1a_jump_type_alias_roots"
    )
    .with_aliases(TYPE_ALIAS_ROOT_JUMP_A_TO_B_ALIASES)
    .with_indirect_dispatch("decl_key_radix_dispatch_args");
pub(in crate::type_checker) const TYPE_ALIAS_ROOT_JUMP_B_TO_A: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_roots.b_to_a",
        Declarations,
        "type_checker/modules/10e1a_jump_type_alias_roots"
    )
    .with_aliases(TYPE_ALIAS_ROOT_JUMP_B_TO_A_ALIASES)
    .with_indirect_dispatch("decl_key_radix_dispatch_args");
pub(in crate::type_checker) const TYPE_ALIAS_ROOT_JUMP_FINAL_A_TO_B: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_roots.final_a_to_b",
        Declarations,
        "type_checker/modules/10e1a_jump_type_alias_roots"
    )
    .with_aliases(TYPE_ALIAS_ROOT_JUMP_A_TO_B_ALIASES)
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_type_alias_equivalence",
    HirNodes,
    "type_checker/modules/10e0c_clear_type_alias_equivalence";
    writes [
        "alias_equiv_parent_a",
        "alias_equiv_parent_b",
        "alias_equiv_edge_0",
        "alias_equiv_edge_1",
        "alias_equiv_component_source",
        "alias_normalized_source",
    ]
);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_DECL_EDGES_INITIALIZE:
    ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.init_type_alias_decl_edges",
    Declarations,
    "type_checker/modules/10e0d_init_type_alias_decl_edges"
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_ARG_EDGES_INITIALIZE:
    ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.init_type_alias_arg_edges",
    HirNodes,
    "type_checker/modules/10e0e_init_type_alias_arg_edges"
);

const TYPE_ALIAS_EQUIVALENCE_HOOK_A_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[typecheck_resource!("alias_equiv_parent" => "alias_equiv_parent_a", ReadWrite)];
const TYPE_ALIAS_EQUIVALENCE_HOOK_B_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[typecheck_resource!("alias_equiv_parent" => "alias_equiv_parent_b", ReadWrite)];
const TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("alias_equiv_parent_in" => "alias_equiv_parent_a", Read),
    typecheck_resource!("alias_equiv_parent_out" => "alias_equiv_parent_b", Write),
];
const TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("alias_equiv_parent_in" => "alias_equiv_parent_b", Read),
    typecheck_resource!("alias_equiv_parent_out" => "alias_equiv_parent_a", Write),
];
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_HOOK_A: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.hook_type_alias_equivalence.a",
        HirNodes,
        "type_checker/modules/10e0f_hook_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_HOOK_A_ALIASES);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_equivalence.a_to_b",
        HirNodes,
        "type_checker/modules/10e0g_jump_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B_ALIASES);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_HOOK_B: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.hook_type_alias_equivalence.b",
        HirNodes,
        "type_checker/modules/10e0f_hook_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_HOOK_B_ALIASES);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_equivalence.b_to_a",
        HirNodes,
        "type_checker/modules/10e0g_jump_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A_ALIASES);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_FINAL_HOOK_A: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.hook_type_alias_equivalence.final_a",
        HirNodes,
        "type_checker/modules/10e0f_hook_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_HOOK_A_ALIASES);
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_FINAL_JUMP_A_TO_B: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.jump_type_alias_equivalence.final_a_to_b",
        HirNodes,
        "type_checker/modules/10e0g_jump_type_alias_equivalence"
    )
    .with_aliases(TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B_ALIASES);

pub(in crate::type_checker) const TYPE_ALIAS_GENERIC_SOURCES_SELECT_PASS: &str =
    "type_check.modules.select_type_alias_generic_sources";
pub(in crate::type_checker) const TYPE_ALIAS_CONCRETE_SOURCES_SELECT_PASS: &str =
    "type_check.modules.select_type_alias_concrete_sources";
pub(in crate::type_checker) const TYPE_ALIAS_EQUIVALENCE_FINALIZE_PASS: &str =
    "type_check.modules.finalize_type_alias_equivalence";
pub(in crate::type_checker) const TYPE_ALIAS_PROJECT_PASS: &str =
    "type_check.modules.project_type_aliases";
pub(in crate::type_checker) const TYPE_ALIAS_PROJECT_AFTER_PROJECTED_REFS_PASS: &str =
    "type_check.modules.project_type_aliases.after_projected_refs";
pub(in crate::type_checker) const TYPE_ALIAS_INSTANCES_PROJECT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.project_type_alias_instances",
        HirNodes,
        "type_checker/modules/10e0k_project_type_alias_instances"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const TYPE_INSTANCES_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.project_type_instances",
    HirNodes,
    "type_checker/modules/10k_project_type_instances"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const VALUE_CALL_PATHS_MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.mark_value_call_paths",
    HirNodes,
    "type_checker/modules/10f_mark_value_call_paths"
);

pub(in crate::type_checker) const VALUE_PATHS_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.project_value_paths",
    HirNodes,
    "type_checker/modules/10g_project_value_paths"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const TYPE_PATHS_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_type_paths",
    HirNodes,
    "type_checker/modules/10e3_validate_type_paths"
)
.with_indirect_dispatch("path_dispatch_args");

const fn consume_value_calls(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/10h_consume_value_calls"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

const fn mirror_value_call_leaf(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/10h2_mirror_value_call_leaf"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

pub(in crate::type_checker) const VALUE_CALLS_CONSUME: ReflectedComputeSpec =
    consume_value_calls("type_check.modules.consume_value_calls");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_ROW_ARGS: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf_after_module_row_args");
pub(in crate::type_checker) const VALUE_CALLS_CONSUME_AFTER_METHODS: ReflectedComputeSpec =
    consume_value_calls("type_check.modules.consume_value_calls_after_methods");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_METHODS: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf_after_methods");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_METHOD_ROW_ARGS:
    ReflectedComputeSpec = mirror_value_call_leaf(
    "type_check.modules.mirror_value_call_leaf_after_methods_module_row_args",
);
pub(in crate::type_checker) const VALUE_CONSTS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_consts",
    HirNodes,
    "type_checker/modules/10i_consume_value_consts"
)
.with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const VALUE_ENUM_UNITS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_enum_units",
    HirNodes,
    "type_checker/modules/10j_consume_value_enum_units"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const MATCH_PATTERNS_BIND: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.bind_match_patterns",
    HirNodes,
    "type_checker/modules/10m_bind_match_patterns"
)
.with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const MATCH_PAYLOADS_TYPE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.type_match_payloads",
    HirNodes,
    "type_checker/modules/10m2_type_match_payloads"
)
.with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const VALUE_ENUM_CALLS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_enum_calls",
    HirNodes,
    "type_checker/modules/10l_consume_value_enum_calls"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const VALUE_ENUM_CALL_PAYLOADS_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_value_enum_call_payloads",
    HirNodes,
    "type_checker/modules/10l2_validate_value_enum_call_payloads"
);

pub(in crate::type_checker) const VALUE_ENUM_CALLS_FINALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.finalize_value_enum_calls",
        HirNodes,
        "type_checker/modules/10l3_finalize_value_enum_calls"
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const MATCH_EXPRS_TYPE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.type_match_exprs",
    HirNodes,
    "type_checker/modules/10n_type_match_exprs"
)
.with_indirect_dispatch("hir_active_dispatch_args");

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
    .with_indirect_dispatch("hir_active_dispatch_args")
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
            .with_aliases($aliases)
            .with_indirect_dispatch("hir_active_dispatch_args");
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
